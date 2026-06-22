import XCTest
@testable import InputalkFunkeyCore

final class FnShortcutDecisionTests: XCTestCase {
    func testHoldToTalkCurrentBehaviorStartsAfterThresholdAndStopsOnFnRelease() {
        let pending = FnShortcutDecision.reduce(
            phase: .idle,
            event: .fnChanged(isPressed: true)
        )
        XCTAssertEqual(pending.nextPhase, .fnDownPending)
        XCTAssertEqual(pending.timerCommands, [.cancelHoldThreshold, .scheduleHoldThreshold])

        let recording = FnShortcutDecision.reduce(
            phase: pending.nextPhase,
            event: .holdThresholdReached
        )
        XCTAssertEqual(recording.nextPhase, .holdRecording)
        XCTAssertEqual(recording.actions, [.startRecording])

        let stopped = FnShortcutDecision.reduce(
            phase: recording.nextPhase,
            event: .fnChanged(isPressed: false)
        )
        XCTAssertEqual(stopped.nextPhase, .idle)
        XCTAssertEqual(stopped.actions, [.stopRecording])
    }

    func testDoubleTapCurrentBehaviorStartsHandsFreeAndNextFnPressStops() {
        let pending = FnShortcutDecision.reduce(
            phase: .idle,
            event: .fnChanged(isPressed: true)
        )
        let waiting = FnShortcutDecision.reduce(
            phase: pending.nextPhase,
            event: .fnChanged(isPressed: false)
        )
        XCTAssertEqual(waiting.nextPhase, .waitingForDoubleTap)
        XCTAssertEqual(
            waiting.timerCommands,
            [.cancelHoldThreshold, .cancelDoubleTapWindow, .scheduleDoubleTapWindow]
        )

        let handsFree = FnShortcutDecision.reduce(
            phase: waiting.nextPhase,
            event: .fnChanged(isPressed: true)
        )
        XCTAssertEqual(handsFree.nextPhase, .handsFreeRecording)
        XCTAssertEqual(handsFree.actions, [.startRecording])

        let stopped = FnShortcutDecision.reduce(
            phase: handsFree.nextPhase,
            event: .fnChanged(isPressed: true)
        )
        XCTAssertEqual(stopped.nextPhase, .idle)
        XCTAssertEqual(stopped.actions, [.stopRecording])
    }

    func testSingleTapCurrentBehaviorReturnsToIdleWhenDoubleTapWindowExpires() {
        let expired = FnShortcutDecision.reduce(
            phase: .waitingForDoubleTap,
            event: .doubleTapWindowExpired
        )

        XCTAssertEqual(expired.nextPhase, .idle)
        XCTAssertEqual(expired.actions, [])
    }

    func testFnVPasteLastCurrentBehaviorConsumesFromPendingAndWaitsForFnRelease() {
        let decision = FnShortcutDecision.reduce(
            phase: .fnDownPending,
            event: .keyDown(
                FnKeyDown(
                    keyCode: FnShortcutDecision.pasteLastTranscriptionKeyCode,
                    isFnDown: true,
                    hasBlockingModifiers: false
                )
            )
        )

        XCTAssertEqual(decision.nextPhase, .shortcutConsumed)
        XCTAssertEqual(decision.actions, [.pasteLastTranscription])
        XCTAssertEqual(decision.timerCommands, [.cancelHoldThreshold, .cancelDoubleTapWindow])
        XCTAssertEqual(decision.keyDisposition, .consume)

        let released = FnShortcutDecision.reduce(
            phase: decision.nextPhase,
            event: .fnChanged(isPressed: false)
        )
        XCTAssertEqual(released.nextPhase, .idle)
    }

    func testFnVPasteLastCurrentBehaviorPassesThroughDuringRecordingModes() {
        for phase in [FnGesturePhase.waitingForDoubleTap, .holdRecording, .handsFreeRecording] {
            let decision = FnShortcutDecision.reduce(
                phase: phase,
                event: .keyDown(
                    FnKeyDown(
                        keyCode: FnShortcutDecision.pasteLastTranscriptionKeyCode,
                        isFnDown: true,
                        hasBlockingModifiers: false
                    )
                )
            )

            XCTAssertEqual(decision.nextPhase, phase)
            XCTAssertEqual(decision.actions, [])
            XCTAssertEqual(decision.keyDisposition, .passThrough)
        }
    }

    func testFnVCurrentBehaviorDoesNotFireWithoutFnOrWithBlockingModifiers() {
        let withoutFn = FnShortcutDecision.reduce(
            phase: .fnDownPending,
            event: .keyDown(
                FnKeyDown(
                    keyCode: FnShortcutDecision.pasteLastTranscriptionKeyCode,
                    isFnDown: false,
                    hasBlockingModifiers: false
                )
            )
        )
        XCTAssertEqual(withoutFn.nextPhase, .fnDownPending)
        XCTAssertEqual(withoutFn.actions, [])
        XCTAssertEqual(withoutFn.keyDisposition, .passThrough)

        let withCommand = FnShortcutDecision.reduce(
            phase: .fnDownPending,
            event: .keyDown(
                FnKeyDown(
                    keyCode: FnShortcutDecision.pasteLastTranscriptionKeyCode,
                    isFnDown: true,
                    hasBlockingModifiers: true
                )
            )
        )
        XCTAssertEqual(withCommand.nextPhase, .fnDownPending)
        XCTAssertEqual(withCommand.actions, [])
        XCTAssertEqual(withCommand.keyDisposition, .passThrough)
    }

    func testFnNumberMapsToPromptSnippetTriggerOnlyFromPendingState() {
        let decision = FnShortcutDecision.reduce(
            phase: .fnDownPending,
            event: .keyDown(
                FnKeyDown(
                    keyCode: 18,
                    isFnDown: true,
                    hasBlockingModifiers: false
                )
            )
        )

        XCTAssertEqual(decision.nextPhase, .shortcutConsumed)
        XCTAssertEqual(decision.actions, [.promptSnippet(.fnKey(SnippetKey(keyCode: 18)))])
        XCTAssertEqual(decision.keyDisposition, .consume)

        for phase in [FnGesturePhase.idle, .waitingForDoubleTap, .holdRecording, .handsFreeRecording] {
            let passThrough = FnShortcutDecision.reduce(
                phase: phase,
                event: .keyDown(
                    FnKeyDown(
                        keyCode: 18,
                        isFnDown: true,
                        hasBlockingModifiers: false
                    )
                )
            )
            XCTAssertEqual(passThrough.nextPhase, phase)
            XCTAssertEqual(passThrough.actions, [])
            XCTAssertEqual(passThrough.keyDisposition, .passThrough)
        }
    }

    func testFnNumberDoesNotFireWhenPromptSnippetsAreUnavailable() {
        let decision = FnShortcutDecision.reduce(
            phase: .fnDownPending,
            event: .keyDown(
                FnKeyDown(
                    keyCode: 18,
                    isFnDown: true,
                    hasBlockingModifiers: false,
                    arePromptSnippetsAvailable: false
                )
            )
        )

        XCTAssertEqual(decision.nextPhase, .shortcutConsumed)
        XCTAssertEqual(decision.actions, [])
        XCTAssertEqual(decision.keyDisposition, .consume)
    }

    func testPromptTriggerLookupSupportsFnOneThroughNine() {
        let expectedKeyCodes = [18, 19, 20, 21, 23, 22, 26, 28, 25]

        XCTAssertEqual(
            expectedKeyCodes.map { FnShortcutDecision.promptTrigger(for: $0) },
            expectedKeyCodes.map { .fnKey(SnippetKey(keyCode: $0)) }
        )
        XCTAssertNil(FnShortcutDecision.promptTrigger(for: 0))
    }
}
