import AppKit
import CoreGraphics
import MurmurCore
import MurmurEngines
import MurmurStorage

/// Runs the push-to-talk loop: hotkey events → state machine → capture → Parakeet → clipboard, then
/// saves the result to the history.
@MainActor
final class DictationController {
    /// Set once the event tap exists, so Escape is swallowed only while capturing.
    var tap: HotkeyTap?
    /// Current speech-model state, provided by the environment.
    var modelState: () -> ParakeetEngine.LoadState = { .notLoaded }
    /// Called after a dictation is delivered and saved, or the history changed otherwise.
    var onHistoryChanged: (() -> Void)?

    /// Most recent dictations, newest last: this session's, plus the latest saved ones at launch.
    /// Feeds the menus; the History window reads the database.
    private(set) var recent: [DictationEntry] = []

    private let mic: MicCapture
    private let engine: ParakeetEngine
    private let pill: PillController
    private let paths: AppPaths
    private let settings: Settings
    private let historyStore: HistoryStore?
    private var machine = HotkeyStateMachine()
    private var session: Session?
    private var tickWorkItem: DispatchWorkItem?
    /// Pause and resume requests, chained so they reach the microphone in order.
    private var micCommands: Task<Void, Never>?

    private struct Session {
        let id: UUID
        var mode: CaptureMode
        var timeline: DictationTimeline
        let startTask: Task<Void, Error>
        /// When the press happened, for the pill's timer and the history.
        let startedAt: Date
        /// The app that had focus when the capture started.
        let appName: String?
        let appBundleID: String?
        /// True once the pill shows the recording state (after the tap threshold for holds).
        var committed: Bool
        /// Set while paused.
        var pausedAt: Date?
        var pausedTotal: TimeInterval = 0
    }

    init(
        mic: MicCapture,
        engine: ParakeetEngine,
        pill: PillController,
        paths: AppPaths,
        settings: Settings,
        historyStore: HistoryStore?
    ) {
        self.mic = mic
        self.engine = engine
        self.pill = pill
        self.paths = paths
        self.settings = settings
        self.historyStore = historyStore
        if let saved = try? historyStore?.recent(limit: 20) {
            recent = saved.reversed()
        }
    }

    var isCapturing: Bool {
        machine.isCapturing
    }

    var isPaused: Bool {
        session?.pausedAt != nil
    }

    // MARK: - Inputs

    func handle(_ event: HotkeyTap.Event) {
        let input: HotkeyInput
        switch event {
        case .trigger(.pressed, let held):
            input = .triggerDown(held: held)
        case .trigger(.released, _):
            input = .triggerUp
        case .controlDown:
            input = .controlDown
        case .otherKeyDown:
            input = .otherKeyDown
        case .escape:
            input = .escape
        }
        process(input, at: Self.now())
    }

    /// The pill's Dictate button, or "Start Hands-free Dictation" in the menu.
    func toggleHandsFree() {
        process(.pillClick, at: Self.now())
    }

    /// The pill's Done button: transcribe what has been captured so far.
    func stop() {
        process(.stop, at: Self.now())
    }

    /// The pill's Cancel button: throw the capture away.
    func cancel() {
        process(.cancel, at: Self.now())
    }

    /// Pauses or resumes the current capture. While paused the microphone is released and the
    /// timer stops; finishing transcribes everything captured before the pause.
    func togglePause() {
        guard var current = session, current.committed else { return }
        let mic = self.mic
        let startTask = current.startTask
        let id = current.id

        if let pausedAt = current.pausedAt {
            current.pausedTotal += Date().timeIntervalSince(pausedAt)
            current.pausedAt = nil
            session = current
            showRecording(current)
            Log.audio.info("dictation resumed")
            enqueueMicCommand {
                do {
                    try await mic.resume()
                } catch {
                    await MainActor.run {
                        guard self.session?.id == id else { return }
                        Log.audio.error("resume failed: \(error.localizedDescription, privacy: .public)")
                        // Keep what was captured before the pause rather than lose it.
                        self.stop()
                    }
                }
            }
        } else {
            current.pausedAt = Date()
            session = current
            showRecording(current)
            Log.audio.info("dictation paused")
            enqueueMicCommand {
                _ = try? await startTask.value
                await mic.pause()
            }
        }
    }

    private func enqueueMicCommand(_ command: @escaping @Sendable () async -> Void) {
        let previous = micCommands
        micCommands = Task {
            await previous?.value
            await command()
        }
    }

    private func process(_ input: HotkeyInput, at now: TimeInterval) {
        for effect in machine.handle(input, at: now) {
            apply(effect, at: now)
        }
        scheduleTick(now: now)
    }

    private func apply(_ effect: HotkeyEffect, at now: TimeInterval) {
        switch effect {
        case .beginCapture(let mode):
            beginCapture(mode: mode, at: now)
        case .commitHold:
            commit()
        case .switchMode(let mode):
            guard var current = session else { return }
            current.mode = mode
            current.timeline.mode = mode
            session = current
            if current.committed {
                showRecording(current)
            }
        case .finish:
            finish(at: now)
        case .discard(let reason):
            discard(reason: reason)
        }
    }

    // MARK: - Ticks

    /// Delivers `.tick` when the state machine needs one, and while a hold is in progress polls
    /// the physical key so a release the tap never delivered cannot leave the mic open.
    private func scheduleTick(now: TimeInterval) {
        tickWorkItem?.cancel()
        tickWorkItem = nil
        guard let deadline = machine.nextDeadline(now: now) else { return }
        let item = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.tick() }
        }
        tickWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + max(0.01, deadline - now), execute: item)
    }

    private func tick() {
        let now = Self.now()
        switch machine.state {
        case .pending, .holding, .command:
            // HID state reflects the hardware even when the tap swallows the Globe key.
            let flags = CGEventSource.flagsState(.hidSystemState).rawValue
            let isDown = (tap?.trigger ?? settings.trigger).isHeld(in: flags)
            for effect in machine.handle(.triggerFlag(isDown: isDown), at: now) {
                apply(effect, at: now)
            }
        case .idle, .tapWindow, .handsFree:
            break
        }
        process(.tick, at: now)
    }

    // MARK: - Capture

    private func beginCapture(mode: CaptureMode, at now: TimeInterval) {
        if let stale = session {
            cancelSession(stale)
        }

        switch modelState() {
        case .ready:
            break
        case .failed:
            refuse("Speech model failed to load. See the menu.")
            return
        case .downloading(let fraction):
            refuse("Speech model downloading… \(Int(fraction * 100))%")
            return
        case .notLoaded, .compiling, .warmingUp:
            refuse("Speech model is still loading…")
            return
        }
        guard MicCapture.isAuthorized else {
            refuse("Allow microphone access in Setup.")
            return
        }

        let id = UUID()
        let mic = self.mic
        let pill = self.pill
        let spool = paths.spool
        let startTask = Task<Void, Error> {
            try await mic.start(
                spoolDirectory: spool,
                onLevel: { level in
                    DispatchQueue.main.async {
                        MainActor.assumeIsolated { pill.push(level: level) }
                    }
                },
                onFirstAudio: { [weak self] in
                    let at = Self.now()
                    DispatchQueue.main.async { [weak self] in
                        MainActor.assumeIsolated { self?.noteFirstAudio(sessionID: id, at: at) }
                    }
                }
            )
        }
        // The pill never takes focus, so the frontmost app is still the one being dictated into.
        let frontmost = NSWorkspace.shared.frontmostApplication
        let isSelf = frontmost?.bundleIdentifier == Bundle.main.bundleIdentifier
        session = Session(
            id: id,
            mode: mode,
            timeline: DictationTimeline(mode: mode, engine: engine.identifier, pressedAt: now),
            startTask: startTask,
            startedAt: Self.date(forUptime: now),
            appName: isSelf ? nil : frontmost?.localizedName,
            appBundleID: isSelf ? nil : frontmost?.bundleIdentifier,
            committed: false
        )
        tap?.setCaptureActive(true)
        if mode != .hold {
            // Hands-free and command captures show immediately; holds wait out the tap threshold.
            commit()
        }

        Task {
            do {
                try await startTask.value
            } catch {
                guard self.session?.id == id else { return }
                Log.audio.error("mic start failed: \(error.localizedDescription, privacy: .public)")
                self.session = nil
                self.machine.reset()
                self.tap?.setCaptureActive(false)
                self.pill.flash(.error(error.localizedDescription), for: 3)
            }
        }
    }

    private func commit() {
        guard var current = session, !current.committed else { return }
        current.committed = true
        session = current
        showRecording(current)
    }

    private func showRecording(_ current: Session) {
        pill.setPhase(.recording(PillModel.Recording(
            startedAt: current.startedAt,
            label: Self.label(for: current.mode),
            pausedAt: current.pausedAt,
            pausedTotal: current.pausedTotal
        )))
    }

    private func finish(at now: TimeInterval) {
        guard var current = session else { return }
        session = nil
        tap?.setCaptureActive(false)
        current.timeline.releasedAt = now
        pill.setPhase(.processing)

        let mic = self.mic
        let engine = self.engine
        let tail = settings.releaseTail
        let startTask = current.startTask
        let pendingCommands = micCommands
        let finished = current

        Task {
            var timeline = finished.timeline
            do {
                try await startTask.value
            } catch {
                // The start failure was already reported.
                return
            }
            // A pause or resume still on its way to the microphone lands before the stop.
            await pendingCommands?.value

            let captured = await mic.stop(tail: tail)
            timeline.audioReadyAt = Self.now()
            timeline.audioSeconds = AudioSamples.duration(sampleCount: captured.samples.count)
            let dropped = captured.droppedBuffers
            if dropped > 0 {
                Log.audio.error("\(dropped, privacy: .public) audio buffers failed to convert")
            }

            guard captured.samples.count >= AudioSamples.sampleRate / 5 else {
                MicCapture.deleteSpool(captured.spoolURL)
                self.complete(.error("Too short. Hold the key while you speak."))
                return
            }

            do {
                let result = try await engine.transcribe(samples: captured.samples, sampleRate: AudioSamples.sampleRate)
                timeline.transcribedAt = Self.now()
                let text = TranscriptTidy.basic(result.text)
                guard !text.isEmpty else {
                    MicCapture.deleteSpool(captured.spoolURL)
                    self.complete(.error("Didn't catch that."))
                    return
                }
                Clipboard.copy(text)
                timeline.deliveredAt = Self.now()
                MicCapture.deleteSpool(captured.spoolURL)
                let summary = timeline.summary()
                let characters = text.count
                Log.output.info("delivered \(characters, privacy: .public) chars: \(summary, privacy: .public)")
                Log.output.debug("text: \(text, privacy: .private)")
                self.record(DictationEntry(
                    createdAt: finished.startedAt,
                    text: text,
                    mode: finished.mode,
                    engine: engine.identifier,
                    audioSeconds: timeline.audioSeconds,
                    appName: finished.appName,
                    appBundleID: finished.appBundleID,
                    timeline: timeline
                ))
                self.complete(.done("Copied"))
            } catch {
                // The spool file is kept so the audio can be recovered.
                Log.asr.error("transcription failed: \(error.localizedDescription, privacy: .public)")
                self.complete(.error("Transcription failed. Audio kept."))
            }
        }
    }

    private func discard(reason: DiscardReason) {
        guard let current = session else { return }
        session = nil
        tap?.setCaptureActive(false)
        cancelSession(current)
        switch reason {
        case .escape, .cancelled:
            pill.flash(.error("Cancelled"), for: 0.8)
        case .tap, .chord:
            if current.committed {
                pill.setPhase(.idle)
            }
        }
        Log.hotkey.info("capture discarded: \(reason.rawValue, privacy: .public)")
    }

    private func cancelSession(_ session: Session) {
        let mic = self.mic
        let startTask = session.startTask
        let pendingCommands = micCommands
        Task {
            _ = try? await startTask.value
            await pendingCommands?.value
            await mic.cancel()
        }
    }

    // MARK: - Results

    private func refuse(_ message: String) {
        machine.reset()
        pill.flash(.error(message), for: 2.5)
        Log.app.notice("dictation refused: \(message, privacy: .public)")
    }

    private func noteFirstAudio(sessionID: UUID, at time: TimeInterval) {
        guard var current = session, current.id == sessionID else { return }
        current.timeline.captureStartedAt = time
        session = current
    }

    /// Adds a delivered dictation to the menus right away and to the database in the background.
    private func record(_ entry: DictationEntry) {
        recent.append(entry)
        if recent.count > 50 {
            recent.removeFirst(recent.count - 50)
        }
        onHistoryChanged?()

        guard settings.saveHistory, let store = historyStore else { return }
        Task.detached(priority: .utility) {
            do {
                try store.add(entry)
            } catch {
                Log.app.error("could not save dictation to history: \(error.localizedDescription, privacy: .public)")
            }
            await MainActor.run { [weak self] in self?.onHistoryChanged?() }
        }
    }

    /// Forgets a dictation deleted in the History window, so the menus stop offering it.
    func forget(id: UUID) {
        recent.removeAll { $0.id == id }
    }

    /// Forgets everything after the history was cleared.
    func forgetAll() {
        recent.removeAll()
    }

    /// Shows the outcome unless a new recording has already started.
    private func complete(_ phase: PillModel.Phase) {
        guard session == nil else { return }
        pill.flash(phase, for: phase == .done("Copied") ? 1.0 : 2.5)
    }

    // MARK: - Helpers

    private nonisolated static func now() -> TimeInterval {
        ProcessInfo.processInfo.systemUptime
    }

    private static func date(forUptime uptime: TimeInterval) -> Date {
        Date().addingTimeInterval(uptime - now())
    }

    private static func label(for mode: CaptureMode) -> String? {
        switch mode {
        case .hold: return nil
        case .handsFree: return "Hands-free"
        case .command: return "Command"
        }
    }
}
