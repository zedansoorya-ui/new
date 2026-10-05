import FluidAudio
import Foundation
import MurmurCore
import MurmurEngines

enum EvalCLI {
    static let usage = """
    murmur-eval: score Murmur's speech recognition on your own recordings

    USAGE
      murmur-eval run [--manifest evals/manifest.json] [--model ultra|v3|v2] [--out evals/reports]
      murmur-eval transcribe <audio-file> [--model ultra|v3|v2]

    run         Transcribes every clip in the manifest and writes a Markdown + JSON report with
                word error rate (raw ASR against your verbatim reference) and latency percentiles.
    transcribe  Prints the transcript and timing for one file (WAV, M4A, MP3...).

    The first run downloads the speech model (about 630 MB).
    """

    static func run(_ arguments: [String]) async -> Int32 {
        guard let command = arguments.first else {
            print(usage)
            return 2
        }
        do {
            let options = try Options(Array(arguments.dropFirst()))
            switch command {
            case "run":
                return try await runManifest(options)
            case "transcribe":
                return try await transcribe(options)
            case "help", "-h", "--help":
                print(usage)
                return 0
            default:
                printError("Unknown command '\(command)'.\n\n\(usage)")
                return 2
            }
        } catch {
            printError("error: \(error.localizedDescription)")
            return 1
        }
    }

    // MARK: - Commands

    private static func transcribe(_ options: Options) async throws -> Int32 {
        guard let path = options.positional.first else {
            throw CLIError.missingArgument("an audio file to transcribe")
        }
        let url = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw CLIError.missingFile(path)
        }
        let engine = try await loadEngine(options.model())
        let samples = try AudioConverter().resampleAudioFile(url)
        let result = try await engine.transcribe(samples: samples, sampleRate: AudioSamples.sampleRate)
        print(TranscriptTidy.basic(result.text))
        printError(String(
            format: "%.1f s of audio in %.0f ms (%.0f× real time), %@",
            result.audioSeconds, result.processingSeconds * 1000, result.realTimeFactor ?? 0, engine.identifier
        ))
        return 0
    }

    private static func runManifest(_ options: Options) async throws -> Int32 {
        let manifestPath = options.values["manifest"] ?? "evals/manifest.json"
        let manifestURL = URL(fileURLWithPath: manifestPath)
        guard FileManager.default.fileExists(atPath: manifestURL.path) else {
            throw CLIError.missingFile("\(manifestPath). Copy evals/manifest.example.json and record clips first; see evals/README.md.")
        }
        let manifest = try EvalManifest.load(from: manifestURL)
        guard !manifest.clips.isEmpty else {
            throw CLIError.missingArgument("at least one clip in \(manifestPath)")
        }

        let engine = try await loadEngine(options.model())
        let converter = AudioConverter()
        var results: [EvalClipResult] = []
        var failures: [String] = []

        for clip in manifest.clips {
            let audioURL = manifestURL.deletingLastPathComponent().appendingPathComponent(clip.audio)
            do {
                let samples = try converter.resampleAudioFile(audioURL)
                let result = try await engine.transcribe(samples: samples, sampleRate: AudioSamples.sampleRate)
                let hypothesis = TranscriptTidy.basic(result.text)
                let wer = WordErrorRate.compute(reference: clip.reference, hypothesis: hypothesis)
                results.append(EvalClipResult(
                    id: clip.id,
                    category: clip.category,
                    reference: clip.reference,
                    hypothesis: hypothesis,
                    wer: wer,
                    audioSeconds: result.audioSeconds,
                    processingSeconds: result.processingSeconds
                ))
                print(String(format: "%@  WER %5.1f%%  %5.0f ms  %@", clip.id, wer.rate * 100, result.processingSeconds * 1000, hypothesis))
            } catch {
                failures.append("\(clip.id): \(error.localizedDescription)")
                printError("\(clip.id): \(error.localizedDescription)")
            }
        }

        let report = EvalReport(
            createdAt: Date().formatted(.iso8601),
            engine: engine.identifier,
            clips: results,
            failures: failures
        )
        let outDirectory = URL(fileURLWithPath: options.values["out"] ?? "evals/reports")
        try FileManager.default.createDirectory(at: outDirectory, withIntermediateDirectories: true)
        let stem = "\(fileStamp())-\(engine.identifier)"
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let jsonURL = outDirectory.appendingPathComponent("\(stem).json")
        let markdownURL = outDirectory.appendingPathComponent("\(stem).md")
        try encoder.encode(report).write(to: jsonURL)
        try report.markdown().write(to: markdownURL, atomically: true, encoding: .utf8)

        print("")
        print(String(format: "Corpus WER %.1f%% over %ld clip(s)", report.corpusWER.rate * 100, results.count))
        if let p50 = report.latencyP50, let p95 = report.latencyP95 {
            print(String(format: "Latency p50 %.0f ms, p95 %.0f ms", p50 * 1000, p95 * 1000))
        }
        print("Report: \(markdownURL.path)")
        return failures.isEmpty ? 0 : 1
    }

    // MARK: - Helpers

    private static func loadEngine(_ model: ParakeetEngine.Model) async throws -> ParakeetEngine {
        let engine = ParakeetEngine(model: model)
        let progress = ProgressPrinter()
        await engine.prepare { state in progress.report(state) }
        guard await engine.isReady else {
            throw CLIError.modelUnavailable(model.displayName)
        }
        return engine
    }

    private static func fileStamp() -> String {
        let components = Calendar(identifier: .gregorian).dateComponents(in: .current, from: Date())
        return String(
            format: "%04ld%02ld%02ld-%02ld%02ld%02ld",
            components.year ?? 0, components.month ?? 0, components.day ?? 0,
            components.hour ?? 0, components.minute ?? 0, components.second ?? 0
        )
    }
}

/// `--key value` options plus positional arguments.
struct Options {
    var positional: [String] = []
    var values: [String: String] = [:]

    init(_ arguments: [String]) throws {
        var iterator = arguments.makeIterator()
        while let argument = iterator.next() {
            if argument.hasPrefix("--") {
                guard let value = iterator.next() else { throw CLIError.missingValue(argument) }
                values[String(argument.dropFirst(2))] = value
            } else {
                positional.append(argument)
            }
        }
    }

    func model() throws -> ParakeetEngine.Model {
        guard let raw = values["model"] else { return .ultra }
        guard let model = ParakeetEngine.Model(rawValue: raw) else { throw CLIError.unknownModel(raw) }
        return model
    }
}

enum CLIError: LocalizedError {
    case missingValue(String)
    case missingArgument(String)
    case missingFile(String)
    case unknownModel(String)
    case modelUnavailable(String)

    var errorDescription: String? {
        switch self {
        case .missingValue(let option): return "\(option) needs a value."
        case .missingArgument(let what): return "Expected \(what)."
        case .missingFile(let path): return "File not found: \(path)"
        case .unknownModel(let raw): return "Unknown model '\(raw)'. Use ultra, v3 or v2."
        case .modelUnavailable(let name): return "\(name) could not be loaded. Check the network and disk space."
        }
    }
}

/// Prints model loading progress in 10% steps.
final class ProgressPrinter: @unchecked Sendable {
    private let lock = NSLock()
    private var lastStep = -1
    private var lastPhase = ""

    func report(_ state: ParakeetEngine.LoadState) {
        lock.lock()
        defer { lock.unlock() }
        switch state {
        case .downloading(let fraction):
            let step = Int(fraction * 10)
            guard step != lastStep else { return }
            lastStep = step
            printError("Downloading model… \(step * 10)%")
        case .compiling where lastPhase != "compiling":
            lastPhase = "compiling"
            printError("Compiling model for the Neural Engine…")
        case .warmingUp where lastPhase != "warmingUp":
            lastPhase = "warmingUp"
            printError("Warming up…")
        case .failed(let reason):
            printError("Model failed to load: \(reason)")
        default:
            break
        }
    }
}

func printError(_ message: String) {
    FileHandle.standardError.write(Data((message + "\n").utf8))
}
