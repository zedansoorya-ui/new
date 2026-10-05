import AppKit
import ApplicationServices
import AVFoundation

enum PermissionState: Equatable {
    case granted
    case denied
    case notDetermined
}

/// Status checks and requests for the permissions Milestone 2 needs. System Audio Recording,
/// Calendar and Notifications join in Milestone 5.
@MainActor
enum Permissions {
    static var microphone: PermissionState {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: return .granted
        case .notDetermined: return .notDetermined
        default: return .denied
        }
    }

    static func requestMicrophone() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .audio)
    }

    /// Needed for the keyboard event tap (and, from Milestone 4, for pasting).
    static var accessibilityTrusted: Bool {
        AXIsProcessTrusted()
    }

    /// Shows the system prompt that offers to open the Accessibility pane.
    static func promptForAccessibility() {
        // The literal key, rather than kAXTrustedCheckOptionPrompt, which Swift 6 treats as
        // shared mutable state.
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    static var allRequiredGranted: Bool {
        microphone == .granted && accessibilityTrusted
    }

    static func open(_ pane: SettingsPane) {
        guard let url = URL(string: pane.urlString) else { return }
        NSWorkspace.shared.open(url)
    }
}

enum SettingsPane {
    case microphone
    case accessibility
    case keyboard

    var urlString: String {
        switch self {
        case .microphone: return "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"
        case .accessibility: return "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        case .keyboard: return "x-apple.systempreferences:com.apple.Keyboard-Settings.extension"
        }
    }
}
