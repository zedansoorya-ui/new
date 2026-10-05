import MurmurCore
import MurmurEngines
import SwiftUI

/// Live status for the onboarding window, refreshed every second while it is open.
@MainActor
final class OnboardingModel: ObservableObject {
    @Published var microphone: PermissionState = .notDetermined
    @Published var accessibility = false
    @Published var globeAction: GlobeKeyAction = .changeInputSource
    @Published var takeOverGlobeKey: Bool
    @Published var trigger: HotkeyTrigger
    @Published var modelState: ParakeetEngine.LoadState = .notLoaded

    var onTakeOverGlobeKeyChange: ((Bool) -> Void)?
    var onRetryModel: (() -> Void)?
    var onDone: (() -> Void)?

    init(trigger: HotkeyTrigger, takeOverGlobeKey: Bool) {
        self.trigger = trigger
        self.takeOverGlobeKey = takeOverGlobeKey
        refresh()
    }

    func refresh() {
        microphone = Permissions.microphone
        accessibility = Permissions.accessibilityTrusted
        globeAction = GlobeKeySetting.currentAction()
    }

    /// The checkbox's binding: records the choice and tells the app, which re-arms the tap.
    var takeOverGlobeKeyChoice: Bool {
        get { takeOverGlobeKey }
        set {
            takeOverGlobeKey = newValue
            onTakeOverGlobeKeyChange?(newValue)
        }
    }

    var globeKeyReady: Bool {
        trigger != .globe || !globeAction.conflictsWithDictation || takeOverGlobeKey
    }

    var modelReady: Bool {
        modelState == .ready
    }
}

struct OnboardingView: View {
    @ObservedObject var model: OnboardingModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Set up Murmur")
                    .font(.title2.weight(.semibold))
                Text("Hold \(model.trigger.name), speak, release. The text lands on your clipboard.")
                    .foregroundStyle(.secondary)
            }

            StepRow(
                title: "Microphone",
                detail: "To hear you. Audio stays on this Mac.",
                done: model.microphone == .granted
            ) {
                if model.microphone == .notDetermined {
                    Button("Allow") {
                        Task {
                            _ = await Permissions.requestMicrophone()
                            model.refresh()
                        }
                    }
                } else if model.microphone == .denied {
                    Button("Open Settings") { Permissions.open(.microphone) }
                }
            }

            StepRow(
                title: "Accessibility",
                detail: "To notice the \(model.trigger.name) key from any app. Turn Murmur on in the list.",
                done: model.accessibility
            ) {
                Button("Open Settings") {
                    Permissions.promptForAccessibility()
                    Permissions.open(.accessibility)
                }
            }

            if model.trigger == .globe {
                StepRow(
                    title: "Globe key",
                    detail: globeDetail,
                    done: model.globeKeyReady
                ) {
                    VStack(alignment: .trailing, spacing: 6) {
                        if model.globeAction.conflictsWithDictation {
                            Button("Open Keyboard Settings") { Permissions.open(.keyboard) }
                        }
                        Toggle("Take over Globe key", isOn: $model.takeOverGlobeKeyChoice)
                        .toggleStyle(.checkbox)
                        .font(.caption)
                    }
                }
            }

            StepRow(
                title: "Speech model",
                detail: modelDetail,
                done: model.modelReady
            ) {
                if case .failed = model.modelState {
                    Button("Retry") { model.onRetryModel?() }
                } else if case .downloading(let fraction) = model.modelState {
                    ProgressView(value: fraction)
                        .frame(width: 120)
                }
            }

            HStack {
                Text(footer)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Done") { model.onDone?() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 520)
    }

    private var globeDetail: String {
        if !model.globeAction.conflictsWithDictation {
            return "\"Press 🌐 key to\" is set to Do Nothing. Good."
        }
        if model.takeOverGlobeKey {
            return "Murmur swallows the Globe key so \"\(model.globeAction.settingsTitle)\" does not fire."
        }
        return "Currently \"\(model.globeAction.settingsTitle)\". In Keyboard settings set \"Press 🌐 key to\" to \"Do Nothing\", or let Murmur take the key over."
    }

    private var modelDetail: String {
        switch model.modelState {
        case .notLoaded: return "Parakeet runs on the Neural Engine. About 630 MB, downloaded once."
        case .downloading(let fraction): return "Downloading… \(Int(fraction * 100))%"
        case .compiling: return "Preparing the model for the Neural Engine…"
        case .warmingUp: return "Warming up…"
        case .ready: return "Ready."
        case .failed(let reason): return "Download failed: \(reason)"
        }
    }

    private var footer: String {
        if model.microphone == .granted && model.accessibility && model.modelReady {
            return "All set. Try it now: hold \(model.trigger.name) and say a sentence."
        }
        return "Murmur keeps working in the menu bar while you finish."
    }
}

private struct StepRow<Accessory: View>: View {
    let title: String
    let detail: String
    let done: Bool
    @ViewBuilder let accessory: () -> Accessory

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: done ? "checkmark.circle.fill" : "circle")
                .font(.title3)
                .foregroundStyle(done ? Color.green : Color.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            if !done {
                accessory()
            }
        }
    }
}
