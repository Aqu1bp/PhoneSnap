import AppKit

final class StatusItemController: NSObject, NSMenuDelegate {
    private let statusItem: NSStatusItem
    private let port: UInt16
    private let onShowLast: () -> Void
    private let onRevealFolder: () -> Void
    private let onPair: () -> Void

    init(port: UInt16,
         onShowLast: @escaping () -> Void,
         onRevealFolder: @escaping () -> Void,
         onPair: @escaping () -> Void) {
        self.port = port
        self.onShowLast = onShowLast
        self.onRevealFolder = onRevealFolder
        self.onPair = onPair
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        if let button = statusItem.button {
            if let symbol = NSImage(systemSymbolName: "iphone.gen3.badge.checkmark", accessibilityDescription: "ScreenshotCatch") {
                symbol.isTemplate = true
                button.image = symbol
            } else {
                button.title = "SC"
            }
            button.toolTip = "ScreenshotCatch"
        }
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        refresh()
    }

    func refresh() {
        guard let menu = statusItem.menu else { return }
        menu.removeAllItems()
        let hostname = Host.current().localizedName ?? "mac"
        // Prefer the stable .local hostname — it survives DHCP IP changes when
        // you move between networks. Fall back to the raw IP for users on
        // networks where mDNS is blocked.
        let primaryURL = "http://\(hostname).local:\(port)/screenshot"
        let ipAddress = LANAddress.current() ?? "0.0.0.0"
        let ipURL = "http://\(ipAddress):\(port)/screenshot"

        let primary = NSMenuItem(title: primaryURL, action: nil, keyEquivalent: "")
        primary.isEnabled = false
        menu.addItem(primary)
        let ipItem = NSMenuItem(title: "or http://\(ipAddress):\(port)/screenshot", action: nil, keyEquivalent: "")
        ipItem.isEnabled = false
        menu.addItem(ipItem)
        menu.addItem(.separator())

        let pair = NSMenuItem(title: "Pair iPhone…", action: #selector(pairAction), keyEquivalent: "p")
        pair.target = self
        menu.addItem(pair)
        menu.addItem(.separator())

        let show = NSMenuItem(title: "Show Last Screenshot", action: #selector(showLastAction), keyEquivalent: "")
        show.target = self
        menu.addItem(show)

        let reveal = NSMenuItem(title: "Reveal Save Folder in Finder", action: #selector(revealAction), keyEquivalent: "")
        reveal.target = self
        menu.addItem(reveal)

        let copyHost = NSMenuItem(title: "Copy URL (\(hostname).local)", action: #selector(copyURLAction(_:)), keyEquivalent: "c")
        copyHost.target = self
        copyHost.representedObject = primaryURL
        menu.addItem(copyHost)

        let copyIP = NSMenuItem(title: "Copy URL (IP)", action: #selector(copyURLAction(_:)), keyEquivalent: "")
        copyIP.target = self
        copyIP.representedObject = ipURL
        menu.addItem(copyIP)

        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit ScreenshotCatch", action: #selector(quitAction), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
    }

    func menuWillOpen(_ menu: NSMenu) { refresh() }

    @objc private func showLastAction() { onShowLast() }
    @objc private func revealAction() { onRevealFolder() }
    @objc private func pairAction() { onPair() }
    @objc private func copyURLAction(_ sender: NSMenuItem) {
        if let str = sender.representedObject as? String {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(str, forType: .string)
        }
    }
    @objc private func quitAction() { NSApp.terminate(nil) }
}
