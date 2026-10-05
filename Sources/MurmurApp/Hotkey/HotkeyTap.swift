// Adapted from PushText (https://github.com/EvanCNavarro/PushText),
// Sources/PushTextKit/CGEventTapHotkeyMonitor.swift at adf1660. MIT License, Copyright (c) 2026 Evan C. Navarro.
// Changes: the tap runs on its own thread; it also watches keyDown (Escape and chords), reports
// Control separately for command mode, swallows Escape while a capture is active, and ignores
// keystrokes Murmur itself synthesises.

import ApplicationServices
import CoreGraphics
import Foundation
import MurmurCore

/// Watches the push-to-talk trigger system-wide with an active `CGEvent` tap.
///
/// Why a tap rather than `NSEvent` monitors: a tap can *swallow* events (the Globe key's own
/// action, Escape while recording), and a `flagsChanged` tap keeps working inside Secure Input
/// fields, where key events are filtered. It needs Accessibility permission; a tap created without
/// it is created successfully and then never fires, so `start()` checks first.
///
/// The callback only translates and forwards. It runs on a dedicated thread so a busy main thread
/// can never make macOS disable the tap for being slow.
final class HotkeyTap: @unchecked Sendable {
    enum Event: Sendable, Equatable {
        case trigger(HotkeyEdge, held: HeldModifiers)
        case controlDown
        case otherKeyDown
        case escape
    }

    enum TapError: LocalizedError {
        case accessibilityNotTrusted
        case tapCreationFailed

        var errorDescription: String? {
            switch self {
            case .accessibilityNotTrusted: return "Accessibility permission is not granted."
            case .tapCreationFailed: return "macOS refused to create the keyboard event tap."
            }
        }
    }

    private let lock = NSLock()
    private let onEvent: @Sendable (Event) -> Void

    // Guarded by `lock`.
    private var gate: ModifierGate
    private var takeOverGlobe: Bool
    private var captureActive = false
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var runLoop: CFRunLoop?
    private var reenableCount = 0

    init(trigger: HotkeyTrigger, takeOverGlobe: Bool, onEvent: @escaping @Sendable (Event) -> Void) {
        self.gate = ModifierGate(trigger: trigger)
        self.takeOverGlobe = takeOverGlobe
        self.onEvent = onEvent
    }

    var isRunning: Bool {
        lock.synchronized { tap != nil }
    }

    /// How many times macOS disabled the tap and we re-armed it.
    var reenables: Int {
        lock.synchronized { reenableCount }
    }

    var trigger: HotkeyTrigger {
        lock.synchronized { gate.trigger }
    }

    func configure(trigger: HotkeyTrigger, takeOverGlobe: Bool) {
        let flags = CGEventSource.flagsState(.combinedSessionState).rawValue
        lock.synchronized {
            gate = ModifierGate(trigger: trigger, flags: flags)
            self.takeOverGlobe = takeOverGlobe
        }
    }

    /// While a capture is active, Escape is swallowed instead of reaching the focused app.
    func setCaptureActive(_ active: Bool) {
        lock.synchronized { captureActive = active }
    }

    func start() throws {
        guard AXIsProcessTrusted() else { throw TapError.accessibilityNotTrusted }
        guard !isRunning else { return }

        let mask = (CGEventMask(1) << CGEventMask(CGEventType.flagsChanged.rawValue))
            | (CGEventMask(1) << CGEventMask(CGEventType.keyDown.rawValue))
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: hotkeyTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            throw TapError.tapCreationFailed
        }
        let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        let flags = CGEventSource.flagsState(.combinedSessionState).rawValue
        lock.synchronized {
            self.tap = tap
            self.source = source
            gate = ModifierGate(trigger: gate.trigger, flags: flags)
        }

        let thread = Thread { [self] in
            self.runTapLoop()
        }
        thread.name = "com.zedan.murmur.hotkey-tap"
        thread.qualityOfService = .userInteractive
        thread.start()
    }

    func stop() {
        let (tap, source, runLoop) = lock.synchronized { (self.tap, self.source, self.runLoop) }
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        if let runLoop {
            if let source {
                CFRunLoopRemoveSource(runLoop, source, .commonModes)
            }
            CFRunLoopStop(runLoop)
        }
        lock.synchronized {
            self.tap = nil
            self.source = nil
            self.runLoop = nil
        }
    }

    private func runTapLoop() {
        let runLoop: CFRunLoop = CFRunLoopGetCurrent()
        let (tap, source) = lock.synchronized { (self.tap, self.source) }
        guard let tap, let source else { return }
        lock.synchronized { self.runLoop = runLoop }
        CFRunLoopAddSource(runLoop, source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        Log.hotkey.info("event tap running")
        CFRunLoopRun()
        Log.hotkey.info("event tap stopped")
    }

    // MARK: - Tap thread

    fileprivate func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            reenable(reason: type == .tapDisabledByTimeout ? "timeout" : "user input")
            return Unmanaged.passUnretained(event)
        case .flagsChanged:
            return handleFlagsChanged(event)
        case .keyDown:
            return handleKeyDown(event)
        default:
            return Unmanaged.passUnretained(event)
        }
    }

    private func handleFlagsChanged(_ event: CGEvent) -> Unmanaged<CGEvent>? {
        guard event.getIntegerValueField(.eventSourceUserData) != SyntheticEvent.marker else {
            return Unmanaged.passUnretained(event)
        }
        let flags = event.flags.rawValue
        let (change, consume) = lock.synchronized { () -> (FlagsChange, Bool) in
            let change = gate.update(flags: flags)
            var consume = false
            if case .trigger = change, takeOverGlobe, gate.trigger.canTakeOverSystemAction {
                // Swallow both the press and the release: letting either edge through still fires
                // the system's Globe action.
                consume = true
            }
            return (change, consume)
        }

        switch change {
        case .trigger(let edge, let held):
            onEvent(.trigger(edge, held: held))
        case .controlPressed:
            onEvent(.controlDown)
        case .otherModifierPressed:
            onEvent(.otherKeyDown)
        case .irrelevant:
            break
        }
        return consume ? nil : Unmanaged.passUnretained(event)
    }

    private func handleKeyDown(_ event: CGEvent) -> Unmanaged<CGEvent>? {
        guard event.getIntegerValueField(.eventSourceUserData) != SyntheticEvent.marker,
              event.getIntegerValueField(.keyboardEventAutorepeat) == 0 else {
            return Unmanaged.passUnretained(event)
        }
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let (triggerDown, capturing) = lock.synchronized { (gate.isDown, captureActive) }

        if keyCode == KeyCode.escape {
            guard capturing else { return Unmanaged.passUnretained(event) }
            onEvent(.escape)
            return nil
        }
        if triggerDown {
            // Fn+arrow, Fn+F-key and similar: the user meant a shortcut, not a dictation.
            onEvent(.otherKeyDown)
        }
        return Unmanaged.passUnretained(event)
    }

    /// macOS disables a tap it considers too slow, or on certain user input, and never re-enables
    /// it. Re-arm, then re-read the live modifier state in case the trigger's release was dropped
    /// while the tap was off.
    private func reenable(reason: String) {
        guard let tap = lock.synchronized({ self.tap }) else { return }
        CGEvent.tapEnable(tap: tap, enable: true)
        let flags = CGEventSource.flagsState(.combinedSessionState).rawValue
        let edge = lock.synchronized { () -> HotkeyEdge? in
            reenableCount += 1
            return gate.resynchronise(flags: flags)
        }
        Log.hotkey.notice("event tap re-enabled after \(reason, privacy: .public)")
        if let edge {
            onEvent(.trigger(edge, held: []))
        }
    }
}

private func hotkeyTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let tap = Unmanaged<HotkeyTap>.fromOpaque(userInfo).takeUnretainedValue()
    return tap.handle(type: type, event: event)
}

extension NSLock {
    /// Runs `body` while holding the lock.
    func synchronized<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}
