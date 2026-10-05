import Foundation

/// Murmur's folders under `~/Library/Application Support/Murmur`.
struct AppPaths: Sendable {
    let root: URL
    /// Raw audio of in-progress dictations, kept until the text is delivered so a crash loses
    /// nothing. Deleted after each successful dictation.
    let spool: URL
    /// Dictation history (SQLite). Text only; never leaves the Mac.
    let database: URL

    init(fileManager: FileManager = .default) {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        root = base.appendingPathComponent("Murmur", isDirectory: true)
        spool = root.appendingPathComponent("Spool", isDirectory: true)
        database = root.appendingPathComponent("history.sqlite")
    }

    func ensureDirectories() {
        for directory in [root, spool] {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
    }

    /// Spool files left behind by a crash or failed dictation.
    func leftoverSpoolFiles() -> [URL] {
        let contents = (try? FileManager.default.contentsOfDirectory(at: spool, includingPropertiesForKeys: nil)) ?? []
        return contents.filter { $0.pathExtension == "f32" }
    }
}
