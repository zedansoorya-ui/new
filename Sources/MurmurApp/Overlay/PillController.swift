import AppKit
import SwiftUI

/// A panel that can never take keyboard focus. This is load-bearing: the pill must not steal focus
/// from the text field the user is dictating into, so it is non-activating, never key, never main,
/// and only ever shown with `orderFrontRegardless()`.
final class PillPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Hosts the pill's SwiftUI view and adds what a non-activating panel of a background app needs:
/// hover tracking that works while Murmur is not the active app, buttons that respond to the
/// first click, and the right-click menu.
final class PillHostingView<Content: View>: NSHostingView<Content> {
    var onHoverChange: ((Bool) -> Void)?
    var menuProvider: (() -> NSMenu?)?
    private var hoverArea: NSTrackingArea?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverArea {
            removeTrackingArea(hoverArea)
        }
        // .activeAlways: Murmur is a background app, so the default "active app only" tracking
        // would never fire.
        let area = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        hoverArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        // SwiftUI keeps tracking areas of its own on this view; react only to ours.
        if event.trackingArea === hoverArea {
            onHoverChange?(true)
        }
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        if event.trackingArea === hoverArea {
            onHoverChange?(false)
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        if let menu = menuProvider?() {
            NSMenu.popUpContextMenu(menu, with: event, for: self)
        } else {
            super.rightMouseDown(with: event)
        }
    }
}

/// Owns the floating pill: its panel, position, hover state and transient results.
@MainActor
final class PillController {
    let model: PillModel
    var onStartDictation: (() -> Void)?
    var onTogglePause: (() -> Void)?
    var onStop: (() -> Void)?
    var onCancel: (() -> Void)?
    var onOpenHistory: (() -> Void)?
    var menuProvider: (() -> NSMenu?)?

    private let panel: PillPanel
    private let hosting: PillHostingView<PillView>
    private var revertWorkItem: DispatchWorkItem?
    private var hoverEndWorkItem: DispatchWorkItem?
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

        let hosting = PillHostingView(rootView: PillView(model: model))
        hosting.frame = NSRect(origin: .zero, size: initial.size)
        panel.contentView = hosting

        self.model = model
        self.panel = panel
        self.hosting = hosting

        hosting.onHoverChange = { [weak self] inside in self?.hoverChanged(inside) }
        hosting.menuProvider = { [weak self] in self?.menuProvider?() }
        model.onStartDictation = { [weak self] in self?.onStartDictation?() }
        model.onTogglePause = { [weak self] in self?.onTogglePause?() }
        model.onStop = { [weak self] in self?.onStop?() }
        model.onCancel = { [weak self] in self?.onCancel?() }
        model.onOpenHistory = { [weak self] in self?.onOpenHistory?() }
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

    /// Shows a transient state, then returns to idle unless something else replaced it. The result
    /// stays up while the pointer is over the pill.
    func flash(_ phase: PillModel.Phase, for seconds: TimeInterval = 1.2) {
        setPhase(phase)
        scheduleRevert(of: phase, after: seconds)
    }

    func push(level: Float) {
        guard case .recording(let recording) = model.phase, !recording.isPaused else { return }
        model.push(level: level)
    }

    var isRecording: Bool {
        if case .recording = model.phase { return true }
        return false
    }

    // MARK: - Hover

    private func hoverChanged(_ inside: Bool) {
        hoverEndWorkItem?.cancel()
        hoverEndWorkItem = nil
        if inside {
            setHovering(true)
            return
        }
        // A short grace period, so brushing past the edge does not collapse the controls.
        let item = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.setHovering(false) }
        }
        hoverEndWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: item)
    }

    private func setHovering(_ hovering: Bool) {
        guard model.isHovering != hovering else { return }
        model.isHovering = hovering
        layout()
    }

    private func scheduleRevert(of phase: PillModel.Phase, after seconds: TimeInterval) {
        revertWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.model.phase == phase else { return }
                if self.model.isHovering {
                    self.scheduleRevert(of: phase, after: 0.5)
                } else {
                    self.setPhase(.idle)
                }
            }
        }
        revertWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: item)
    }

    // MARK: - Layout

    private func size(for phase: PillModel.Phase, hovering: Bool) -> NSSize {
        switch phase {
        case .idle:
            return hovering ? NSSize(width: 196, height: 32) : NSSize(width: 44, height: 14)
        case .recording(let recording):
            if hovering { return NSSize(width: 340, height: 34) }
            if recording.isPaused { return NSSize(width: 180, height: 32) }
            return NSSize(width: recording.label == nil ? 196 : 260, height: 32)
        case .processing:
            return NSSize(width: 148, height: 32)
        case .done:
            return hovering ? NSSize(width: 220, height: 32) : NSSize(width: 124, height: 32)
        case .error:
            return NSSize(width: 300, height: 32)
        }
    }

    /// Bottom-centre of the screen that has keyboard focus, just above the Dock.
    private func layout() {
        let size = size(for: model.phase, hovering: model.isHovering)
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let visible = screen.visibleFrame
        let origin = NSPoint(x: visible.midX - size.width / 2, y: visible.minY + 10)
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
        hosting.frame = NSRect(origin: .zero, size: size)
        if !panel.isVisible {
            panel.orderFrontRegardless()
        }
    }
}
