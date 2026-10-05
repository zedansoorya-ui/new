import AppKit
import SwiftUI

/// The setup window. Unlike the pill, this is a normal window that takes focus while open.
@MainActor
final class OnboardingWindowController: NSObject, NSWindowDelegate {
    let model: OnboardingModel
    private var window: NSWindow?
    private var refreshTimer: Timer?

    init(model: OnboardingModel) {
        self.model = model
        super.init()
    }

    func show() {
        if window == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 520, height: 420),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            window.title = "Murmur"
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: OnboardingView(model: model))
            window.delegate = self
            window.center()
            self.window = window
        }
        model.refresh()
        startRefreshing()
        NSApplication.shared.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func close() {
        window?.close()
    }

    func windowWillClose(_ notification: Notification) {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    private func startRefreshing() {
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.model.refresh() }
        }
    }
}
