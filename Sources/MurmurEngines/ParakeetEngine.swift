// Adapted from Muesli (https://github.com/Muesli-HQ/muesli),
// native/MuesliNative/Sources/MuesliNativeApp/FluidAudioBackend.swift at 906df1c.
// MIT License, Copyright (c) 2026 Pranav Hari.
// Changes: moved to FluidAudio 0.17.5's downloadAndLoad API with Parakeet Ultra as the default,
// conforms to Murmur's TranscriptionEngine protocol, pads clips shorter than Parakeet's minimum,
// and runs a warm-up pass after loading.

import FluidAudio
import Foundation
import MurmurCore

/// Parakeet TDT speech recognition on the Apple Neural Engine, via FluidAudio.
public actor ParakeetEngine: TranscriptionEngine {
    public enum Model: String, CaseIterable, Sendable {
        /// moondream's post-training of v3: same languages and speed, lower error rates.
        /// FluidAudio's recommendation for new integrations.
        case ultra
        /// Multilingual Parakeet TDT 0.6B v3 (25 European languages).
        case v3
        /// English-only Parakeet TDT 0.6B v2.
        case v2

        public var displayName: String {
            switch self {
            case .ultra: return "Parakeet Ultra"
            case .v3: return "Parakeet v3"
            case .v2: return "Parakeet v2 (English)"
            }
        }

        var version: AsrModelVersion {
            switch self {
            case .ultra: return .ultra
            case .v3: return .v3
            case .v2: return .v2
            }
        }
    }

    public enum LoadState: Sendable, Equatable {
        case notLoaded
        case downloading(Double)
        case compiling
        case warmingUp
        case ready
        case failed(String)
    }

    public enum EngineError: LocalizedError {
        case notReady

        public var errorDescription: String? {
            switch self {
            case .notReady: return "The speech model is not loaded yet."
            }
        }
    }

    public nonisolated let identifier: String
    public nonisolated let model: Model
    private var manager: AsrManager?

    public init(model: Model) {
        self.model = model
        self.identifier = "parakeet-\(model.rawValue)"
    }

    public var isReady: Bool {
        manager != nil
    }

    /// Downloads the model if needed (about 630 MB the first time), loads it into Core ML
    /// and runs one warm-up pass so the first real dictation is fast. Safe to call again after a
    /// failure.
    public func prepare(onState: @escaping @Sendable (LoadState) -> Void) async {
        if manager != nil {
            onState(.ready)
            return
        }
        do {
            onState(.downloading(0))
            let models = try await AsrModels.downloadAndLoad(
                version: model.version,
                progressHandler: { progress in
                    switch progress.phase {
                    case .compiling:
                        onState(.compiling)
                    case .listing, .downloading:
                        onState(.downloading(progress.fractionCompleted))
                    }
                }
            )
            let manager = AsrManager(config: .default)
            try await manager.loadModels(models)
            self.manager = manager

            onState(.warmingUp)
            let silence = [Float](repeating: 0, count: AudioSamples.sampleRate)
            _ = try? await transcribe(samples: silence, sampleRate: AudioSamples.sampleRate)
            onState(.ready)
        } catch {
            manager = nil
            onState(.failed(error.localizedDescription))
        }
    }

    public func transcribe(samples: [Float], sampleRate: Int) async throws -> TranscriptionResult {
        guard let manager else { throw EngineError.notReady }
        // Parakeet rejects audio under 0.3 s; pad with silence rather than drop a short word.
        let input = AudioSamples.padded(samples, toAtLeast: Int(Double(sampleRate) * 0.35))
        let started = ProcessInfo.processInfo.systemUptime
        var decoderState = TdtDecoderState.make(decoderLayers: await manager.decoderLayerCount)
        let result = try await manager.transcribe(input, decoderState: &decoderState, language: .english)
        return TranscriptionResult(
            text: result.text,
            confidence: Double(result.confidence),
            audioSeconds: AudioSamples.duration(sampleCount: samples.count, sampleRate: sampleRate),
            processingSeconds: ProcessInfo.processInfo.systemUptime - started
        )
    }
}
