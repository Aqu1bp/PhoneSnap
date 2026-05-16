import AppKit

final class StatusItemController: NSObject, NSMenuDelegate {
    private let statusItem: NSStatusItem
    private let port: UInt16
    private let onShowLast: () -> Void
    private let onRevealFolder: () -> Void

    init(port: UInt16, onShowLast: @escaping () -> Void, onRevealFolder: @escaping () -> Void) {
        self.port = port
        self.onShowLast = onShowLast
        self.onRevealFolder = onRevealFolder
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
        let address = LANAddress.current() ?? "0.0.0.0"
        let urlString = "http://\(address):\(port)/screenshot"
        let urlItem = NSMenuItem(title: urlString, action: nil, keyEquivalent: "")
        urlItem.isEnabled = false
        menu.addItem(urlItem)
        let hostnameItem = NSMenuItem(title: "or http://\(Host.current().localizedName ?? "mac").local:\(port)/screenshot", action: nil, keyEquivalent: "")
        hostnameItem.isEnabled = false
        menu.addItem(hostnameItem)
        menu.addItem(.separator())

        let show = NSMenuItem(title: "Show Last Screenshot", action: #selector(showLastAction), keyEquivalent: "")
        show.target = self
        menu.addItem(show)

        let reveal = NSMenuItem(title: "Reveal Save Folder in Finder", action: #selector(revealAction), keyEquivalent: "")
        reveal.target = self
        menu.addItem(reveal)

        let copy = NSMenuItem(title: "Copy Server URL", action: #selector(copyURLAction(_:)), keyEquivalent: "c")
        copy.target = self
        copy.representedObject = urlString
        menu.addItem(copy)

        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit ScreenshotCatch", action: #selector(quitAction), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
    }

    func menuWillOpen(_ menu: NSMenu) { refresh() }

    @objc private func showLastAction() { onShowLast() }
    @objc private func revealAction() { onRevealFolder() }
    @objc private func copyURLAction(_ sender: NSMenuItem) {
        if let str = sender.representedObject as? String {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(str, forType: .string)
        }
    }
    @objc private func quitAction() { NSApp.terminate(nil) }
}
