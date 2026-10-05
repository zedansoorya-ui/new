import Foundation
import MurmurCore
import MurmurEngines

/// User preferences, backed by `UserDefaults`. A settings window arrives in Milestone 6; until then
/// the menu-bar menu exposes the options people need for testing.
@MainActor
final class Settings {
    private enum Key {
        static let trigger = "trigger"
        static let takeOverGlobeKey = "takeOverGlobeKey"
        static let asrModel = "asrModel"
        static let releaseTailMilliseconds = "releaseTailMilliseconds"
        static let hasCompletedOnboarding = "hasCompletedOnboarding"
        static let verboseDiagnostics = "verboseDiagnostics"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// The push-to-talk key. Globe/Fn by default.
    var trigger: HotkeyTrigger {
        get { HotkeyTrigger.with(id: defaults.string(forKey: Key.trigger) ?? "") ?? .globe }
        set { defaults.set(newValue.id, forKey: Key.trigger) }
    }

    /// Swallow the Globe key's own events so macOS's action (emoji picker, input source, Apple
    /// dictation) does not fire alongside Murmur. Off by default: onboarding asks the user to set
    /// "Press 🌐 key to" to "Do Nothing" instead.
    var takeOverGlobeKey: Bool {
        get { defaults.bool(forKey: Key.takeOverGlobeKey) }
        set { defaults.set(newValue, forKey: Key.takeOverGlobeKey) }
    }

    /// Which Parakeet model to load. Changing it takes effect on next launch.
    var asrModel: ParakeetEngine.Model {
        get { ParakeetEngine.Model(rawValue: defaults.string(forKey: Key.asrModel) ?? "") ?? .ultra }
        set { defaults.set(newValue.rawValue, forKey: Key.asrModel) }
    }

    /// Keep recording this long after the key is released, so the end of the last word is not cut.
    var releaseTail: TimeInterval {
        let milliseconds = defaults.object(forKey: Key.releaseTailMilliseconds) as? Int ?? 150
        return TimeInterval(min(max(milliseconds, 0), 1000)) / 1000
    }

    var hasCompletedOnboarding: Bool {
        get { defaults.bool(forKey: Key.hasCompletedOnboarding) }
        set { defaults.set(newValue, forKey: Key.hasCompletedOnboarding) }
    }

    /// Include transcript text in diagnostics. Off by default.
    var verboseDiagnostics: Bool {
        get { defaults.bool(forKey: Key.verboseDiagnostics) }
        set { defaults.set(newValue, forKey: Key.verboseDiagnostics) }
    }

    /// Non-secret settings for the diagnostics report.
    var diagnosticsSummary: [String: String] {
        [
            "trigger": trigger.id,
            "takeOverGlobeKey": String(takeOverGlobeKey),
            "asrModel": asrModel.rawValue,
            "releaseTailMs": String(Int(releaseTail * 1000)),
            "verboseDiagnostics": String(verboseDiagnostics),
        ]
    }
}
