import Foundation

struct SpeechActivityConfiguration {
    var sampleRate: Double = 16_000
    var frameDuration: TimeInterval = 0.03
    var frameStride: TimeInterval = 0.01

    var earlyAcceptMinimumActiveDuration: TimeInterval = 0.20
    var earlyAcceptMinimumConsecutiveActiveDuration: TimeInterval = 0.12
    var earlyAcceptMinimumFrameRMSDBFS: Float = -38
    var earlyAcceptMinimumFramePeakDBFS: Float = -28

    var noiseFloorPercentile: Float = 0.20
    var activeFrameDBAboveNoiseFloor: Float = 10
    var minimumActiveFrameRMSDBFS: Float = -52
    var minimumActiveFramePeakDBFS: Float = -48
    var minimumRecordingRMSDBFS: Float = -72
    var minimumRecordingPeakDBFS: Float = -60
    var minimumSNRDB: Float = 8
    var minimumActiveSpeechDuration: TimeInterval = 0.20
    var minimumConsecutiveActiveSpeechDuration: TimeInterval = 0.10
    var minimumActiveFrameRatio: Float = 0.015
    var minimumActiveSpeechDurationWhenRatioIsLow: TimeInterval = 0.45

    var noSpeechFeedbackMinimumDuration: TimeInterval = 1.25
}

struct SpeechActivityResult {
    enum Decision: String {
        case acceptedEarly
        case acceptedAfterFullAnalysis
        case rejectedAsNoSpeech
    }

    let decision: Decision
    let duration: TimeInterval
    let analyzedDuration: TimeInterval
    let activeSpeechDuration: TimeInterval
    let longestConsecutiveActiveSpeechDuration: TimeInterval
    let activeFrameRatio: Float
    let rmsDBFS: Float
    let peakDBFS: Float
    let noiseFloorDBFS: Float
    let activeRMSDBFS: Float
    let snrDB: Float
    let shouldShowNoSpeechMessage: Bool

    var shouldTranscribe: Bool {
        decision == .acceptedEarly || decision == .acceptedAfterFullAnalysis
    }
}

extension SpeechActivityResult: CustomStringConvertible {
    var description: String {
        [
            "decision=\(decision.rawValue)",
            "duration=\(String(format: "%.2f", duration))s",
            "analyzed=\(String(format: "%.2f", analyzedDuration))s",
            "active=\(String(format: "%.2f", activeSpeechDuration))s",
            "consecutive=\(String(format: "%.2f", longestConsecutiveActiveSpeechDuration))s",
            "ratio=\(String(format: "%.3f", activeFrameRatio))",
            "rms=\(String(format: "%.1f", rmsDBFS))dBFS",
            "peak=\(String(format: "%.1f", peakDBFS))dBFS",
            "noise=\(String(format: "%.1f", noiseFloorDBFS))dBFS",
            "activeRMS=\(String(format: "%.1f", activeRMSDBFS))dBFS",
            "snr=\(String(format: "%.1f", snrDB))dB",
        ].joined(separator: " ")
    }
}

struct SpeechActivityDetector {
    var configuration = SpeechActivityConfiguration()

    func analyze(samples: [Float]) -> SpeechActivityResult {
        let analyzer = AudioFrameAnalyzer(configuration: configuration)
        let duration = Double(samples.count) / configuration.sampleRate
        let frameCount = analyzer.frameCount(sampleCount: samples.count)
        var runningStats = RunningAudioStats()
        var earlyAcceptState = EarlyAcceptState(configuration: configuration)
        var frames = [AudioFrameMetrics]()

        for frameIndex in 0..<frameCount {
            guard let frame = analyzer.metrics(for: samples, frameIndex: frameIndex) else {
                continue
            }

            frames.append(frame)
            runningStats.add(frame)

            if earlyAcceptState.add(frame) {
                return makeResult(
                    decision: .acceptedEarly,
                    duration: duration,
                    analyzedDuration: frame.endTime,
                    frames: frames,
                    runningStats: runningStats,
                    noiseFloorDBFS: runningStats.lowestFrameRMSDBFS,
                    activeFrameThresholdDBFS: configuration.earlyAcceptMinimumFrameRMSDBFS
                )
            }
        }

        let recordingStats = RecordingDecisionStats(
            frames: frames,
            runningStats: runningStats,
            configuration: configuration
        )
        let decision: SpeechActivityResult.Decision =
            recordingStats.shouldTranscribe
            ? .acceptedAfterFullAnalysis
            : .rejectedAsNoSpeech

        return makeResult(
            decision: decision,
            duration: duration,
            analyzedDuration: duration,
            frames: frames,
            runningStats: runningStats,
            noiseFloorDBFS: recordingStats.noiseFloorDBFS,
            activeFrameThresholdDBFS: recordingStats.activeFrameThresholdDBFS
        )
    }

    private func makeResult(
        decision: SpeechActivityResult.Decision,
        duration: TimeInterval,
        analyzedDuration: TimeInterval,
        frames: [AudioFrameMetrics],
        runningStats: RunningAudioStats,
        noiseFloorDBFS: Float,
        activeFrameThresholdDBFS: Float
    ) -> SpeechActivityResult {
        let activeFrames = frames.filter {
            $0.rmsDBFS >= activeFrameThresholdDBFS
                && $0.peakDBFS >= configuration.minimumActiveFramePeakDBFS
        }
        let activeSpeechDuration = min(
            Double(activeFrames.count) * configuration.frameStride,
            duration
        )
        let longestRun = longestConsecutiveActiveDuration(
            frames: frames,
            activeFrameThresholdDBFS: activeFrameThresholdDBFS
        )
        let activeFrameRatio =
            frames.isEmpty ? 0 : Float(activeFrames.count) / Float(frames.count)
        let activeRMSDBFS = AudioMath.dbFS(
            AudioMath.rms(fromSumSquares: activeFrames.reduce(Float(0)) {
                $0 + $1.sumSquares
            }, sampleCount: activeFrames.reduce(0) { $0 + $1.sampleCount })
        )
        let snrDB = max(0, activeRMSDBFS - noiseFloorDBFS)

        return SpeechActivityResult(
            decision: decision,
            duration: duration,
            analyzedDuration: analyzedDuration,
            activeSpeechDuration: activeSpeechDuration,
            longestConsecutiveActiveSpeechDuration: longestRun,
            activeFrameRatio: activeFrameRatio,
            rmsDBFS: runningStats.rmsDBFS,
            peakDBFS: runningStats.peakDBFS,
            noiseFloorDBFS: noiseFloorDBFS,
            activeRMSDBFS: activeRMSDBFS,
            snrDB: snrDB,
            shouldShowNoSpeechMessage: duration
                >= configuration.noSpeechFeedbackMinimumDuration
        )
    }

    private func longestConsecutiveActiveDuration(
        frames: [AudioFrameMetrics],
        activeFrameThresholdDBFS: Float
    ) -> TimeInterval {
        var current = 0
        var longest = 0

        for frame in frames {
            let isActive = frame.rmsDBFS >= activeFrameThresholdDBFS
                && frame.peakDBFS >= configuration.minimumActiveFramePeakDBFS
            if isActive {
                current += 1
                longest = max(longest, current)
            } else {
                current = 0
            }
        }

        return Double(longest) * configuration.frameStride
    }
}

private struct AudioFrameAnalyzer {
    let configuration: SpeechActivityConfiguration

    var frameLengthSamples: Int {
        max(1, Int((configuration.frameDuration * configuration.sampleRate).rounded()))
    }

    var frameStrideSamples: Int {
        max(1, Int((configuration.frameStride * configuration.sampleRate).rounded()))
    }

    func frameCount(sampleCount: Int) -> Int {
        guard sampleCount > 0 else { return 0 }
        if sampleCount <= frameLengthSamples { return 1 }
        return 1 + ((sampleCount - frameLengthSamples) / frameStrideSamples)
    }

    func metrics(for samples: [Float], frameIndex: Int) -> AudioFrameMetrics? {
        let start = frameIndex * frameStrideSamples
        guard start < samples.count else { return nil }

        let end = min(start + frameLengthSamples, samples.count)
        guard end > start else { return nil }

        var sumSquares: Float = 0
        var peak: Float = 0

        for sample in samples[start..<end] {
            let absoluteSample = abs(sample)
            peak = max(peak, absoluteSample)
            sumSquares += sample * sample
        }

        let count = end - start
        let rms = AudioMath.rms(fromSumSquares: sumSquares, sampleCount: count)

        return AudioFrameMetrics(
            sampleCount: count,
            sumSquares: sumSquares,
            rmsDBFS: AudioMath.dbFS(rms),
            peak: peak,
            peakDBFS: AudioMath.dbFS(peak),
            endTime: Double(end) / configuration.sampleRate
        )
    }
}

private struct AudioFrameMetrics {
    let sampleCount: Int
    let sumSquares: Float
    let rmsDBFS: Float
    let peak: Float
    let peakDBFS: Float
    let endTime: TimeInterval
}

private struct RunningAudioStats {
    private(set) var frameCount = 0
    private(set) var sampleCount = 0
    private(set) var sumSquares: Float = 0
    private(set) var peak: Float = 0
    private(set) var lowestFrameRMSDBFS: Float = AudioMath.silenceDBFS

    var rmsDBFS: Float {
        AudioMath.dbFS(AudioMath.rms(fromSumSquares: sumSquares, sampleCount: sampleCount))
    }

    var peakDBFS: Float {
        AudioMath.dbFS(peak)
    }

    mutating func add(_ frame: AudioFrameMetrics) {
        frameCount += 1
        sampleCount += frame.sampleCount
        sumSquares += frame.sumSquares
        peak = max(peak, frame.peak)
        if frameCount == 1 {
            lowestFrameRMSDBFS = frame.rmsDBFS
        } else {
            lowestFrameRMSDBFS = min(lowestFrameRMSDBFS, frame.rmsDBFS)
        }
    }
}

private struct EarlyAcceptState {
    let configuration: SpeechActivityConfiguration
    private var activeDuration: TimeInterval = 0
    private var consecutiveActiveDuration: TimeInterval = 0

    init(configuration: SpeechActivityConfiguration) {
        self.configuration = configuration
    }

    mutating func add(_ frame: AudioFrameMetrics) -> Bool {
        let isClearlySpeech = frame.rmsDBFS
            >= configuration.earlyAcceptMinimumFrameRMSDBFS
            && frame.peakDBFS >= configuration.earlyAcceptMinimumFramePeakDBFS

        if isClearlySpeech {
            activeDuration += configuration.frameStride
            consecutiveActiveDuration += configuration.frameStride
        } else {
            consecutiveActiveDuration = 0
        }

        return activeDuration >= configuration.earlyAcceptMinimumActiveDuration
            && consecutiveActiveDuration
                >= configuration.earlyAcceptMinimumConsecutiveActiveDuration
    }
}

private struct RecordingDecisionStats {
    let noiseFloorDBFS: Float
    let activeFrameThresholdDBFS: Float
    let activeFrameCount: Int
    let activeSpeechDuration: TimeInterval
    let longestConsecutiveActiveSpeechDuration: TimeInterval
    let activeFrameRatio: Float
    let activeRMSDBFS: Float
    let snrDB: Float
    let shouldTranscribe: Bool

    init(
        frames: [AudioFrameMetrics],
        runningStats: RunningAudioStats,
        configuration: SpeechActivityConfiguration
    ) {
        noiseFloorDBFS = Self.percentileDBFS(
            frames.map(\.rmsDBFS),
            percentile: configuration.noiseFloorPercentile
        )
        activeFrameThresholdDBFS = max(
            noiseFloorDBFS + configuration.activeFrameDBAboveNoiseFloor,
            configuration.minimumActiveFrameRMSDBFS
        )

        var activeFrames = [AudioFrameMetrics]()
        var currentRun = 0
        var longestRun = 0

        for frame in frames {
            let isActive = frame.rmsDBFS >= activeFrameThresholdDBFS
                && frame.peakDBFS >= configuration.minimumActiveFramePeakDBFS
            if isActive {
                activeFrames.append(frame)
                currentRun += 1
                longestRun = max(longestRun, currentRun)
            } else {
                currentRun = 0
            }
        }

        activeFrameCount = activeFrames.count
        activeSpeechDuration = Double(activeFrameCount) * configuration.frameStride
        longestConsecutiveActiveSpeechDuration =
            Double(longestRun) * configuration.frameStride
        activeFrameRatio =
            frames.isEmpty ? 0 : Float(activeFrameCount) / Float(frames.count)
        activeRMSDBFS = AudioMath.dbFS(
            AudioMath.rms(fromSumSquares: activeFrames.reduce(Float(0)) {
                $0 + $1.sumSquares
            }, sampleCount: activeFrames.reduce(0) { $0 + $1.sampleCount })
        )
        snrDB = max(0, activeRMSDBFS - noiseFloorDBFS)

        let hasEnoughRecordingLevel = runningStats.rmsDBFS
            >= configuration.minimumRecordingRMSDBFS
            && runningStats.peakDBFS >= configuration.minimumRecordingPeakDBFS
        let hasEnoughActiveSpeech = activeSpeechDuration
            >= configuration.minimumActiveSpeechDuration
            && longestConsecutiveActiveSpeechDuration
                >= configuration.minimumConsecutiveActiveSpeechDuration
        let hasEnoughActiveRatio = activeFrameRatio
            >= configuration.minimumActiveFrameRatio
            || activeSpeechDuration
                >= configuration.minimumActiveSpeechDurationWhenRatioIsLow

        shouldTranscribe = hasEnoughRecordingLevel
            && hasEnoughActiveSpeech
            && hasEnoughActiveRatio
            && snrDB >= configuration.minimumSNRDB
    }

    private static func percentileDBFS(_ values: [Float], percentile: Float) -> Float {
        guard !values.isEmpty else { return AudioMath.silenceDBFS }

        let sorted = values.sorted()
        let clampedPercentile = min(max(percentile, 0), 1)
        let index = min(
            sorted.count - 1,
            max(0, Int((Float(sorted.count - 1) * clampedPercentile).rounded()))
        )
        return sorted[index]
    }
}

private enum AudioMath {
    static let silenceDBFS: Float = -120

    static func rms(fromSumSquares sumSquares: Float, sampleCount: Int) -> Float {
        guard sampleCount > 0 else { return 0 }
        return sqrt(sumSquares / Float(sampleCount))
    }

    static func dbFS(_ amplitude: Float) -> Float {
        guard amplitude > 0 else { return silenceDBFS }
        return max(silenceDBFS, Float(20 * log10(Double(amplitude))))
    }
}
