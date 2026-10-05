// Adapted from PushText (https://github.com/EvanCNavarro/PushText),
// Sources/PushTextCore/ModifierGate.swift at adf1660. MIT License, Copyright (c) 2026 Evan C. Navarro.
// Changes: renamed HotkeyBinding to HotkeyTrigger and trimmed it to the triggers Murmur offers; the
// gate now also classifies the other modifiers so the state machine can tell Fn+Ctrl (command mode)
// from Fn+anything-else (a chord that must cancel).

import Foundation

/// A physical key that works as the push-to-talk trigger.
///
/// Held-ness is read from the side-specific device bit in the raw `CGEventFlags` value, never from
/// the public union masks. `maskAlternate` stays set while *either* Option key is down, so watching
/// it would hide a right-Option release behind a left-Option hold and leave the microphone open.
public struct HotkeyTrigger: Hashable, Sendable {
    /// Stable identifier used in settings.
    public let id: String
    /// Virtual key code (`kVK_*`) of the physical key.
    public let keyCode: Int64
    /// Device-dependent modifier bit (`NX_DEVICE*KEYMASK`) for this key.
    public let deviceMask: UInt64
    /// Name shown in menus and logs.
    public let name: String

    public init(id: String, keyCode: Int64, deviceMask: UInt64, name: String) {
        self.id = id
        self.keyCode = keyCode
        self.deviceMask = deviceMask
        self.name = name
    }

    /// The Globe/Fn key: `kVK_Function` (0x3F) and `kCGEventFlagMaskSecondaryFn` (0x800000).
    ///
    /// Detected by its flag rather than its key code: some Apple Silicon Macs report a different
    /// key code for Globe in `flagsChanged`. The flag is also set on arrow and F-key `keyDown`
    /// events, which is why only `flagsChanged` events may be fed to a gate.
    public static let globe = HotkeyTrigger(id: "globe", keyCode: 0x3F, deviceMask: ModifierMask.function, name: "Globe (fn)")
    /// Right Option: `kVK_RightOption` (0x3D), `NX_DEVICERALTKEYMASK` (0x40).
    public static let rightOption = HotkeyTrigger(id: "rightOption", keyCode: 0x3D, deviceMask: ModifierMask.rightOption, name: "Right Option")
    /// Right Command: `kVK_RightCommand` (0x36), `NX_DEVICERCMDKEYMASK` (0x10).
    public static let rightCommand = HotkeyTrigger(id: "rightCommand", keyCode: 0x36, deviceMask: ModifierMask.rightCommand, name: "Right Command")

    /// Triggers offered in the menu, default first.
    public static let all: [HotkeyTrigger] = [.globe, .rightOption, .rightCommand]

    public static func with(id: String) -> HotkeyTrigger? {
        all.first { $0.id == id }
    }

    /// Whether this trigger is held in a raw flag snapshot, ignoring every other modifier.
    public func isHeld(in rawFlags: UInt64) -> Bool {
        rawFlags & deviceMask != 0
    }

    /// Only Globe may have its own system action swallowed. Every other modifier has a second job
    /// (capitals, shortcuts) that consuming it would break.
    public var canTakeOverSystemAction: Bool {
        self == .globe
    }
}

/// Device-dependent modifier bits from `IOKit/hidsystem/IOLLEvent.h`. They are not symmetric:
/// right Control is 0x2000, nowhere near left Control's 0x1.
public enum ModifierMask {
    public static let leftControl: UInt64 = 0x0000_0001
    public static let leftShift: UInt64 = 0x0000_0002
    public static let rightShift: UInt64 = 0x0000_0004
    public static let leftCommand: UInt64 = 0x0000_0008
    public static let rightCommand: UInt64 = 0x0000_0010
    public static let leftOption: UInt64 = 0x0000_0020
    public static let rightOption: UInt64 = 0x0000_0040
    public static let rightControl: UInt64 = 0x0000_2000
    public static let function: UInt64 = 0x0080_0000

    public static let control: UInt64 = leftControl | rightControl
    /// Every side-specific modifier bit we track.
    public static let all: UInt64 = leftControl | leftShift | rightShift | leftCommand | rightCommand
        | leftOption | rightOption | rightControl | function
}

/// Virtual key codes Murmur cares about outside the trigger itself.
public enum KeyCode {
    public static let escape: Int64 = 0x35
}

/// Which way a trigger key just moved.
public enum HotkeyEdge: Equatable, Sendable {
    case pressed
    case released
}

/// What a `flagsChanged` event meant for the current trigger.
public enum FlagsChange: Equatable, Sendable {
    /// The trigger went down or up. `held` describes the other modifiers at that moment.
    case trigger(HotkeyEdge, held: HeldModifiers)
    /// Control went down while the trigger was held.
    case controlPressed
    /// Some other modifier went down while the trigger was held.
    case otherModifierPressed
    /// Nothing relevant: a release, or a change while the trigger is up.
    case irrelevant
}

/// Turns raw modifier-flag snapshots into trigger edges and modifier events for one trigger.
///
/// `flagsChanged` reports the whole new modifier state, not a delta, and fires for every
/// modifier. The gate keeps the previous snapshot and reports only what changed.
public struct ModifierGate: Sendable {
    public let trigger: HotkeyTrigger
    public private(set) var isDown: Bool
    private var lastFlags: UInt64

    public init(trigger: HotkeyTrigger, flags: UInt64 = 0) {
        self.trigger = trigger
        self.isDown = trigger.isHeld(in: flags)
        self.lastFlags = flags
    }

    /// Feed the raw flags from a `flagsChanged` event.
    public mutating func update(flags: UInt64) -> FlagsChange {
        let previous = lastFlags
        lastFlags = flags

        let nowDown = trigger.isHeld(in: flags)
        let others = ModifierMask.all & ~trigger.deviceMask
        if nowDown != isDown {
            isDown = nowDown
            return .trigger(nowDown ? .pressed : .released, held: HeldModifiers(flags: flags & others))
        }

        guard isDown else { return .irrelevant }
        let newlyDown = (flags & others) & ~(previous & others)
        guard newlyDown != 0 else { return .irrelevant }
        if newlyDown & ~ModifierMask.control == 0 {
            return .controlPressed
        }
        return .otherModifierPressed
    }

    /// Re-synchronise with a live flag snapshot, for example after the event tap was re-enabled
    /// and may have missed events. Returns the edge if the trigger's state changed.
    public mutating func resynchronise(flags: UInt64) -> HotkeyEdge? {
        lastFlags = flags
        let nowDown = trigger.isHeld(in: flags)
        guard nowDown != isDown else { return nil }
        isDown = nowDown
        return nowDown ? .pressed : .released
    }
}
