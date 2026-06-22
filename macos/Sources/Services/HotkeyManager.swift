import AppKit
import Carbon.HIToolbox
import InputalkFunkeyCore

@_silgen_name("TISUpdateFnUsageType")
private func TISUpdateFnUsageType(_ value: Int32)

@_silgen_name("TISGetFnUsageType")
private func TISGetFnUsageType() -> Int32

// MARK: - Hotkey Manager

/// Manages the Fn (Globe) key for dictation:
/// - **Double-press Fn**: Hands-free mode (recording starts, press Fn again to stop + transcribe)
/// - **Hold Fn**: Hold-to-talk (release to stop + transcribe)
///
/// Uses a CGEvent tap to intercept Fn before macOS shows the emoji picker.
@MainActor
class HotkeyManager {
    var onRecordStart: (() -> Void)?
    var onRecordStop: (() -> Void)?
    var onPasteLastTranscription: (() -> Void)?
    var onPromptSnippetShortcut: ((SnippetTrigger) -> Void)?
    var arePromptSnippetShortcutsAvailable: (() -> Bool)?

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    /// Keep the state object alive for the C callback
    private var stateRef: AnyObject?

    /// Saved original Fn key usage type so we can restore on quit
    private var originalFnUsageType: Int?
    private var hadOriginalFnUsageType = false
    private var didOverrideSystemFnBehavior = false

    func start() {
        stop()

        // Disable the system Globe key behavior (emoji picker / input switching).
        // Writing AppleFnUsageType persists the setting, while TISUpdateFnUsageType
        // applies it to the live Text Input state immediately. We restore on stop().
        disableSystemFnBehavior()

        guard AXIsProcessTrusted() else { return }

        let state = FnKeyState()
        state.manager = self
        stateRef = state

        let userInfo = Unmanaged.passUnretained(state).toOpaque()

        // Listen for Fn modifier changes, Fn+V retry insertion, and Fn+number snippets.
        let eventMask: CGEventMask =
            (1 << CGEventType.flagsChanged.rawValue) | (1 << CGEventType.keyDown.rawValue)

        guard
            let tap = CGEvent.tapCreate(
                tap: .cgSessionEventTap,
                place: .headInsertEventTap,
                options: .defaultTap,
                eventsOfInterest: eventMask,
                callback: fnEventCallback,
                userInfo: userInfo
            )
        else {
            return
        }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    func stop() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
        stateRef = nil

        restoreSystemFnBehavior()
    }

    // MARK: - System Fn Key Override

    /// Disable macOS Globe key system action by applying AppleFnUsageType = 0
    private func disableSystemFnBehavior() {
        guard !didOverrideSystemFnBehavior else { return }

        let defaults = UserDefaults(suiteName: "com.apple.HIToolbox")
        hadOriginalFnUsageType = defaults?.object(forKey: "AppleFnUsageType") != nil
        originalFnUsageType = Int(TISGetFnUsageType())
        applySystemFnUsageType(0)
        didOverrideSystemFnBehavior = true
    }

    /// Restore the user's original Globe key behavior
    private func restoreSystemFnBehavior() {
        guard didOverrideSystemFnBehavior, let original = originalFnUsageType else { return }

        applySystemFnUsageType(original)

        if !hadOriginalFnUsageType {
            let defaults = UserDefaults(suiteName: "com.apple.HIToolbox")
            defaults?.removeObject(forKey: "AppleFnUsageType")
            defaults?.synchronize()
        }

        originalFnUsageType = nil
        hadOriginalFnUsageType = false
        didOverrideSystemFnBehavior = false
    }

    private func applySystemFnUsageType(_ value: Int) {
        let defaults = UserDefaults(suiteName: "com.apple.HIToolbox")
        defaults?.set(value, forKey: "AppleFnUsageType")
        defaults?.synchronize()
        TISUpdateFnUsageType(Int32(value))
    }

    func cancelRecording() {
        if let state = stateRef as? FnKeyState {
            state.phase = .idle
        }
    }
}

// MARK: - State Machine

/// Fn key detection phases:
/// ```
/// idle → fnDown:
///   start holdTimer (300ms)
///   → if held past timer → holdRecording → fnUp → stop + transcribe → idle
///   → if released quickly → waitingForDoubleTap (400ms window)
///       → fnDown within window → handsFreeRecording → fnDown → stop + transcribe → idle
///       → timeout → idle (single tap, ignored)
/// ```
private class FnKeyState: @unchecked Sendable {
    var phase: FnGesturePhase = .idle
    var fnDownTime: CFAbsoluteTime = 0
    var holdTimer: DispatchWorkItem?
    var doubleTapTimer: DispatchWorkItem?
    weak var manager: HotkeyManager?

    /// Track previous Fn flag state so we only suppress events where Fn actually changed.
    /// Without this, modifier key-up events (Shift, Cmd, etc.) get swallowed because
    /// their flags are empty after release, causing "stuck keys" in remote desktop apps.
    var previousFnDown: Bool = false

    /// How long Fn must be held before hold-to-talk activates
    let holdThreshold: TimeInterval = 0.3
    /// Window to detect second tap of double-tap
    let doubleTapWindow: TimeInterval = 0.4
}

private let fnFlag: UInt64 = 0x800000
private let shortcutBlockingModifiers: CGEventFlags = [
    .maskCommand, .maskAlternate, .maskShift, .maskControl,
]

// MARK: - CGEvent Callback (C-function, runs on event tap thread)

private func fnEventCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    // Re-enable if macOS disabled the tap
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        // We can't access the tap ref here easily, but it auto-re-enables in practice
        return Unmanaged.passUnretained(event)
    }

    guard let userInfo else {
        return Unmanaged.passUnretained(event)
    }

    let state = Unmanaged<FnKeyState>.fromOpaque(userInfo).takeUnretainedValue()

    if type == .keyDown {
        return handleKeyDown(event: event, state: state)
    }

    guard type == .flagsChanged else {
        return Unmanaged.passUnretained(event)
    }

    // Check if the Fn (Globe / SecondaryFn) flag changed
    // NX_SECONDARYFN = 0x800000 in IOKit
    let fnIsDown = (event.flags.rawValue & fnFlag) != 0

    // Only act on events where the Fn flag actually toggled.
    // flagsChanged fires for ALL modifier changes (Shift, Cmd, etc.).
    // If we suppress non-Fn events, their key-up never reaches the system,
    // causing "stuck" modifiers in remote desktop apps like Parsec.
    let fnChanged = (fnIsDown != state.previousFnDown)
    state.previousFnDown = fnIsDown

    if !fnChanged {
        return Unmanaged.passUnretained(event)
    }

    // Fn flag changed — ignore if other modifiers are also held (Cmd, Opt, Shift, Ctrl)
    let hasOtherModifiers = !event.flags.intersection(shortcutBlockingModifiers).isEmpty
    if hasOtherModifiers {
        return Unmanaged.passUnretained(event)
    }

    DispatchQueue.main.async {
        handleFnStateChange(state: state, fnPressed: fnIsDown)
    }

    // Suppress Fn events to prevent macOS from showing
    // the emoji picker, keyboard switcher, or dictation panel.
    return nil
}

private func handleKeyDown(event: CGEvent, state: FnKeyState) -> Unmanaged<CGEvent>? {
    let keyCode = Int(event.getIntegerValueField(.keyboardEventKeycode))
    let fnIsDown = ((event.flags.rawValue & fnFlag) != 0) || state.previousFnDown
    let hasOtherModifiers = !event.flags.intersection(shortcutBlockingModifiers).isEmpty

    let decision = FnShortcutDecision.reduce(
        phase: state.phase,
        event: .keyDown(
            FnKeyDown(
                keyCode: keyCode,
                isFnDown: fnIsDown,
                hasBlockingModifiers: hasOtherModifiers
            )
        )
    )

    if shouldApply(decision: decision, currentPhase: state.phase) {
        DispatchQueue.main.async {
            applyDecision(decision, state: state)
        }
    }

    return decision.keyDisposition == .consume ? nil : Unmanaged.passUnretained(event)
}

@MainActor
private func handleFnStateChange(state: FnKeyState, fnPressed: Bool) {
    let decision = FnShortcutDecision.reduce(
        phase: state.phase,
        event: .fnChanged(isPressed: fnPressed)
    )
    applyDecision(decision, state: state)
}

@MainActor
private func applyDecision(_ decision: FnGestureDecision, state: FnKeyState) {
    state.phase = decision.nextPhase

    for command in decision.timerCommands {
        applyTimerCommand(command, state: state)
    }

    for action in decision.actions {
        applyAction(action, state: state)
    }
}

private func shouldApply(decision: FnGestureDecision, currentPhase: FnGesturePhase) -> Bool {
    decision.nextPhase != currentPhase
        || !decision.actions.isEmpty
        || !decision.timerCommands.isEmpty
}

@MainActor
private func applyTimerCommand(_ command: FnGestureTimerCommand, state: FnKeyState) {
    switch command {
    case .cancelHoldThreshold:
        state.holdTimer?.cancel()
        state.holdTimer = nil

    case .scheduleHoldThreshold:
        state.holdTimer?.cancel()
        let holdWork = DispatchWorkItem { [weak state] in
            Task { @MainActor in
                guard let state else { return }
                let decision = FnShortcutDecision.reduce(
                    phase: state.phase,
                    event: .holdThresholdReached
                )
                applyDecision(decision, state: state)
            }
        }
        state.holdTimer = holdWork
        DispatchQueue.main.asyncAfter(
            deadline: .now() + state.holdThreshold,
            execute: holdWork
        )

    case .cancelDoubleTapWindow:
        state.doubleTapTimer?.cancel()
        state.doubleTapTimer = nil

    case .scheduleDoubleTapWindow:
        state.doubleTapTimer?.cancel()
        let doubleTapWork = DispatchWorkItem { [weak state] in
            Task { @MainActor in
                guard let state else { return }
                let decision = FnShortcutDecision.reduce(
                    phase: state.phase,
                    event: .doubleTapWindowExpired
                )
                applyDecision(decision, state: state)
            }
        }
        state.doubleTapTimer = doubleTapWork
        DispatchQueue.main.asyncAfter(
            deadline: .now() + state.doubleTapWindow,
            execute: doubleTapWork
        )
    }
}

@MainActor
private func applyAction(_ action: FnGestureAction, state: FnKeyState) {
    switch action {
    case .startRecording:
        state.manager?.onRecordStart?()
    case .stopRecording:
        state.manager?.onRecordStop?()
    case .pasteLastTranscription:
        state.manager?.onPasteLastTranscription?()
    case .promptSnippet(let trigger):
        guard state.manager?.arePromptSnippetShortcutsAvailable?() ?? true else { return }
        state.manager?.onPromptSnippetShortcut?(trigger)
    }
}
