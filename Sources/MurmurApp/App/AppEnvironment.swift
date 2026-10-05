import AppKit
import MurmurCore
import MurmurEngines

/// Builds and wires the app's long-lived objects. Lives as long as the app.
@MainActor
final class AppEnvironment {
    let settings: Settings
    let paths: AppPaths
    let engine: ParakeetEngine
    let pill: PillController
    let dictation: DictationController
    let onboarding: OnboardingWindowController
    private let statusItem: StatusItemController
    private let mic: MicCapture

    private(set) var modelState: ParakeetEngine.LoadState = .notLoaded
    private var hotkeyTap: HotkeyTap?
    private var accessibilityTimer: Timer?

    init() {
        let settings = Settings()
        let paths = AppPaths()
        let engine = ParakeetEngine(model: settings.asrModel)
        let mic = MicCapture()
        let pill = PillController()
        let dictation = DictationController(mic: mic, engine: engine, pill: pill, paths: paths, settings: settings)
        let onboardingModel = OnboardingModel(trigger: settings.trigger, takeOverGlobeKey: settings.takeOverGlobeKey)

        self.settings = settings
        self.paths = paths
        self.engine = engine
        self.mic = mic
        self.pill = pill
        self.dictation = dictation
        self.onboarding = OnboardingWindowController(model: onboardingModel)
        self.statusItem = StatusItemController()
    }

    func start() {
        paths.ensureDirectories()
        let leftovers = paths.leftoverSpoolFiles()
        if !leftovers.isEmpty {
            // Recovery UI lands in Milestone 3; for now the audio is kept, not deleted.
            Log.app.notice("\(leftovers.count, privacy: .public) unprocessed recording(s) left in the spool folder")
        }

        dictation.modelState = { [unowned self] in self.modelState }
        pill.onClick = { [unowned self] in self.dictation.toggleHandsFree() }
        pill.menuProvider = { [unowned self] in self.statusItem.makePillMenu() }
        onboarding.model.onTakeOverGlobeKeyChange = { [unowned self] value in self.setTakeOverGlobeKey(value) }
        onboarding.model.onRetryModel = { [unowned self] in self.loadModel() }
        onboarding.model.onDone = { [unowned self] in
            self.settings.hasCompletedOnboarding = true
            self.onboarding.close()
        }
        statusItem.environment = self

        statusItem.install()
        pill.show()
        startHotkeyTap()
        loadModel()

        if !Permissions.allRequiredGranted || !settings.hasCompletedOnboarding {
            onboarding.show()
        }
        Log.app.info("Murmur started")
    }

    func stop() {
        hotkeyTap?.stop()
    }

    // MARK: - Status

    /// First line of the menu.
    var statusLine: String {
        if Permissions.microphone != .granted { return "Microphone access needed — open Setup" }
        if !Permissions.accessibilityTrusted { return "Accessibility access needed — open Setup" }
        switch modelState {
        case .ready: return "Ready — hold \(settings.trigger.name) to dictate"
        case .downloading(let fraction): return "Downloading speech model… \(Int(fraction * 100))%"
        case .compiling, .warmingUp, .notLoaded: return "Preparing speech model…"
        case .failed: return "Speech model failed to load — open Setup to retry"
        }
    }

    var hotkeyTapStatus: String {
        guard let hotkeyTap else { return "not created" }
        let state = hotkeyTap.isRunning ? "running" : "not running"
        return "\(state), trigger \(hotkeyTap.trigger.id), re-enabled \(hotkeyTap.reenables)×"
    }

    // MARK: - Settings changes

    func setTrigger(_ trigger: HotkeyTrigger) {
        settings.trigger = trigger
        hotkeyTap?.configure(trigger: trigger, takeOverGlobe: settings.takeOverGlobeKey)
        onboarding.model.trigger = trigger
        Log.hotkey.info("trigger set to \(trigger.id, privacy: .public)")
    }

    func setTakeOverGlobeKey(_ enabled: Bool) {
        settings.takeOverGlobeKey = enabled
        hotkeyTap?.configure(trigger: settings.trigger, takeOverGlobe: enabled)
        onboarding.model.takeOverGlobeKey = enabled
        Log.hotkey.info("take over Globe key: \(enabled, privacy: .public)")
    }

    // MARK: - Hotkey

    private func startHotkeyTap() {
        if hotkeyTap == nil {
            let dictation = self.dictation
            let tap = HotkeyTap(trigger: settings.trigger, takeOverGlobe: settings.takeOverGlobeKey) { event in
                DispatchQueue.main.async {
                    MainActor.assumeIsolated { dictation.handle(event) }
                }
            }
            hotkeyTap = tap
            dictation.tap = tap
        }
        guard let hotkeyTap, !hotkeyTap.isRunning else { return }
        do {
            try hotkeyTap.start()
            accessibilityTimer?.invalidate()
            accessibilityTimer = nil
            let triggerID = settings.trigger.id
            Log.hotkey.info("hotkey tap started for \(triggerID, privacy: .public)")
        } catch {
            Log.hotkey.notice("hotkey tap not started: \(error.localizedDescription, privacy: .public)")
            waitForAccessibility()
        }
    }

    /// Accessibility can be granted while Murmur runs; start the tap as soon as it is.
    private func waitForAccessibility() {
        guard accessibilityTimer == nil else { return }
        accessibilityTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [unowned self] _ in
            MainActor.assumeIsolated {
                guard Permissions.accessibilityTrusted else { return }
                self.startHotkeyTap()
            }
        }
    }

    // MARK: - Model

    func loadModel() {
        let engine = self.engine
        updateModelState(.notLoaded)
        Task {
            await engine.prepare { [unowned self] state in
                DispatchQueue.main.async { [unowned self] in
                    MainActor.assumeIsolated { self.updateModelState(state) }
                }
            }
        }
    }

    private func updateModelState(_ state: ParakeetEngine.LoadState) {
        modelState = state
        onboarding.model.modelState = state
        switch state {
        case .ready:
            let identifier = engine.identifier
            Log.asr.info("speech model ready: \(identifier, privacy: .public)")
        case .failed(let reason):
            Log.asr.error("speech model failed: \(reason, privacy: .public)")
        case .notLoaded, .downloading, .compiling, .warmingUp:
            break
        }
    }
}
