import Foundation

/// `evals/manifest.json`: the clips to score. Audio paths are relative to the manifest file.
public struct EvalManifest: Codable, Sendable, Equatable {
    public var clips: [EvalClip]

    public init(clips: [EvalClip]) {
        self.clips = clips
    }

    public static func load(from url: URL) throws -> EvalManifest {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(EvalManifest.self, from: data)
    }
}

public struct EvalClip: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    /// Path to the recording (WAV, M4A, MP3...), relative to the manifest.
    public var audio: String
    /// Group used in the report: casual, fast, self-correction, list, names, hinglish, code...
    public var category: String?
    /// Exactly what was said, word for word. Raw ASR output is scored against this.
    public var reference: String
    /// The ideal cleaned-up output. Cleanup engines are scored against this (Milestone 4).
    public var expected: String?
    /// Bundle ID of the app the dictation was meant for, for app-aware styles (Milestone 4).
    public var app: String?
    /// BCP-47 language code, "en" by default.
    public var language: String?

    public init(id: String, audio: String, category: String? = nil, reference: String,
                expected: String? = nil, app: String? = nil, language: String? = nil) {
        self.id = id
        self.audio = audio
        self.category = category
        self.reference = reference
        self.expected = expected
        self.app = app
        self.language = language
    }
}

/// Result for one clip.
public struct EvalClipResult: Codable, Sendable, Equatable {
    public var id: String
    public var category: String?
    public var reference: String
    public var hypothesis: String
    public var wer: WordErrorRate
    public var audioSeconds: TimeInterval
    public var processingSeconds: TimeInterval

    public init(id: String, category: String?, reference: String, hypothesis: String,
                wer: WordErrorRate, audioSeconds: TimeInterval, processingSeconds: TimeInterval) {
        self.id = id
        self.category = category
        self.reference = reference
        self.hypothesis = hypothesis
        self.wer = wer
        self.audioSeconds = audioSeconds
        self.processingSeconds = processingSeconds
    }
}

/// A full run: per-clip results plus a summary, rendered as JSON and Markdown.
public struct EvalReport: Codable, Sendable, Equatable {
    public var createdAt: String
    public var engine: String
    public var clips: [EvalClipResult]
    public var failures: [String]

    public init(createdAt: String, engine: String, clips: [EvalClipResult], failures: [String] = []) {
        self.createdAt = createdAt
        self.engine = engine
        self.clips = clips
        self.failures = failures
    }

    public var corpusWER: WordErrorRate {
        WordErrorRate.aggregate(clips.map(\.wer))
    }

    public var latencyP50: TimeInterval? {
        Percentiles.value(50, of: clips.map(\.processingSeconds))
    }

    public var latencyP95: TimeInterval? {
        Percentiles.value(95, of: clips.map(\.processingSeconds))
    }

    /// Corpus WER per category, sorted by category name.
    public var werByCategory: [(category: String, wer: WordErrorRate)] {
        let grouped = Dictionary(grouping: clips) { $0.category ?? "uncategorised" }
        return grouped.keys.sorted().map { key in
            (category: key, wer: WordErrorRate.aggregate(grouped[key]!.map(\.wer)))
        }
    }

    public func markdown() -> String {
        var lines: [String] = []
        lines.append("# Eval report — \(engine)")
        lines.append("")
        lines.append("Run at \(createdAt). \(clips.count) clip(s) scored, \(failures.count) failed.")
        lines.append("")
        lines.append("| Metric | Value |")
        lines.append("|---|---|")
        lines.append("| Corpus WER (raw ASR) | \(Self.percent(corpusWER.rate)) |")
        lines.append("| Substitutions / deletions / insertions | \(corpusWER.operations.substitutions) / \(corpusWER.operations.deletions) / \(corpusWER.operations.insertions) |")
        lines.append("| Transcription latency p50 | \(Self.milliseconds(latencyP50)) |")
        lines.append("| Transcription latency p95 | \(Self.milliseconds(latencyP95)) |")
        lines.append("")
        if !clips.isEmpty {
            lines.append("## By category")
            lines.append("")
            lines.append("| Category | WER |")
            lines.append("|---|---|")
            for entry in werByCategory {
                lines.append("| \(entry.category) | \(Self.percent(entry.wer.rate)) |")
            }
            lines.append("")
            lines.append("## Clips")
            lines.append("")
            lines.append("| Clip | Category | WER | Audio | Latency | Hypothesis |")
            lines.append("|---|---|---|---|---|---|")
            for clip in clips {
                let hypothesis = clip.hypothesis
                    .replacingOccurrences(of: "|", with: "\\|")
                    .replacingOccurrences(of: "\n", with: " ")
                lines.append("| \(clip.id) | \(clip.category ?? "") | \(Self.percent(clip.wer.rate)) | \(String(format: "%.1f s", clip.audioSeconds)) | \(Self.milliseconds(clip.processingSeconds)) | \(hypothesis) |")
            }
        }
        if !failures.isEmpty {
            lines.append("")
            lines.append("## Failures")
            lines.append("")
            for failure in failures {
                lines.append("- \(failure)")
            }
        }
        return lines.joined(separator: "\n") + "\n"
    }

    static func percent(_ value: Double) -> String {
        String(format: "%.1f%%", value * 100)
    }

    static func milliseconds(_ value: TimeInterval?) -> String {
        guard let value else { return "—" }
        return "\(Int((value * 1000).rounded())) ms"
    }
}
