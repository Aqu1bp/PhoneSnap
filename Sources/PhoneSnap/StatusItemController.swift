import AppKit

final class StatusItemController: NSObject, NSMenuDelegate {
    private let statusItem: NSStatusItem
    private let wiredStatus: () -> String
    private let androidStatus: () -> String
    private let androidCaptureDevices: () -> [ADBDevice]
    private let wirelessStatus: () -> String
    private let onCaptureAndroid: (String) -> Void
    private let onShowLast: () -> Void
    private let onRevealFolder: () -> Void
    private let onSetupWireless: () -> Void

    init(wiredStatus: @escaping () -> String,
         androidStatus: @escaping () -> String,
         androidCaptureDevices: @escaping () -> [ADBDevice],
         wirelessStatus: @escaping () -> String,
         onCaptureAndroid: @escaping (String) -> Void,
         onShowLast: @escaping () -> Void,
         onRevealFolder: @escaping () -> Void,
         onSetupWireless: @escaping () -> Void) {
        self.wiredStatus = wiredStatus
        self.androidStatus = androidStatus
        self.androidCaptureDevices = androidCaptureDevices
        self.wirelessStatus = wirelessStatus
        self.onCaptureAndroid = onCaptureAndroid
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

    /// Swap the menu bar icon to reflect whether a capture-ready phone is attached.
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
        button.toolTip = connected ? "PhoneSnap - phone connected" : "PhoneSnap - no phone connected"
    }

    func refresh() {
        guard let menu = statusItem.menu else { return }
        menu.removeAllItems()

        let status = NSMenuItem(title: wiredStatus(), action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(status)

        let android = NSMenuItem(title: androidStatus(), action: nil, keyEquivalent: "")
        android.isEnabled = false
        menu.addItem(android)

        let wireless = NSMenuItem(title: wirelessStatus(), action: nil, keyEquivalent: "")
        wireless.isEnabled = false
        menu.addItem(wireless)
        menu.addItem(.separator())

        addAndroidCaptureItem(to: menu)

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

    private func addAndroidCaptureItem(to menu: NSMenu) {
        let devices = androidCaptureDevices()
        if devices.count == 1, let device = devices.first {
            let capture = NSMenuItem(
                title: "Capture Android Screen",
                action: #selector(captureAndroidAction(_:)),
                keyEquivalent: ""
            )
            capture.target = self
            capture.representedObject = device.serial
            capture.toolTip = "Capture the current display on \(device.displayName)"
            menu.addItem(capture)
            return
        }

        let parent = NSMenuItem(title: "Capture Android Screen", action: nil, keyEquivalent: "")
        guard !devices.isEmpty else {
            parent.isEnabled = false
            menu.addItem(parent)
            return
        }

        let submenu = NSMenu(title: "Capture Android Screen")
        for device in devices {
            let item = NSMenuItem(
                title: "\(device.displayName) (...\(device.serialSuffix))",
                action: #selector(captureAndroidAction(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = device.serial
            submenu.addItem(item)
        }
        parent.submenu = submenu
        menu.addItem(parent)
    }

    @objc private func captureAndroidAction(_ sender: NSMenuItem) {
        guard let serial = sender.representedObject as? String else { return }
        onCaptureAndroid(serial)
    }

    @objc private func setupWirelessAction() { onSetupWireless() }
    @objc private func showLastAction() { onShowLast() }
    @objc private func revealAction() { onRevealFolder() }
    @objc private func quitAction() { NSApp.terminate(nil) }
}
