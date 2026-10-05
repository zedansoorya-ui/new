// Adapted from Muesli (https://github.com/Muesli-HQ/muesli),
// native/MuesliNative/Sources/MuesliNativeApp/StreamingMicRecorder.swift at 906df1c.
// MIT License, Copyright (c) 2026 Pranav Hari.
// Changes: reduced to push-to-talk capture (no file rotation or device-change recovery yet);
// keeps 16 kHz Float32 samples in memory for one-shot transcription and spools the same samples to
// disk as raw Float32 so a crash loses nothing; reuses one converter per capture so resampler state
// carries across buffers; pause stops the engine and resume restarts it into the same capture.

import AVFoundation
import Foundation
import MurmurCore

/// Push-to-talk microphone capture at 16 kHz mono Float32.
///
/// The engine runs only while capturing: macOS ties the orange microphone indicator to a running
/// input, and a permanently warm engine would claim the mic was in use when it is not.
final class MicCapture: @unchecked Sendable {
    struct Captured: Sendable {
        let samples: [Float]
        /// Raw Float32 copy of the samples on disk, until the caller deletes it.
        let spoolURL: URL?
        /// Buffers that failed to convert, if any. Non-zero means audio was lost.
        let droppedBuffers: Int
    }

    enum CaptureError: LocalizedError {
        case microphoneNotAuthorized
        case noInputDevice
        case unsupportedFormat
        case engineStartFailed(String)

        var errorDescription: String? {
            switch self {
            case .microphoneNotAuthorized: return "Microphone access is not granted."
            case .noInputDevice: return "No microphone is available."
            case .unsupportedFormat: return "The microphone's audio format is not supported."
            case .engineStartFailed(let reason): return "The microphone could not start: \(reason)"
            }
        }
    }

    static let sampleRate = Double(AudioSamples.sampleRate)
    private static let tapBufferSize: AVAudioFrameCount = 1024

    /// Serialises start and stop. AVAudioEngine calls can block while the audio daemon negotiates
    /// a route, so they never run on the main thread.
    private let control = DispatchQueue(label: "com.zedan.murmur.mic")
    private let engine = AVAudioEngine()
    private let lock = NSLock()
    /// Touched only on `control`.
    private var tapInstalled = false

    // Guarded by `lock`; touched by the tap thread.
    private var converter: AVAudioConverter?
    private var targetFormat: AVAudioFormat?
    private var samples: [Float] = []
    private var spoolHandle: FileHandle?
    private var spoolURL: URL?
    private var droppedBuffers = 0
    private var isRunning = false
    private var isPaused = false
    private var onLevel: (@Sendable (Float) -> Void)?
    private var onFirstAudio: (@Sendable () -> Void)?

    static var isAuthorized: Bool {
        AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    }

    /// Starts capturing. `onLevel` receives 0...1 display levels on the audio thread;
    /// `onFirstAudio` fires once when the first converted audio arrives.
    func start(
        spoolDirectory: URL,
        onLevel: @escaping @Sendable (Float) -> Void,
        onFirstAudio: @escaping @Sendable () -> Void
    ) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            control.async {
                do {
                    try self.startOnControlQueue(spoolDirectory: spoolDirectory, onLevel: onLevel, onFirstAudio: onFirstAudio)
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// Keeps recording for `tail` seconds (so the end of the last word is not cut off), then stops
    /// and returns everything captured. No tail while paused: nothing is being recorded.
    func stop(tail: TimeInterval) async -> Captured {
        if tail > 0, !lock.synchronized({ isPaused }) {
            try? await Task.sleep(nanoseconds: UInt64(tail * 1_000_000_000))
        }
        return await withCheckedContinuation { (continuation: CheckedContinuation<Captured, Never>) in
            control.async {
                continuation.resume(returning: self.stopOnControlQueue(keepSpool: true))
            }
        }
    }

    /// Stops listening without ending the capture. The microphone is released, so macOS's
    /// recording indicator goes out while paused.
    func pause() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            control.async {
                self.pauseOnControlQueue()
                continuation.resume()
            }
        }
    }

    /// Starts listening again; new audio is appended to the same capture.
    func resume() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            control.async {
                do {
                    try self.resumeOnControlQueue()
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// Stops and throws the audio away, including its spool file.
    func cancel() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            control.async {
                _ = self.stopOnControlQueue(keepSpool: false)
                continuation.resume()
            }
        }
    }

    static func deleteSpool(_ url: URL?) {
        guard let url else { return }
        try? FileManager.default.removeItem(at: url)
    }

    // MARK: - Control queue

    private func startOnControlQueue(
        spoolDirectory: URL,
        onLevel: @escaping @Sendable (Float) -> Void,
        onFirstAudio: @escaping @Sendable () -> Void
    ) throws {
        guard Self.isAuthorized else { throw CaptureError.microphoneNotAuthorized }
        if lock.synchronized({ isRunning }) {
            _ = stopOnControlQueue(keepSpool: false)
        }

        let input = engine.inputNode
        let hardwareFormat = input.outputFormat(forBus: 0)
        guard hardwareFormat.sampleRate > 0, hardwareFormat.channelCount > 0 else {
            throw CaptureError.noInputDevice
        }
        guard let target = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: Self.sampleRate,
            channels: 1,
            interleaved: false
        ), let converter = AVAudioConverter(from: hardwareFormat, to: target) else {
            throw CaptureError.unsupportedFormat
        }

        let url = spoolDirectory.appendingPathComponent("dictation-\(Self.timestamp())-\(UUID().uuidString.prefix(8)).f32")
        FileManager.default.createFile(atPath: url.path, contents: nil)
        let handle = try? FileHandle(forWritingTo: url)

        lock.synchronized {
            self.converter = converter
            self.targetFormat = target
            self.samples = []
            self.samples.reserveCapacity(Int(Self.sampleRate) * 30)
            self.spoolHandle = handle
            self.spoolURL = handle == nil ? nil : url
            self.droppedBuffers = 0
            self.onLevel = onLevel
            self.onFirstAudio = onFirstAudio
            self.isRunning = true
        }

        installTap(on: input)
        engine.prepare()
        do {
            try engine.start()
        } catch {
            removeTapIfInstalled()
            _ = clearState(keepSpool: false)
            throw CaptureError.engineStartFailed(error.localizedDescription)
        }
        Log.audio.info("mic started: \(hardwareFormat.sampleRate, privacy: .public) Hz, \(hardwareFormat.channelCount, privacy: .public) ch")
    }

    private func pauseOnControlQueue() {
        guard lock.synchronized({ isRunning && !isPaused }) else { return }
        removeTapIfInstalled()
        if engine.isRunning {
            engine.stop()
        }
        lock.synchronized { isPaused = true }
        Log.audio.info("mic paused")
    }

    private func resumeOnControlQueue() throws {
        guard lock.synchronized({ isRunning && isPaused }) else { return }
        // The input device may have changed while paused (AirPods connected, say), so build a
        // converter for whatever the input delivers now. Output stays 16 kHz mono.
        let input = engine.inputNode
        let hardwareFormat = input.outputFormat(forBus: 0)
        guard hardwareFormat.sampleRate > 0, hardwareFormat.channelCount > 0 else {
            throw CaptureError.noInputDevice
        }
        guard let target = lock.synchronized({ targetFormat }),
              let converter = AVAudioConverter(from: hardwareFormat, to: target) else {
            throw CaptureError.unsupportedFormat
        }
        lock.synchronized {
            self.converter = converter
            self.isPaused = false
        }
        installTap(on: input)
        engine.prepare()
        do {
            try engine.start()
        } catch {
            removeTapIfInstalled()
            lock.synchronized { isPaused = true }
            throw CaptureError.engineStartFailed(error.localizedDescription)
        }
        Log.audio.info("mic resumed: \(hardwareFormat.sampleRate, privacy: .public) Hz")
    }

    private func stopOnControlQueue(keepSpool: Bool) -> Captured {
        removeTapIfInstalled()
        if engine.isRunning {
            engine.stop()
        }
        return clearState(keepSpool: keepSpool)
    }

    private func installTap(on input: AVAudioInputNode) {
        removeTapIfInstalled()
        input.installTap(onBus: 0, bufferSize: Self.tapBufferSize, format: nil) { [weak self] buffer, _ in
            self?.process(buffer)
        }
        tapInstalled = true
    }

    private func removeTapIfInstalled() {
        guard tapInstalled else { return }
        engine.inputNode.removeTap(onBus: 0)
        tapInstalled = false
    }

    private func clearState(keepSpool: Bool) -> Captured {
        let (captured, handle, url, dropped) = lock.synchronized { () -> ([Float], FileHandle?, URL?, Int) in
            let result = (samples, spoolHandle, spoolURL, droppedBuffers)
            samples = []
            spoolHandle = nil
            spoolURL = nil
            converter = nil
            targetFormat = nil
            onLevel = nil
            onFirstAudio = nil
            isRunning = false
            isPaused = false
            return result
        }
        try? handle?.close()
        if !keepSpool {
            Self.deleteSpool(url)
        }
        return Captured(samples: captured, spoolURL: keepSpool ? url : nil, droppedBuffers: dropped)
    }

    // MARK: - Tap thread

    private func process(_ buffer: AVAudioPCMBuffer) {
        lock.lock()
        guard isRunning, !isPaused, let converter, let targetFormat, buffer.frameLength > 0 else {
            lock.unlock()
            return
        }

        let ratio = targetFormat.sampleRate / buffer.format.sampleRate
        // Ceil plus slack: a resampler's output length is not exactly frames × ratio, and an
        // undersized buffer silently truncates audio.
        let capacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up)) + 32
        guard let output = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else {
            droppedBuffers += 1
            lock.unlock()
            return
        }

        let input = OneShotInput(buffer)
        var conversionError: NSError?
        let status = converter.convert(to: output, error: &conversionError) { _, inputStatus in
            guard let next = input.take() else {
                // Not .endOfStream: the converter is reused for the whole capture and ending the
                // stream would discard its filter state at every buffer.
                inputStatus.pointee = .noDataNow
                return nil
            }
            inputStatus.pointee = .haveData
            return next
        }

        guard status != .error, conversionError == nil, let channel = output.floatChannelData?[0] else {
            droppedBuffers += 1
            lock.unlock()
            return
        }

        let count = Int(output.frameLength)
        let chunk = UnsafeBufferPointer(start: channel, count: count)
        let isFirstAudio = samples.isEmpty && count > 0
        samples.append(contentsOf: chunk)
        if let spoolHandle, count > 0 {
            try? spoolHandle.write(contentsOf: Data(buffer: chunk))
        }
        let level = LevelMeter.displayLevel(of: chunk)
        let levelHandler = onLevel
        let firstAudioHandler = isFirstAudio ? onFirstAudio : nil
        lock.unlock()

        firstAudioHandler?()
        levelHandler?(level)
    }

    /// Hands one buffer to the converter's input block. The block runs synchronously inside
    /// `convert`, on the calling thread, but newer SDKs type it as `@Sendable`, which rules out a
    /// captured `var` flag. Hence the unchecked conformance.
    private final class OneShotInput: @unchecked Sendable {
        private var buffer: AVAudioPCMBuffer?

        init(_ buffer: AVAudioPCMBuffer) {
            self.buffer = buffer
        }

        func take() -> AVAudioPCMBuffer? {
            defer { buffer = nil }
            return buffer
        }
    }

    private static func timestamp() -> String {
        let components = Calendar(identifier: .gregorian).dateComponents(in: .current, from: Date())
        return String(
            format: "%04ld%02ld%02ld-%02ld%02ld%02ld",
            components.year ?? 0, components.month ?? 0, components.day ?? 0,
            components.hour ?? 0, components.minute ?? 0, components.second ?? 0
        )
    }
}
