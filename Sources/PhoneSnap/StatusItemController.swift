import AppKit

final class StatusItemController: NSObject, NSMenuDelegate {
    private let automaticStatus: () -> String
    private let automaticEnabled: () -> Bool
    private let onToggleAutomatic: (Bool) -> Void
    private let onSetupAutomatic: () -> Void
    private let statusItem: NSStatusItem
    private let wiredStatus: () -> String
    private let wirelessStatus: () -> String
    private let wirelessEnabled: () -> Bool
    private let onToggleWireless: (Bool) -> Void
    private let onOpenSettings: () -> Void
    private let onRotatePairing: () -> Void
    private let onShowLast: () -> Void
    private let onRevealFolder: () -> Void
    private let onSetupWireless: () -> Void

    init(automaticStatus: @escaping () -> String,
         automaticEnabled: @escaping () -> Bool,
         onToggleAutomatic: @escaping (Bool) -> Void,
         onSetupAutomatic: @escaping () -> Void,
         wiredStatus: @escaping () -> String,
         wirelessStatus: @escaping () -> String,
         wirelessEnabled: @escaping () -> Bool,
         onToggleWireless: @escaping (Bool) -> Void,
         onOpenSettings: @escaping () -> Void,
         onRotatePairing: @escaping () -> Void,
         onShowLast: @escaping () -> Void,
         onRevealFolder: @escaping () -> Void,
         onSetupWireless: @escaping () -> Void) {
        self.automaticStatus = automaticStatus
        self.automaticEnabled = automaticEnabled
        self.onToggleAutomatic = onToggleAutomatic
        self.onSetupAutomatic = onSetupAutomatic
        self.wiredStatus = wiredStatus
        self.wirelessStatus = wirelessStatus
        self.wirelessEnabled = wirelessEnabled
        self.onToggleWireless = onToggleWireless
        self.onOpenSettings = onOpenSettings
        self.onRotatePairing = onRotatePairing
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

        let automatic = NSMenuItem(title: "Wi-Fi: " + automaticStatus(), action: nil, keyEquivalent: "")
        automatic.isEnabled = false
        menu.addItem(automatic)
        menu.addItem(.separator())
        let autoToggle = NSMenuItem(title: "Automatic Wi-Fi Screenshots", action: #selector(toggleAutomaticAction), keyEquivalent: "")
        autoToggle.state = automaticEnabled() ? .on : .off
        autoToggle.target = self
        menu.addItem(autoToggle)
        let autoSetup = NSMenuItem(title: "Set Up Automatic Wi-Fi…", action: #selector(setupAutomaticAction), keyEquivalent: "")
        autoSetup.target = self
        menu.addItem(autoSetup)
        let legacyMenu = NSMenu(title: "Shortcut & Developer Uploads")
        let legacyItem = NSMenuItem(title: "Shortcut & Developer Uploads", action: nil, keyEquivalent: "")
        legacyItem.submenu = legacyMenu
        menu.addItem(legacyItem)

        let wireless = NSMenuItem(title: wirelessStatus(), action: nil, keyEquivalent: "")
        wireless.isEnabled = false
        legacyMenu.addItem(wireless)
        legacyMenu.addItem(.separator())

        let isEnabled = wirelessEnabled()
        let toggle = NSMenuItem(
            title: "Enable Shortcut Upload Receiver",
            action: #selector(toggleWirelessAction),
            keyEquivalent: ""
        )
        toggle.state = isEnabled ? .on : .off
        toggle.target = self
        toggle.toolTip = isEnabled
            ? "PhoneSnap is listening for Shortcut uploads on this network."
            : "Off — PhoneSnap opens no network listener. Wired capture is unaffected."
        legacyMenu.addItem(toggle)

        let setup = NSMenuItem(title: "Set Up Wireless Shortcut...", action: #selector(setupWirelessAction), keyEquivalent: "")
        setup.target = self
        legacyMenu.addItem(setup)

        let rotate = NSMenuItem(
            title: "Rotate Shortcut Pairing...",
            action: #selector(rotatePairingAction),
            keyEquivalent: ""
        )
        rotate.target = self
        rotate.toolTip = "Generate a new pair ID and token. Installed Shortcuts must be set up again."
        legacyMenu.addItem(rotate)

        legacyMenu.addItem(.separator())

        menu.addItem(.separator())

        let show = NSMenuItem(title: "Show Last Screenshot", action: #selector(showLastAction), keyEquivalent: "")
        show.target = self
        menu.addItem(show)

        let reveal = NSMenuItem(title: "Reveal Save Folder in Finder", action: #selector(revealAction), keyEquivalent: "")
        reveal.target = self
        menu.addItem(reveal)

        menu.addItem(.separator())
        let settings = NSMenuItem(title: "Settings...", action: #selector(settingsAction), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)

        let quit = NSMenuItem(title: "Quit PhoneSnap", action: #selector(quitAction), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
    }

    func menuWillOpen(_ menu: NSMenu) { refresh() }

    @objc private func toggleAutomaticAction() { onToggleAutomatic(!automaticEnabled()) }
    @objc private func setupAutomaticAction() { onSetupAutomatic() }
    @objc private func toggleWirelessAction() { onToggleWireless(!wirelessEnabled()) }
    @objc private func settingsAction() { onOpenSettings() }
    @objc private func rotatePairingAction() { onRotatePairing() }
    @objc private func setupWirelessAction() { onSetupWireless() }
    @objc private func showLastAction() { onShowLast() }
    @objc private func revealAction() { onRevealFolder() }
    @objc private func quitAction() { NSApp.terminate(nil) }
}
