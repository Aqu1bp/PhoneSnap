import AppKit

final class StatusItemController: NSObject, NSMenuDelegate {
    private let statusItem: NSStatusItem
    private let wirelessStatus: () -> String
    private let onShowLast: () -> Void
    private let onRevealFolder: () -> Void
    private let onSetupWireless: () -> Void
    private let onCopyDevSenderConfig: () -> Void

    init(wirelessStatus: @escaping () -> String,
         onShowLast: @escaping () -> Void,
         onRevealFolder: @escaping () -> Void,
         onSetupWireless: @escaping () -> Void,
         onCopyDevSenderConfig: @escaping () -> Void) {
        self.wirelessStatus = wirelessStatus
        self.onShowLast = onShowLast
        self.onRevealFolder = onRevealFolder
        self.onSetupWireless = onSetupWireless
        self.onCopyDevSenderConfig = onCopyDevSenderConfig
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        if let button = statusItem.button {
            if let symbol = NSImage(systemSymbolName: "iphone.gen3.badge.checkmark", accessibilityDescription: "PhoneSnap") {
                symbol.isTemplate = true
                button.image = symbol
            } else {
                button.title = "PS"
            }
            button.toolTip = "PhoneSnap"
        }
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        refresh()
    }

    func refresh() {
        guard let menu = statusItem.menu else { return }
        menu.removeAllItems()

        let status = NSMenuItem(title: "Wired mode: connect a trusted iPhone", action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(status)

        let wireless = NSMenuItem(title: wirelessStatus(), action: nil, keyEquivalent: "")
        wireless.isEnabled = false
        menu.addItem(wireless)
        menu.addItem(.separator())

        let setup = NSMenuItem(title: "Set Up Wireless Shortcut...", action: #selector(setupWirelessAction), keyEquivalent: "")
        setup.target = self
        menu.addItem(setup)

        let copyDevConfig = NSMenuItem(title: "Copy Dev Sender Config", action: #selector(copyDevSenderConfigAction), keyEquivalent: "")
        copyDevConfig.target = self
        menu.addItem(copyDevConfig)

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
    @objc private func copyDevSenderConfigAction() { onCopyDevSenderConfig() }
    @objc private func showLastAction() { onShowLast() }
    @objc private func revealAction() { onRevealFolder() }
    @objc private func quitAction() { NSApp.terminate(nil) }
}
