import Foundation
import GRDB

/// Every delivered dictation, newest first, in a SQLite database that never leaves the Mac.
///
/// Thread-safe: GRDB's `DatabaseQueue` serialises all access, so the store can be shared and called
/// from any thread. Calls are synchronous and fast (a few milliseconds), but the app still makes
/// writes off the main thread.
public final class HistoryStore: Sendable {
    private let queue: DatabaseQueue

    /// Opens the database at `url`, creating it and its folder if needed, and migrates it.
    public convenience init(url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try self.init(queue: DatabaseQueue(path: url.path))
    }

    /// A store that lives only in memory, for tests.
    public static func inMemory() throws -> HistoryStore {
        try HistoryStore(queue: DatabaseQueue())
    }

    private init(queue: DatabaseQueue) throws {
        self.queue = queue
        try Self.migrator.migrate(queue)
    }

    // MARK: - Writing

    public func add(_ entry: DictationEntry) throws {
        try queue.write { db in
            try entry.insert(db)
        }
    }

    public func delete(id: UUID) throws {
        try queue.write { db in
            _ = try DictationEntry.deleteOne(db, key: id)
        }
    }

    public func deleteAll() throws {
        try queue.write { db in
            _ = try DictationEntry.deleteAll(db)
        }
    }

    // MARK: - Reading

    public func recent(limit: Int = 500) throws -> [DictationEntry] {
        try queue.read { db in
            try DictationEntry
                .order(Column("createdAt").desc)
                .limit(limit)
                .fetchAll(db)
        }
    }

    /// Entries whose text or app name contains `query`, ignoring case (for ASCII letters), newest
    /// first. An empty query returns the most recent entries.
    public func search(_ query: String, limit: Int = 500) throws -> [DictationEntry] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return try recent(limit: limit) }
        let pattern = "%" + Self.escapeLikePattern(trimmed) + "%"
        return try queue.read { db in
            try DictationEntry.fetchAll(
                db,
                sql: """
                    SELECT * FROM dictation
                    WHERE text LIKE ? ESCAPE '\\' OR appName LIKE ? ESCAPE '\\'
                    ORDER BY createdAt DESC
                    LIMIT ?
                    """,
                arguments: [pattern, pattern, limit]
            )
        }
    }

    public func entry(id: UUID) throws -> DictationEntry? {
        try queue.read { db in
            try DictationEntry.fetchOne(db, key: id)
        }
    }

    public func count() throws -> Int {
        try queue.read { db in
            try DictationEntry.fetchCount(db)
        }
    }

    // MARK: - Helpers

    /// Escapes `LIKE` wildcards so a search for "100%" or "file_name" matches literally.
    static func escapeLikePattern(_ text: String) -> String {
        var escaped = ""
        escaped.reserveCapacity(text.count)
        for character in text {
            if character == "\\" || character == "%" || character == "_" {
                escaped.append("\\")
            }
            escaped.append(character)
        }
        return escaped
    }

    private static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1-dictation") { db in
            try db.create(table: "dictation") { t in
                t.primaryKey("id", .blob)
                t.column("createdAt", .datetime).notNull().indexed()
                t.column("text", .text).notNull()
                t.column("mode", .text).notNull()
                t.column("engine", .text).notNull()
                t.column("audioSeconds", .double).notNull()
                t.column("appName", .text)
                t.column("appBundleID", .text)
                t.column("wordCount", .integer).notNull()
                t.column("timeline", .text)
            }
        }
        return migrator
    }
}
