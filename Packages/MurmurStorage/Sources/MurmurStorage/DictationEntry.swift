import Foundation
import GRDB
import MurmurCore

/// One delivered dictation, as kept in the history.
public struct DictationEntry: Codable, Sendable, Equatable, Identifiable {
    public var id: UUID
    public var createdAt: Date
    public var text: String
    public var mode: CaptureMode
    /// Speech engine identifier, for example `parakeet-ultra`.
    public var engine: String
    /// Seconds of audio captured (paused time excluded).
    public var audioSeconds: Double
    /// The app that had focus when the dictation started.
    public var appName: String?
    public var appBundleID: String?
    public var wordCount: Int
    /// Stage timestamps and latencies. Stored as JSON; contains no text.
    public var timeline: DictationTimeline?

    public init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        text: String,
        mode: CaptureMode,
        engine: String,
        audioSeconds: Double,
        appName: String? = nil,
        appBundleID: String? = nil,
        timeline: DictationTimeline? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.text = text
        self.mode = mode
        self.engine = engine
        self.audioSeconds = audioSeconds
        self.appName = appName
        self.appBundleID = appBundleID
        self.wordCount = text.split(whereSeparator: \.isWhitespace).count
        self.timeline = timeline
    }
}

extension DictationEntry: FetchableRecord, PersistableRecord {
    public static let databaseTableName = "dictation"
}
