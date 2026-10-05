// Murmur's push-to-talk logic. The semantics (capture on press, tap vs hold, double-tap to latch,
// chord cancels, Escape cancels, a watchdog for a release that never arrives) follow Muesli's
// HotkeyMonitor.swift (MIT, Copyright (c) 2026 Pranav Hari) and PushText's DictationState.swift
// (MIT, Copyright (c) 2026 Evan C. Navarro); this pure, timer-free form is written for Murmur.

import Foundation

/// How a capture was started, which decides what ends it.
public enum CaptureMode: String, Sendable, Equatable, Codable {
    /// Lasts while the trigger is held.
    case hold
    /// Latched by a double-tap or a pill click; ended by the next trigger press.
    case handsFree
    /// Trigger + Control: a spoken instruction applied to the selection.
    case command
}

/// Why a capture was thrown away.
public enum DiscardReason: String, Sendable, Equatable {
    /// Released too quickly to be speech.
    case tap
    /// Another key was pressed with the trigger (Fn+arrow, Fn+F-key...), so it was a shortcut.
    case chord
    /// The user pressed Escape.
    case escape
}

/// What the app should do in response to an input.
public enum HotkeyEffect: Sendable, Equatable {
    /// Start capturing audio now, before we know whether this is a tap or a hold, so the first
    /// syllable is kept.
    case beginCapture(CaptureMode)
    /// The press has lasted long enough to be a real dictation: show the recording state.
    case commitHold
    /// The capture changed mode (hold → command).
    case switchMode(CaptureMode)
    /// Stop capturing and process the audio.
    case finish(CaptureMode)
    /// Stop capturing and throw the audio away.
    case discard(DiscardReason)
}

/// Modifiers other than the trigger that are held at a given moment.
public struct HeldModifiers: OptionSet, Sendable, Hashable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    public static let control = HeldModifiers(rawValue: 1 << 0)
    public static let other = HeldModifiers(rawValue: 1 << 1)

    /// Classifies a raw flag value that already excludes the trigger's own bit.
    public init(flags: UInt64) {
        var held: HeldModifiers = []
        if flags & ModifierMask.control != 0 { held.insert(.control) }
        if flags & ModifierMask.all & ~ModifierMask.control != 0 { held.insert(.other) }
        self = held
    }
}

/// Inputs to the state machine. Times are monotonic seconds (for example system uptime).
public enum HotkeyInput: Sendable, Equatable {
    case triggerDown(held: HeldModifiers)
    case triggerUp
    /// Control went down while the trigger was held.
    case controlDown
    /// Any other key, or another modifier, went down while the trigger was held.
    case otherKeyDown
    case escape
    case pillClick
    /// A scheduled check; see `nextDeadline(now:)`.
    case tick
    /// A live reading of whether the trigger is physically down, used to recover from a release
    /// the event tap never delivered.
    case triggerFlag(isDown: Bool)
}

public struct HotkeyTiming: Sendable, Equatable {
    /// Presses shorter than this are taps, not dictations.
    public var tapThreshold: TimeInterval
    /// A second press within this long after a tap latches hands-free mode.
    public var doubleTapWindow: TimeInterval
    /// How long the trigger may read as released, without a release event, before we act on it.
    public var missedReleaseGrace: TimeInterval
    /// How often to poll the trigger while a hold is in progress.
    public var pollInterval: TimeInterval

    public init(
        tapThreshold: TimeInterval = 0.15,
        doubleTapWindow: TimeInterval = 0.35,
        missedReleaseGrace: TimeInterval = 0.5,
        pollInterval: TimeInterval = 0.25
    ) {
        self.tapThreshold = tapThreshold
        self.doubleTapWindow = doubleTapWindow
        self.missedReleaseGrace = missedReleaseGrace
        self.pollInterval = pollInterval
    }
}

/// Pure push-to-talk state machine: timestamped inputs in, effects out, no timers or I/O.
///
/// | State | Input | Next | Effects |
/// |---|---|---|---|
/// | idle | triggerDown | pending | beginCapture(.hold) |
/// | pending | triggerUp < tapThreshold | tapWindow | discard(.tap) |
/// | pending | tick ≥ tapThreshold | holding | commitHold |
/// | pending/holding | controlDown | command | switchMode(.command) |
/// | pending/holding/command | otherKeyDown | idle | discard(.chord) |
/// | holding | triggerUp | idle | finish(.hold) |
/// | tapWindow | triggerDown ≤ doubleTapWindow | handsFree | beginCapture(.handsFree) |
/// | handsFree | triggerDown | idle | finish(.handsFree) |
/// | any capturing | escape | idle | discard(.escape) |
public struct HotkeyStateMachine: Sendable {
    public enum State: Sendable, Equatable {
        case idle
        case pending(since: TimeInterval)
        case holding(since: TimeInterval)
        case command(since: TimeInterval)
        case tapWindow(releasedAt: TimeInterval)
        /// `awaitingLatchRelease` is true between the second press of a double-tap and its
        /// release, which must not end the capture it just started.
        case handsFree(since: TimeInterval, awaitingLatchRelease: Bool)
    }

    public private(set) var state: State = .idle
    public var timing: HotkeyTiming
    private var triggerMissingSince: TimeInterval?

    public init(timing: HotkeyTiming = HotkeyTiming()) {
        self.timing = timing
    }

    /// Whether audio should currently be captured.
    public var isCapturing: Bool {
        switch state {
        case .pending, .holding, .command, .handsFree: return true
        case .idle, .tapWindow: return false
        }
    }

    /// Forget everything, for example after the capture failed to start.
    public mutating func reset() {
        state = .idle
        triggerMissingSince = nil
    }

    public mutating func handle(_ input: HotkeyInput, at now: TimeInterval) -> [HotkeyEffect] {
        if input == .escape {
            if isCapturing {
                reset()
                return [.discard(.escape)]
            }
            reset()
            return []
        }

        switch state {
        case .idle:
            return handleIdle(input, at: now)

        case .pending(let since):
            switch input {
            case .triggerUp:
                if now - since < timing.tapThreshold {
                    triggerMissingSince = nil
                    state = .tapWindow(releasedAt: now)
                    return [.discard(.tap)]
                }
                // The tick that would have committed the hold has not run yet.
                reset()
                return [.commitHold, .finish(.hold)]
            case .tick:
                guard now - since >= timing.tapThreshold else { return [] }
                state = .holding(since: since)
                return [.commitHold]
            case .controlDown:
                state = .command(since: since)
                return [.switchMode(.command)]
            case .otherKeyDown:
                reset()
                return [.discard(.chord)]
            case .triggerFlag(let isDown):
                noteTriggerFlag(isDown, at: now)
                return []
            case .triggerDown, .pillClick, .escape:
                return []
            }

        case .holding(let since):
            switch input {
            case .triggerUp:
                reset()
                return [.finish(.hold)]
            case .controlDown:
                state = .command(since: since)
                return [.switchMode(.command)]
            case .otherKeyDown:
                reset()
                return [.discard(.chord)]
            case .triggerFlag(let isDown):
                noteTriggerFlag(isDown, at: now)
                return finishIfReleaseWasMissed(at: now, mode: .hold)
            case .tick:
                return finishIfReleaseWasMissed(at: now, mode: .hold)
            case .triggerDown, .pillClick, .escape:
                return []
            }

        case .command(let since):
            switch input {
            case .triggerUp:
                reset()
                if now - since < timing.tapThreshold {
                    return [.discard(.tap)]
                }
                return [.finish(.command)]
            case .otherKeyDown:
                reset()
                return [.discard(.chord)]
            case .triggerFlag(let isDown):
                noteTriggerFlag(isDown, at: now)
                return finishIfReleaseWasMissed(at: now, mode: .command)
            case .tick:
                return finishIfReleaseWasMissed(at: now, mode: .command)
            case .triggerDown, .controlDown, .pillClick, .escape:
                return []
            }

        case .tapWindow(let releasedAt):
            switch input {
            case .triggerDown(let held):
                if held.contains(.other) {
                    reset()
                    return []
                }
                if now - releasedAt <= timing.doubleTapWindow {
                    state = .handsFree(since: now, awaitingLatchRelease: true)
                    return [.beginCapture(.handsFree)]
                }
                // Too late to count as a double-tap: treat it as a fresh press.
                reset()
                return handleIdle(input, at: now)
            case .tick:
                if now - releasedAt > timing.doubleTapWindow {
                    reset()
                }
                return []
            case .pillClick:
                state = .handsFree(since: now, awaitingLatchRelease: false)
                return [.beginCapture(.handsFree)]
            case .triggerUp, .controlDown, .otherKeyDown, .triggerFlag, .escape:
                return []
            }

        case .handsFree(let since, let awaitingLatchRelease):
            switch input {
            case .triggerUp:
                if awaitingLatchRelease {
                    state = .handsFree(since: since, awaitingLatchRelease: false)
                }
                return []
            case .triggerDown:
                guard !awaitingLatchRelease else { return [] }
                reset()
                return [.finish(.handsFree)]
            case .pillClick:
                reset()
                return [.finish(.handsFree)]
            case .controlDown, .otherKeyDown, .tick, .triggerFlag, .escape:
                // Typing while hands-free does not cancel; only Escape or the trigger ends it.
                return []
            }
        }
    }

    /// When the app should next deliver a `.tick`, or nil if nothing is time-dependent.
    public func nextDeadline(now: TimeInterval) -> TimeInterval? {
        switch state {
        case .idle, .handsFree:
            return nil
        case .pending(let since):
            return since + timing.tapThreshold
        case .tapWindow(let releasedAt):
            // Strictly after the window closes, so the tick sees it as expired.
            return releasedAt + timing.doubleTapWindow + 0.001
        case .holding, .command:
            if let missing = triggerMissingSince {
                return missing + timing.missedReleaseGrace
            }
            return now + timing.pollInterval
        }
    }

    private mutating func handleIdle(_ input: HotkeyInput, at now: TimeInterval) -> [HotkeyEffect] {
        switch input {
        case .triggerDown(let held):
            if held.contains(.other) {
                // Cmd+Fn and friends are someone else's shortcut.
                return []
            }
            if held.contains(.control) {
                state = .command(since: now)
                return [.beginCapture(.command)]
            }
            state = .pending(since: now)
            return [.beginCapture(.hold)]
        case .pillClick:
            state = .handsFree(since: now, awaitingLatchRelease: false)
            return [.beginCapture(.handsFree)]
        case .triggerUp, .controlDown, .otherKeyDown, .escape, .tick, .triggerFlag:
            return []
        }
    }

    private mutating func noteTriggerFlag(_ isDown: Bool, at now: TimeInterval) {
        if isDown {
            triggerMissingSince = nil
        } else if triggerMissingSince == nil {
            triggerMissingSince = now
        }
    }

    private mutating func finishIfReleaseWasMissed(at now: TimeInterval, mode: CaptureMode) -> [HotkeyEffect] {
        guard let missing = triggerMissingSince, now - missing >= timing.missedReleaseGrace else {
            return []
        }
        reset()
        return [.finish(mode)]
    }
}
