import AppKit
import MurmurCore
import MurmurEngines
import MurmurStorage
import OSLog

/// "Copy Diagnostics": everything needed to debug a report from the user's Mac, without
/// transcript text unless verbose diagnostics is switched on.
@MainActor
enum Diagnostics {
    static func copyReport(for environment: AppEnvironment) {
        Clipboard.copy(report(for: environment))
    }

    static func report(for environment: AppEnvironment) -> String {
        var lines: [String] = []
        let info = Bundle.main.infoDictionary ?? [:]
        let version = info["CFBundleShortVersionString"] as? String ?? "dev"
        let build = info["CFBundleVersion"] as? String ?? "?"
        let memoryGB = Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824

        lines.append("Murmur \(version) (\(build)) — diagnostics \(Date().formatted(.iso8601))")
        lines.append("macOS \(ProcessInfo.processInfo.operatingSystemVersionString)")
        lines.append("Chip: \(chipName()) · RAM: \(String(format: "%.0f", memoryGB)) GB")
        lines.append("Bundle: \(Bundle.main.bundleIdentifier ?? "none") at \(Bundle.main.bundlePath)")
        lines.append("")
        lines.append("Speech model: \(environment.settings.asrModel.displayName) — \(describe(environment.modelState))")
        lines.append("Microphone: \(describe(Permissions.microphone))")
        lines.append("Accessibility: \(Permissions.accessibilityTrusted ? "granted" : "not granted")")
        lines.append("Globe key action: \(GlobeKeySetting.currentAction().settingsTitle)")
        lines.append("Hotkey tap: \(environment.hotkeyTapStatus)")
        let settings = environment.settings.diagnosticsSummary
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: ", ")
        lines.append("Settings: \(settings)")
        lines.append("")

        let savedCount = (try? environment.historyStore?.count()).map { String($0) } ?? "unavailable"
        lines.append("History: \(savedCount) saved · saving new: \(environment.settings.saveHistory ? "on" : "off")")
        // This session only: entries loaded from the database at launch would muddle the latencies.
        let records = environment.dictation.recent.filter { $0.createdAt >= environment.launchedAt }.suffix(20)
        lines.append("Recent dictations this session, newest last (\(records.count)):")
        for record in records {
            let summary = record.timeline?.summary() ?? "\(record.mode.rawValue) · \(record.engine)"
            var line = "- \(summary)"
            if let app = record.appName {
                line += " · \(app)"
            }
            if environment.settings.verboseDiagnostics {
                line += " — \"\(record.text)\""
            }
            lines.append(line)
        }
        lines.append("")
        lines.append("Log, this session:")
        lines.append(contentsOf: recentLogLines(limit: 200))
        return lines.joined(separator: "\n")
    }

    static func describe(_ state: ParakeetEngine.LoadState) -> String {
        switch state {
        case .notLoaded: return "not loaded"
        case .downloading(let fraction): return "downloading \(Int(fraction * 100))%"
        case .compiling: return "compiling for the Neural Engine"
        case .warmingUp: return "warming up"
        case .ready: return "ready"
        case .failed(let reason): return "failed: \(reason)"
        }
    }

    static func describe(_ state: PermissionState) -> String {
        switch state {
        case .granted: return "granted"
        case .denied: return "denied"
        case .notDetermined: return "not asked yet"
        }
    }

    /// This process's own log lines. Values logged as private stay redacted.
    static func recentLogLines(limit: Int) -> [String] {
        do {
            let store = try OSLogStore(scope: .currentProcessIdentifier)
            let position = store.position(date: Date().addingTimeInterval(-12 * 3600))
            let predicate = NSPredicate(format: "subsystem == %@", Log.subsystem)
            var lines: [String] = []
            for case let entry as OSLogEntryLog in try store.getEntries(at: position, matching: predicate) {
                lines.append("\(entry.date.formatted(.iso8601)) [\(entry.category)] \(entry.composedMessage)")
            }
            return Array(lines.suffix(limit))
        } catch {
            return ["(log unavailable: \(error.localizedDescription))"]
        }
    }

    static func chipName() -> String {
        var size = 0
        guard sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0) == 0, size > 0 else {
            return "unknown"
        }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname("machdep.cpu.brand_string", &buffer, &size, nil, 0) == 0 else {
            return "unknown"
        }
        let bytes = buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
        return String(decoding: bytes, as: UTF8.self)
    }
}
