// Adapted from PushText (https://github.com/EvanCNavarro/PushText),
// Sources/PushTextKit/GlobeKeySetting.swift at adf1660. MIT License, Copyright (c) 2026 Evan C. Navarro.

import Foundation
import MurmurCore

/// Reads System Settings ▸ Keyboard ▸ "Press 🌐 key to". Read-only on purpose; see `GlobeKeyAction`.
enum GlobeKeySetting {
    static func currentAction() -> GlobeKeyAction {
        // CFPreferences rather than UserDefaults(suiteName:): this is another app's domain.
        let value = CFPreferencesCopyAppValue("AppleFnUsageType" as CFString, "com.apple.HIToolbox" as CFString)
        return GlobeKeyAction.from(storedValue: value as? Int)
    }
}

/// Marks keystrokes Murmur synthesises (paste, copy) so the hotkey tap ignores them instead of
/// treating them as a chord that cancels the capture. "MURMUR" packed into `eventSourceUserData`.
enum SyntheticEvent {
    static let marker: Int64 = 0x4D55_524D_5552
}
