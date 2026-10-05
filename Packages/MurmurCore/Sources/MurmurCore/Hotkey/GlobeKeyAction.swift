// Adapted from PushText (https://github.com/EvanCNavarro/PushText),
// Sources/PushTextCore/GlobeKeyConflict.swift at adf1660. MIT License, Copyright (c) 2026 Evan C. Navarro.
// Changes: renamed and merged the conflict check into the enum.

import Foundation

/// What macOS does when the Globe key is pressed: System Settings ▸ Keyboard ▸ "Press 🌐 key to".
///
/// Stored as `AppleFnUsageType` in the `com.apple.HIToolbox` preferences domain. Murmur only ever
/// *reads* it. Apps that write it through private API can leave the Globe key permanently dead if
/// they crash mid-write, even after being uninstalled.
public enum GlobeKeyAction: Int, Equatable, Sendable, CaseIterable {
    case doNothing = 0
    case changeInputSource = 1
    case showEmoji = 2
    case startDictation = 3

    /// The wording System Settings uses.
    public var settingsTitle: String {
        switch self {
        case .doNothing: return "Do Nothing"
        case .changeInputSource: return "Change Input Source"
        case .showEmoji: return "Show Emoji & Symbols"
        case .startDictation: return "Start Dictation"
        }
    }

    /// Interprets the stored preference. A missing or unknown value is the factory default,
    /// which on a Mac with a Globe key is *not* "Do Nothing", so it must not read as safe.
    public static func from(storedValue: Int?) -> GlobeKeyAction {
        guard let storedValue, let action = GlobeKeyAction(rawValue: storedValue) else {
            return .changeInputSource
        }
        return action
    }

    /// True when pressing Globe for dictation would also trigger a system action.
    public var conflictsWithDictation: Bool {
        self != .doNothing
    }
}
