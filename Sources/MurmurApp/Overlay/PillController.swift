import AppKit
import SwiftUI

/// A panel that can never take keyboard focus. This is load-bearing: the pill must not steal focus
/// from the text field the user is dictating into, so it is non-activating, never key, never main,
/// and only ever shown with `orderFrontRegardless()`.
final class PillPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Receives all clicks on the pill. The SwiftUI view inside is purely visual.
final class PillContainerView: NSView {
    var onClick: (() -> Void)?
    var menuProvider: (() -> NSMenu?)?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        super.hitTest(point) == nil ? nil : self
    }

    override func mouseDown(with event: NSEvent) {
        onClick?()
    }

    override func rightMouseDown(with event: NSEvent) {
        guard let menu = menuProvider?() else { return }
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }
}

/// Owns the floating pill: its panel, position and state.
@MainActor
final class PillController {
    let model: PillModel
    var onClick: (() -> Void)?
    var menuProvider: (() -> NSMenu?)?

    private let panel: PillPanel
    private let container: PillContainerView
    private var revertWorkItem: DispatchWorkItem?
    private var screenObserver: NSObjectProtocol?

    init() {
        let initial = NSRect(x: 0, y: 0, width: 44, height: 14)
        let model = PillModel()

        let panel = PillPanel(contentRect: initial, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isMovable = false
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .none

        let container = PillContainerView(frame: initial)
        let hosting = NSHostingView(rootView: PillView(model: model))
        hosting.frame = container.bounds
        hosting.autoresizingMask = [.width, .height]
        container.addSubview(hosting)
        panel.contentView = container

        self.model = model
        self.panel = panel
        self.container = container

        container.onClick = { [weak self] in self?.onClick?() }
        container.menuProvider = { [weak self] in self?.menuProvider?() }
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.layout() }
        }
    }

    var phase: PillModel.Phase {
        model.phase
    }

    func show() {
        layout()
        panel.orderFrontRegardless()
    }

    func setPhase(_ phase: PillModel.Phase) {
        revertWorkItem?.cancel()
        revertWorkItem = nil
        if case .recording = phase, !isRecording {
            model.resetLevels()
        }
        model.phase = phase
        layout()
    }

    /// Shows a transient state, then returns to idle unless something else replaced it.
    func flash(_ phase: PillModel.Phase, for seconds: TimeInterval = 1.2) {
        setPhase(phase)
        let item = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.model.phase == phase else { return }
                self.setPhase(.idle)
            }
        }
        revertWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: item)
    }

    func push(level: Float) {
        guard isRecording else { return }
        model.push(level: level)
    }

    var isRecording: Bool {
        if case .recording = model.phase { return true }
        return false
    }

    // MARK: - Layout

    private func size(for phase: PillModel.Phase) -> NSSize {
        switch phase {
        case .idle: return NSSize(width: 44, height: 14)
        case .recording(_, let label): return NSSize(width: label == nil ? 196 : 260, height: 32)
        case .processing: return NSSize(width: 148, height: 32)
        case .done: return NSSize(width: 124, height: 32)
        case .error: return NSSize(width: 300, height: 32)
        }
    }

    /// Bottom-centre of the screen that has keyboard focus, just above the Dock.
    private func layout() {
        let size = size(for: model.phase)
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let visible = screen.visibleFrame
        let origin = NSPoint(x: visible.midX - size.width / 2, y: visible.minY + 10)
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
        container.frame = NSRect(origin: .zero, size: size)
        if !panel.isVisible {
            panel.orderFrontRegardless()
        }
    }
}
