import Foundation

/// A speech-to-text engine. Implementations live in the app package (Parakeet via FluidAudio
/// today; WhisperKit or others later) so that everything above them stays engine-agnostic.
public protocol TranscriptionEngine: Sendable {
    /// Stable identifier recorded with each dictation, for example "parakeet-ultra".
    var identifier: String { get }

    /// Transcribes mono Float32 samples.
    func transcribe(samples: [Float], sampleRate: Int) async throws -> TranscriptionResult
}

public struct TranscriptionResult: Sendable, Equatable, Codable {
    public var text: String
    /// Engine-reported confidence in 0...1, when the engine provides one.
    public var confidence: Double?
    /// Length of the audio that was transcribed.
    public var audioSeconds: TimeInterval
    /// Wall-clock time the engine spent.
    public var processingSeconds: TimeInterval

    public init(text: String, confidence: Double?, audioSeconds: TimeInterval, processingSeconds: TimeInterval) {
        self.text = text
        self.confidence = confidence
        self.audioSeconds = audioSeconds
        self.processingSeconds = processingSeconds
    }

    /// Real-time factor: seconds of audio processed per second of compute.
    public var realTimeFactor: Double? {
        guard processingSeconds > 0 else { return nil }
        return audioSeconds / processingSeconds
    }
}
