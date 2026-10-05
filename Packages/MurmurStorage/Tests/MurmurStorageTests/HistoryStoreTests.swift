import Foundation
import MurmurCore
import XCTest
@testable import MurmurStorage

final class HistoryStoreTests: XCTestCase {
    // Whole seconds: the database keeps dates to the millisecond, so equality checks need dates
    // that survive the round trip exactly.
    private let base = Date(timeIntervalSince1970: 1_790_000_000)

    private func entry(_ text: String, minutesAgo: Double = 0, app: String? = nil) -> DictationEntry {
        DictationEntry(
            createdAt: base.addingTimeInterval(-minutesAgo * 60),
            text: text,
            mode: .hold,
            engine: "parakeet-ultra",
            audioSeconds: 2.5,
            appName: app,
            appBundleID: app.map { "com.example.\($0.lowercased())" }
        )
    }

    func testRecentIsNewestFirstAndLimited() throws {
        let store = try HistoryStore.inMemory()
        try store.add(entry("oldest", minutesAgo: 30))
        try store.add(entry("newest", minutesAgo: 0))
        try store.add(entry("middle", minutesAgo: 10))

        XCTAssertEqual(try store.recent().map(\.text), ["newest", "middle", "oldest"])
        XCTAssertEqual(try store.recent(limit: 2).map(\.text), ["newest", "middle"])
        XCTAssertEqual(try store.count(), 3)
    }

    func testRoundTripKeepsEveryField() throws {
        let store = try HistoryStore.inMemory()
        var timeline = DictationTimeline(mode: .handsFree, engine: "parakeet-ultra", pressedAt: 100)
        timeline.releasedAt = 104
        timeline.deliveredAt = 104.25
        timeline.audioSeconds = 3.5
        let original = DictationEntry(
            createdAt: base,
            text: "Ship it on Thursday.",
            mode: .handsFree,
            engine: "parakeet-ultra",
            audioSeconds: 3.5,
            appName: "Slack",
            appBundleID: "com.tinyspeck.slackmacgap",
            timeline: timeline
        )
        try store.add(original)

        let loaded = try XCTUnwrap(try store.entry(id: original.id))
        XCTAssertEqual(loaded, original)
        XCTAssertEqual(loaded.wordCount, 4)
        XCTAssertEqual(loaded.timeline?.postReleaseLatency, 0.25)
    }

    func testMissingAppAndTimelineAreNil() throws {
        let store = try HistoryStore.inMemory()
        let original = entry("no app")
        try store.add(original)
        let loaded = try XCTUnwrap(try store.entry(id: original.id))
        XCTAssertNil(loaded.appName)
        XCTAssertNil(loaded.timeline)
    }

    func testSearchMatchesTextAndAppIgnoringCase() throws {
        let store = try HistoryStore.inMemory()
        try store.add(entry("Meet at the LIBRARY at four", minutesAgo: 5, app: "Messages"))
        try store.add(entry("Draft the MUN position paper", minutesAgo: 1, app: "Pages"))
        try store.add(entry("Buy milk", minutesAgo: 2, app: "Reminders"))

        XCTAssertEqual(try store.search("library").map(\.text), ["Meet at the LIBRARY at four"])
        XCTAssertEqual(try store.search("pages").map(\.text), ["Draft the MUN position paper"])
        XCTAssertEqual(try store.search("  ").count, 3, "blank query returns recent entries")
        XCTAssertEqual(try store.search("nothing like this").count, 0)
    }

    func testSearchTreatsWildcardsLiterally() throws {
        let store = try HistoryStore.inMemory()
        try store.add(entry("Battery at 100% today"))
        try store.add(entry("Battery at 1000 percent"))
        try store.add(entry("rename file_name.txt"))
        try store.add(entry("rename filename.txt"))

        XCTAssertEqual(try store.search("100%").map(\.text), ["Battery at 100% today"])
        XCTAssertEqual(try store.search("file_name").map(\.text), ["rename file_name.txt"])
        XCTAssertEqual(HistoryStore.escapeLikePattern(#"a%b_c\d"#), #"a\%b\_c\\d"#)
    }

    func testDeleteOneAndAll() throws {
        let store = try HistoryStore.inMemory()
        let keep = entry("keep", minutesAgo: 1)
        let drop = entry("drop")
        try store.add(keep)
        try store.add(drop)

        try store.delete(id: drop.id)
        XCTAssertEqual(try store.recent().map(\.text), ["keep"])
        XCTAssertNil(try store.entry(id: drop.id))

        try store.deleteAll()
        XCTAssertEqual(try store.count(), 0)
    }

    func testFileDatabaseSurvivesReopening() throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("murmur-history-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("history.sqlite")

        do {
            let store = try HistoryStore(url: url)
            try store.add(entry("persisted"))
        }
        let reopened = try HistoryStore(url: url)
        XCTAssertEqual(try reopened.recent().map(\.text), ["persisted"])
    }
}
