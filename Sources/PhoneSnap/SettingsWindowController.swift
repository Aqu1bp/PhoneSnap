import AppKit

@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private let window: NSWindow
    private let latestOnlyButton = NSButton(radioButtonWithTitle: ThumbnailMode.latestOnly.title, target: nil, action: nil)
    private let recentStripButton = NSButton(radioButtonWithTitle: ThumbnailMode.recentStrip.title, target: nil, action: nil)
    private let wirelessButton = NSButton(checkboxWithTitle: "Enable the wireless receiver", target: nil, action: nil)
    private let wirelessNote = NSTextField(wrappingLabelWithString: "")

    private let wirelessEnabled: () -> Bool
    private let onToggleWireless: (Bool) -> Void
    private let onModeChanged: (ThumbnailMode) -> Void

    init(wirelessEnabled: @escaping () -> Bool,
         onToggleWireless: @escaping (Bool) -> Void,
         onModeChanged: @escaping (ThumbnailMode) -> Void) {
        self.wirelessEnabled = wirelessEnabled
        self.onToggleWireless = onToggleWireless
        self.onModeChanged = onModeChanged
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 250),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        super.init()

        window.title = "PhoneSnap Settings"
        window.isReleasedWhenClosed = false
        window.delegate = self

        let screenshotsHeader = NSTextField(labelWithString: "Screenshots")
        screenshotsHeader.font = .systemFont(ofSize: 13, weight: .semibold)

        let modeNote = NSTextField(wrappingLabelWithString:
            "Applies to both wired and wireless capture.")
        modeNote.font = .systemFont(ofSize: 11)
        modeNote.textColor = .secondaryLabelColor

        let wirelessHeader = NSTextField(labelWithString: "Wireless")
        wirelessHeader.font = .systemFont(ofSize: 13, weight: .semibold)

        wirelessNote.font = .systemFont(ofSize: 11)
        wirelessNote.textColor = .secondaryLabelColor

        for button in [latestOnlyButton, recentStripButton] {
            button.target = self
            button.action = #selector(modeChanged(_:))
        }
        wirelessButton.target = self
        wirelessButton.action = #selector(wirelessChanged(_:))

        let separator = NSBox.separator()
        let stack = NSStackView(views: [
            screenshotsHeader,
            recentStripButton,
            latestOnlyButton,
            modeNote,
            separator,
            wirelessHeader,
            wirelessButton,
            wirelessNote
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.setCustomSpacing(14, after: modeNote)
        stack.setCustomSpacing(14, after: separator)
        stack.translatesAutoresizingMaskIntoConstraints = false

        let content = NSView()
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 20)
        ])
        window.contentView = content
    }

    func show() {
        refresh()
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func refresh() {
        let mode = ThumbnailSettings.mode()
        latestOnlyButton.state = mode == .latestOnly ? .on : .off
        recentStripButton.state = mode == .recentStrip ? .on : .off
        let on = wirelessEnabled()
        wirelessButton.state = on ? .on : .off
        wirelessNote.stringValue = on
            ? "PhoneSnap is listening for Shortcut uploads on this network."
            : "Off — PhoneSnap opens no network listener. Wired capture is unaffected."
    }

    @objc private func modeChanged(_ sender: NSButton) {
        let mode: ThumbnailMode = sender === latestOnlyButton ? .latestOnly : .recentStrip
        ThumbnailSettings.setMode(mode)
        onModeChanged(mode)
        refresh()
    }

    @objc private func wirelessChanged(_ sender: NSButton) {
        onToggleWireless(sender.state == .on)
        refresh()
    }
}

private extension NSBox {
    static func separator() -> NSBox {
        let box = NSBox()
        box.boxType = .separator
        return box
    }
}
