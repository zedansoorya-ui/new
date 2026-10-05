import AppKit
import SwiftUI

/// The History window: a normal, resizable window that takes focus while open.
@MainActor
final class HistoryWindowController: NSObject, NSWindowDelegate {
    let model: HistoryModel
    private var window: NSWindow?

    init(model: HistoryModel) {
        self.model = model
        super.init()
    }

    var isVisible: Bool {
        window?.isVisible ?? false
    }

    func show() {
        if window == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 860, height: 560),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.title = "Murmur History"
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: HistoryView(model: model))
            window.delegate = self
            window.center()
            window.setFrameAutosaveName("MurmurHistory")
            self.window = window
        }
        model.reload()
        NSApplication.shared.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    /// Picks up new or deleted dictations if the window is open.
    func refreshIfVisible() {
        guard isVisible else { return }
        model.reload()
    }
}
