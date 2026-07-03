import AppKit

final class StatusItemController: NSObject, NSMenuDelegate {
    private let statusItem: NSStatusItem
    private let wiredStatus: () -> String
    private let wirelessStatus: () -> String
    private let onShowLast: () -> Void
    private let onRevealFolder: () -> Void
    private let onSetupWireless: () -> Void

    init(wiredStatus: @escaping () -> String,
         wirelessStatus: @escaping () -> String,
         onShowLast: @escaping () -> Void,
         onRevealFolder: @escaping () -> Void,
         onSetupWireless: @escaping () -> Void) {
        self.wiredStatus = wiredStatus
        self.wirelessStatus = wirelessStatus
        self.onShowLast = onShowLast
        self.onRevealFolder = onRevealFolder
        self.onSetupWireless = onSetupWireless
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        setConnected(false)
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        refresh()
    }

    /// Swap the menu bar icon to reflect whether a trusted iPhone is attached.
    func setConnected(_ connected: Bool) {
        guard let button = statusItem.button else { return }
        let candidates = connected
            ? ["iphone.gen3.badge.checkmark", "iphone.badge.checkmark", "iphone"]
            : ["iphone.gen3", "iphone"]
        let symbol = candidates.lazy
            .compactMap { NSImage(systemSymbolName: $0, accessibilityDescription: "PhoneSnap") }
            .first
        if let symbol {
            symbol.isTemplate = true
            button.image = symbol
            button.title = ""
        } else {
            button.image = nil
            button.title = "📱"
        }
        button.toolTip = connected ? "PhoneSnap — iPhone connected" : "PhoneSnap — no iPhone connected"
    }

    func refresh() {
        guard let menu = statusItem.menu else { return }
        menu.removeAllItems()

        let status = NSMenuItem(title: wiredStatus(), action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(status)

        let wireless = NSMenuItem(title: wirelessStatus(), action: nil, keyEquivalent: "")
        wireless.isEnabled = false
        menu.addItem(wireless)
        menu.addItem(.separator())

        let setup = NSMenuItem(title: "Set Up Wireless Shortcut...", action: #selector(setupWirelessAction), keyEquivalent: "")
        setup.target = self
        menu.addItem(setup)

        menu.addItem(.separator())

        let show = NSMenuItem(title: "Show Last Screenshot", action: #selector(showLastAction), keyEquivalent: "")
        show.target = self
        menu.addItem(show)

        let reveal = NSMenuItem(title: "Reveal Save Folder in Finder", action: #selector(revealAction), keyEquivalent: "")
        reveal.target = self
        menu.addItem(reveal)

        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit PhoneSnap", action: #selector(quitAction), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
    }

    func menuWillOpen(_ menu: NSMenu) { refresh() }

    @objc private func setupWirelessAction() { onSetupWireless() }
    @objc private func showLastAction() { onShowLast() }
    @objc private func revealAction() { onRevealFolder() }
    @objc private func quitAction() { NSApp.terminate(nil) }
}
