import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins

struct WirelessSetupInfo {
    let pairID: String
    let port: UInt16
    let receiverState: WirelessReceiver.State
    let hostName: String
    let lanIP: String?

    var primarySetupURL: String {
        "http://\(hostName):\(port)/pair/\(pairID)"
    }

    var fallbackSetupURL: String? {
        guard let lanIP, !lanIP.isEmpty else { return nil }
        return "http://\(lanIP):\(port)/pair/\(pairID)"
    }
}

@MainActor
final class WirelessSetupWindowController {
    private var window: NSWindow?
    private let infoProvider: () -> WirelessSetupInfo

    init(infoProvider: @escaping () -> WirelessSetupInfo) {
        self.infoProvider = infoProvider
    }

    func show() {
        if let window {
            window.contentView = makeContent()
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 620),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Set Up PhoneSnap Wireless Shortcut"
        window.isReleasedWhenClosed = false
        window.contentView = makeContent()
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = window
    }

    func refreshIfVisible() {
        guard let window, window.isVisible else { return }
        window.contentView = makeContent()
    }

    private func makeContent() -> NSView {
        let info = infoProvider()
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 440, height: 620))
        root.wantsLayer = true
        root.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        let title = NSTextField(labelWithString: "Set Up PhoneSnap")
        title.font = NSFont.systemFont(ofSize: 22, weight: .semibold)
        title.alignment = .center
        title.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(title)

        let subtitle = NSTextField(wrappingLabelWithString:
            "Scan this with your iPhone camera, then open and add the PhoneSnap Shortcut. iOS may ask for Photos and local-network permission on first run."
        )
        subtitle.font = NSFont.systemFont(ofSize: 13)
        subtitle.alignment = .center
        subtitle.textColor = .secondaryLabelColor
        subtitle.maximumNumberOfLines = 0
        subtitle.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(subtitle)

        let status = NSTextField(labelWithString: info.receiverState.menuTitle)
        status.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        status.alignment = .center
        status.textColor = info.receiverState == .ready ? .systemGreen : .secondaryLabelColor
        status.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(status)

        let qrImageView = NSImageView()
        qrImageView.imageScaling = .scaleProportionallyUpOrDown
        qrImageView.wantsLayer = true
        qrImageView.layer?.backgroundColor = NSColor.white.cgColor
        qrImageView.layer?.cornerRadius = 8
        qrImageView.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(qrImageView)
        qrImageView.image = qrImage(from: info.primarySetupURL, size: 250)

        let urlLabel = NSTextField(wrappingLabelWithString: info.primarySetupURL)
        urlLabel.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        urlLabel.alignment = .center
        urlLabel.textColor = .secondaryLabelColor
        urlLabel.maximumNumberOfLines = 0
        urlLabel.isSelectable = true
        urlLabel.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(urlLabel)

        let fallbackText = info.fallbackSetupURL.map { "Fallback LAN URL: \($0)" }
            ?? "Fallback LAN URL unavailable until this Mac has a LAN IPv4 address."
        let fallbackLabel = NSTextField(wrappingLabelWithString: fallbackText)
        fallbackLabel.font = NSFont.systemFont(ofSize: 11)
        fallbackLabel.alignment = .center
        fallbackLabel.textColor = .tertiaryLabelColor
        fallbackLabel.maximumNumberOfLines = 0
        fallbackLabel.isSelectable = true
        fallbackLabel.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(fallbackLabel)

        let copyButton = NSButton(title: "Copy Setup URL", target: self, action: #selector(copySetupURL))
        copyButton.bezelStyle = .rounded
        copyButton.translatesAutoresizingMaskIntoConstraints = false

        let openButton = NSButton(title: "Open Setup Page", target: self, action: #selector(openSetupURL))
        openButton.bezelStyle = .rounded
        openButton.translatesAutoresizingMaskIntoConstraints = false

        let buttonRow = NSStackView(views: [copyButton, openButton])
        buttonRow.orientation = .horizontal
        buttonRow.spacing = 8
        buttonRow.alignment = .centerY
        buttonRow.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(buttonRow)

        let hint = NSTextField(wrappingLabelWithString:
            "Wired USB capture remains available while this receiver runs. After setup, run the PhoneSnap Shortcut from Shortcuts, Action Button, Back Tap, Control Center, or the Home Screen."
        )
        hint.font = NSFont.systemFont(ofSize: 12)
        hint.alignment = .center
        hint.textColor = .secondaryLabelColor
        hint.maximumNumberOfLines = 0
        hint.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(hint)

        NSLayoutConstraint.activate([
            title.topAnchor.constraint(equalTo: root.topAnchor, constant: 24),
            title.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 28),
            title.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -28),

            subtitle.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 10),
            subtitle.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 32),
            subtitle.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -32),

            status.topAnchor.constraint(equalTo: subtitle.bottomAnchor, constant: 12),
            status.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 24),
            status.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -24),

            qrImageView.topAnchor.constraint(equalTo: status.bottomAnchor, constant: 18),
            qrImageView.centerXAnchor.constraint(equalTo: root.centerXAnchor),
            qrImageView.widthAnchor.constraint(equalToConstant: 250),
            qrImageView.heightAnchor.constraint(equalToConstant: 250),

            urlLabel.topAnchor.constraint(equalTo: qrImageView.bottomAnchor, constant: 16),
            urlLabel.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 24),
            urlLabel.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -24),

            fallbackLabel.topAnchor.constraint(equalTo: urlLabel.bottomAnchor, constant: 8),
            fallbackLabel.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 24),
            fallbackLabel.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -24),

            buttonRow.topAnchor.constraint(equalTo: fallbackLabel.bottomAnchor, constant: 14),
            buttonRow.centerXAnchor.constraint(equalTo: root.centerXAnchor),

            hint.topAnchor.constraint(equalTo: buttonRow.bottomAnchor, constant: 18),
            hint.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 32),
            hint.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -32),
            hint.bottomAnchor.constraint(lessThanOrEqualTo: root.bottomAnchor, constant: -24)
        ])

        return root
    }

    @objc private func copySetupURL() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(infoProvider().primarySetupURL, forType: .string)
    }

    @objc private func openSetupURL() {
        guard let url = URL(string: infoProvider().primarySetupURL) else { return }
        NSWorkspace.shared.open(url)
    }

    private func qrImage(from string: String, size: CGFloat) -> NSImage? {
        let filter = CIFilter.qrCodeGenerator()
        guard let data = string.data(using: .utf8) else { return nil }
        filter.message = data
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        let scale = size / output.extent.width
        let scaled = output.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let context = CIContext()
        guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        return NSImage(cgImage: cgImage, size: NSSize(width: size, height: size))
    }
}
