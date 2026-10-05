import Foundation

/// Timestamps for one dictation, in monotonic seconds, plus the derived latencies that the
/// acceptance tests are measured by. Contains no transcript text, so it is safe to put in
/// diagnostics.
public struct DictationTimeline: Sendable, Equatable, Codable {
    public var mode: CaptureMode
    public var engine: String
    /// Trigger pressed (or pill clicked).
    public var pressedAt: TimeInterval
    /// The microphone delivered its first audio.
    public var captureStartedAt: TimeInterval?
    /// Trigger released (or hands-free stopped).
    public var releasedAt: TimeInterval?
    /// Capture stopped and all audio was in hand.
    public var audioReadyAt: TimeInterval?
    /// The engine returned text.
    public var transcribedAt: TimeInterval?
    /// The text was on the clipboard.
    public var deliveredAt: TimeInterval?
    /// Seconds of audio captured.
    public var audioSeconds: TimeInterval

    public init(mode: CaptureMode, engine: String, pressedAt: TimeInterval) {
        self.mode = mode
        self.engine = engine
        self.pressedAt = pressedAt
        self.audioSeconds = 0
    }

    /// Release to text-on-clipboard: the number the "< 1 s" acceptance test is about.
    public var postReleaseLatency: TimeInterval? {
        guard let releasedAt, let deliveredAt else { return nil }
        return deliveredAt - releasedAt
    }

    /// Time the engine spent transcribing.
    public var transcriptionTime: TimeInterval? {
        guard let audioReadyAt, let transcribedAt else { return nil }
        return transcribedAt - audioReadyAt
    }

    /// How long the microphone took to start after the press.
    public var captureStartDelay: TimeInterval? {
        guard let captureStartedAt else { return nil }
        return captureStartedAt - pressedAt
    }

    /// One line for diagnostics, for example
    /// `hold · 3.2 s audio · mic start 85 ms · transcribe 140 ms · release→clipboard 410 ms · parakeet-ultra`.
    public func summary() -> String {
        var parts = [mode.rawValue, String(format: "%.1f s audio", audioSeconds)]
        if let delay = captureStartDelay { parts.append("mic start \(Self.milliseconds(delay))") }
        if let time = transcriptionTime { parts.append("transcribe \(Self.milliseconds(time))") }
        if let latency = postReleaseLatency { parts.append("release→clipboard \(Self.milliseconds(latency))") }
        parts.append(engine)
        return parts.joined(separator: " · ")
    }

    static func milliseconds(_ seconds: TimeInterval) -> String {
        "\(Int((seconds * 1000).rounded())) ms"
    }
}
