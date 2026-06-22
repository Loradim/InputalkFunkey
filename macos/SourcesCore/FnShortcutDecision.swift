public enum FnGesturePhase: Equatable, Sendable {
    case idle
    case fnDownPending
    case waitingForDoubleTap
    case holdRecording
    case handsFreeRecording
    case shortcutConsumed
}

public enum FnGestureEvent: Equatable, Sendable {
    case fnChanged(isPressed: Bool)
    case holdThresholdReached
    case doubleTapWindowExpired
    case keyDown(FnKeyDown)
}

public struct FnKeyDown: Equatable, Sendable {
    public var keyCode: Int
    public var isFnDown: Bool
    public var hasBlockingModifiers: Bool
    public var arePromptSnippetsAvailable: Bool

    public init(
        keyCode: Int,
        isFnDown: Bool,
        hasBlockingModifiers: Bool,
        arePromptSnippetsAvailable: Bool = true
    ) {
        self.keyCode = keyCode
        self.isFnDown = isFnDown
        self.hasBlockingModifiers = hasBlockingModifiers
        self.arePromptSnippetsAvailable = arePromptSnippetsAvailable
    }
}

public enum FnGestureAction: Equatable, Sendable {
    case startRecording
    case stopRecording
    case pasteLastTranscription
    case promptSnippet(SnippetTrigger)
}

public enum FnGestureTimerCommand: Equatable, Sendable {
    case scheduleHoldThreshold
    case cancelHoldThreshold
    case scheduleDoubleTapWindow
    case cancelDoubleTapWindow
}

public enum FnKeyDisposition: Equatable, Sendable {
    case passThrough
    case consume
}

public struct FnGestureDecision: Equatable, Sendable {
    public var nextPhase: FnGesturePhase
    public var actions: [FnGestureAction]
    public var timerCommands: [FnGestureTimerCommand]
    public var keyDisposition: FnKeyDisposition

    public init(
        nextPhase: FnGesturePhase,
        actions: [FnGestureAction] = [],
        timerCommands: [FnGestureTimerCommand] = [],
        keyDisposition: FnKeyDisposition = .passThrough
    ) {
        self.nextPhase = nextPhase
        self.actions = actions
        self.timerCommands = timerCommands
        self.keyDisposition = keyDisposition
    }
}

public enum FnShortcutDecision {
    public static let pasteLastTranscriptionKeyCode = 9

    public static func reduce(
        phase: FnGesturePhase,
        event: FnGestureEvent
    ) -> FnGestureDecision {
        switch event {
        case .fnChanged(let isPressed):
            return handleFnChange(phase: phase, isPressed: isPressed)
        case .holdThresholdReached:
            return handleHoldThreshold(phase: phase)
        case .doubleTapWindowExpired:
            return handleDoubleTapWindowExpired(phase: phase)
        case .keyDown(let keyDown):
            return handleKeyDown(phase: phase, keyDown: keyDown)
        }
    }

    public static func promptTrigger(for keyCode: Int) -> SnippetTrigger? {
        SnippetKey.fnNumberTriggers.first { trigger in
            guard case .fnKey(let key) = trigger else { return false }
            return key.keyCode == keyCode
        }
    }

    private static func handleFnChange(
        phase: FnGesturePhase,
        isPressed: Bool
    ) -> FnGestureDecision {
        switch phase {
        case .idle:
            if isPressed {
                return FnGestureDecision(
                    nextPhase: .fnDownPending,
                    timerCommands: [.cancelHoldThreshold, .scheduleHoldThreshold]
                )
            }
            return FnGestureDecision(nextPhase: phase)

        case .fnDownPending:
            if !isPressed {
                return FnGestureDecision(
                    nextPhase: .waitingForDoubleTap,
                    timerCommands: [
                        .cancelHoldThreshold,
                        .cancelDoubleTapWindow,
                        .scheduleDoubleTapWindow,
                    ]
                )
            }
            return FnGestureDecision(nextPhase: phase)

        case .waitingForDoubleTap:
            if isPressed {
                return FnGestureDecision(
                    nextPhase: .handsFreeRecording,
                    actions: [.startRecording],
                    timerCommands: [.cancelDoubleTapWindow]
                )
            }
            return FnGestureDecision(nextPhase: phase)

        case .holdRecording:
            if !isPressed {
                return FnGestureDecision(
                    nextPhase: .idle,
                    actions: [.stopRecording]
                )
            }
            return FnGestureDecision(nextPhase: phase)

        case .handsFreeRecording:
            if isPressed {
                return FnGestureDecision(
                    nextPhase: .idle,
                    actions: [.stopRecording]
                )
            }
            return FnGestureDecision(nextPhase: phase)

        case .shortcutConsumed:
            if !isPressed {
                return FnGestureDecision(nextPhase: .idle)
            }
            return FnGestureDecision(nextPhase: phase)
        }
    }

    private static func handleHoldThreshold(phase: FnGesturePhase) -> FnGestureDecision {
        guard phase == .fnDownPending else {
            return FnGestureDecision(nextPhase: phase)
        }

        return FnGestureDecision(
            nextPhase: .holdRecording,
            actions: [.startRecording]
        )
    }

    private static func handleDoubleTapWindowExpired(
        phase: FnGesturePhase
    ) -> FnGestureDecision {
        guard phase == .waitingForDoubleTap else {
            return FnGestureDecision(nextPhase: phase)
        }

        return FnGestureDecision(nextPhase: .idle)
    }

    private static func handleKeyDown(
        phase: FnGesturePhase,
        keyDown: FnKeyDown
    ) -> FnGestureDecision {
        guard keyDown.isFnDown, !keyDown.hasBlockingModifiers else {
            return FnGestureDecision(nextPhase: phase)
        }

        if keyDown.keyCode == pasteLastTranscriptionKeyCode {
            return handlePasteLastTranscription(phase: phase)
        }

        if let trigger = promptTrigger(for: keyDown.keyCode) {
            return handlePromptSnippet(
                phase: phase,
                trigger: trigger,
                isAvailable: keyDown.arePromptSnippetsAvailable
            )
        }

        return FnGestureDecision(nextPhase: phase)
    }

    private static func handlePasteLastTranscription(
        phase: FnGesturePhase
    ) -> FnGestureDecision {
        switch phase {
        case .idle, .fnDownPending:
            return FnGestureDecision(
                nextPhase: .shortcutConsumed,
                actions: [.pasteLastTranscription],
                timerCommands: [.cancelHoldThreshold, .cancelDoubleTapWindow],
                keyDisposition: .consume
            )
        case .shortcutConsumed:
            return FnGestureDecision(nextPhase: phase, keyDisposition: .consume)
        case .waitingForDoubleTap, .holdRecording, .handsFreeRecording:
            return FnGestureDecision(nextPhase: phase)
        }
    }

    private static func handlePromptSnippet(
        phase: FnGesturePhase,
        trigger: SnippetTrigger,
        isAvailable: Bool
    ) -> FnGestureDecision {
        switch phase {
        case .fnDownPending:
            let actions: [FnGestureAction] = isAvailable ? [.promptSnippet(trigger)] : []
            return FnGestureDecision(
                nextPhase: .shortcutConsumed,
                actions: actions,
                timerCommands: [.cancelHoldThreshold, .cancelDoubleTapWindow],
                keyDisposition: .consume
            )
        case .shortcutConsumed:
            return FnGestureDecision(nextPhase: phase, keyDisposition: .consume)
        case .idle, .waitingForDoubleTap, .holdRecording, .handsFreeRecording:
            return FnGestureDecision(nextPhase: phase)
        }
    }
}
