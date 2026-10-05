import OSLog

/// Unified-log categories under the `com.zedan.murmur` subsystem.
///
/// Transcript text is only ever logged with `privacy: .private`, so it is redacted in the unified
/// log and in "Copy diagnostics".
enum Log {
    static let subsystem = "com.zedan.murmur"

    static let app = Logger(subsystem: subsystem, category: "app")
    static let hotkey = Logger(subsystem: subsystem, category: "hotkey")
    static let audio = Logger(subsystem: subsystem, category: "audio")
    static let asr = Logger(subsystem: subsystem, category: "asr")
    static let output = Logger(subsystem: subsystem, category: "output")
    static let ui = Logger(subsystem: subsystem, category: "ui")
}
