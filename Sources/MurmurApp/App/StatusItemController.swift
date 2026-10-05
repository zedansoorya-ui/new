import AppKit
import MurmurCore
import MurmurEngines

/// The menu-bar icon and its menu. Also builds the pill's right-click menu.
@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    weak var environment: AppEnvironment?
    private var statusItem: NSStatusItem?
    private let menu = NSMenu()

    func install() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "waveform", accessibilityDescription: "Murmur")
            button.image?.isTemplate = true
        }
        menu.delegate = self
        menu.autoenablesItems = false
        item.menu = menu
        statusItem = item
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        rebuild(menu)
    }

    /// Right-click menu for the pill: quick actions and the last five dictations.
    func makePillMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        guard let environment else { return menu }
        menu.addItem(makeItem(environment.dictation.isCapturing ? "Stop Dictation" : "Start Hands-free Dictation", #selector(toggleHandsFree)))
        addRecentDictations(to: menu, environment: environment)
        menu.addItem(.separator())
        menu.addItem(makeItem("Setup…", #selector(showSetup)))
        return menu
    }

    private func rebuild(_ menu: NSMenu) {
        menu.removeAllItems()
        guard let environment else { return }

        let header = NSMenuItem(title: environment.statusLine, action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(.separator())

        menu.addItem(makeItem(environment.dictation.isCapturing ? "Stop Dictation" : "Start Hands-free Dictation", #selector(toggleHandsFree)))
        let copyLast = makeItem("Copy Last Dictation", #selector(copyLast))
        copyLast.isEnabled = environment.dictation.history.last != nil
        menu.addItem(copyLast)
        addRecentDictations(to: menu, environment: environment)
        menu.addItem(.separator())

        let hotkeyMenu = NSMenu()
        hotkeyMenu.autoenablesItems = false
        for trigger in HotkeyTrigger.all {
            let item = makeItem(trigger.name, #selector(selectTrigger(_:)))
            item.representedObject = trigger.id
            item.state = environment.settings.trigger == trigger ? .on : .off
            hotkeyMenu.addItem(item)
        }
        hotkeyMenu.addItem(.separator())
        let takeOver = makeItem("Take Over Globe Key", #selector(toggleTakeOverGlobeKey))
        takeOver.state = environment.settings.takeOverGlobeKey ? .on : .off
        takeOver.isEnabled = environment.settings.trigger == .globe
        hotkeyMenu.addItem(takeOver)
        menu.addItem(makeSubmenuItem("Hotkey", hotkeyMenu))

        let modelMenu = NSMenu()
        modelMenu.autoenablesItems = false
        for model in ParakeetEngine.Model.allCases {
            let item = makeItem(model.displayName, #selector(selectModel(_:)))
            item.representedObject = model.rawValue
            item.state = environment.settings.asrModel == model ? .on : .off
            modelMenu.addItem(item)
        }
        modelMenu.addItem(.separator())
        let note = NSMenuItem(title: "Takes effect after relaunch", action: nil, keyEquivalent: "")
        note.isEnabled = false
        modelMenu.addItem(note)
        menu.addItem(makeSubmenuItem("Speech Model", modelMenu))
        menu.addItem(.separator())

        menu.addItem(makeItem("Setup…", #selector(showSetup)))
        menu.addItem(makeItem("Copy Diagnostics", #selector(copyDiagnostics)))
        menu.addItem(.separator())
        menu.addItem(makeItem("Quit Murmur", #selector(quit), key: "q"))
    }

    private func addRecentDictations(to menu: NSMenu, environment: AppEnvironment) {
        let recent = environment.dictation.history.suffix(5).reversed()
        guard !recent.isEmpty else { return }
        let recentMenu = NSMenu()
        recentMenu.autoenablesItems = false
        for record in recent {
            let item = makeItem(Self.menuTitle(for: record.text), #selector(copyRecent(_:)))
            item.representedObject = record.text
            item.toolTip = record.text
            recentMenu.addItem(item)
        }
        menu.addItem(makeSubmenuItem("Recent Dictations", recentMenu))
    }

    private func makeItem(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    private func makeSubmenuItem(_ title: String, _ submenu: NSMenu) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.submenu = submenu
        return item
    }

    private static func menuTitle(for text: String) -> String {
        let flattened = text.replacingOccurrences(of: "\n", with: " ")
        return flattened.count > 48 ? String(flattened.prefix(47)) + "…" : flattened
    }

    // MARK: - Actions

    @objc private func toggleHandsFree() {
        environment?.dictation.toggleHandsFree()
    }

    @objc private func copyLast() {
        guard let text = environment?.dictation.history.last?.text else { return }
        Clipboard.copy(text)
    }

    @objc private func copyRecent(_ sender: NSMenuItem) {
        guard let text = sender.representedObject as? String else { return }
        Clipboard.copy(text)
    }

    @objc private func selectTrigger(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String, let trigger = HotkeyTrigger.with(id: id) else { return }
        environment?.setTrigger(trigger)
    }

    @objc private func toggleTakeOverGlobeKey() {
        guard let environment else { return }
        environment.setTakeOverGlobeKey(!environment.settings.takeOverGlobeKey)
    }

    @objc private func selectModel(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let model = ParakeetEngine.Model(rawValue: raw) else { return }
        environment?.settings.asrModel = model
    }

    @objc private func showSetup() {
        environment?.onboarding.show()
    }

    @objc private func copyDiagnostics() {
        guard let environment else { return }
        Diagnostics.copyReport(for: environment)
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }
}
