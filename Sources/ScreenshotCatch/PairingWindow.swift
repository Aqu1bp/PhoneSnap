import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins

/// Standalone window that shows a QR code containing
/// `shortcuts://import-shortcut?url=<install endpoint>&name=Send Screenshot To Mac`.
/// Scanning this from the iPhone Camera opens Safari, which redirects to
/// the Shortcuts.app import flow with the pre-built `.shortcut` file as
/// payload. End-state for the user: one scan, one tap, no typing.
@MainActor
final class PairingWindow {
    private var window: NSWindow?
    private let port: UInt16
    init(port: UInt16) {
        self.port = port
    }

    func show() {
        if let w = window {
            w.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let w = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 520),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        w.title = "Pair iPhone"
        w.isReleasedWhenClosed = false
        w.contentView = makeContent()
        w.center()
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        window = w
    }

    private func makeContent() -> NSView {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 380, height: 520))
        root.wantsLayer = true
        root.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        let title = NSTextField(labelWithString: "Set up your iPhone")
        title.font = NSFont.systemFont(ofSize: 18, weight: .semibold)
        title.alignment = .center
        title.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(title)

        let subtitle = NSTextField(wrappingLabelWithString:
            "Open Camera on iPhone, point at the code, tap the Safari notification, then tap Add Shortcut. Your Mac's URL is already baked in."
        )
        subtitle.font = NSFont.systemFont(ofSize: 12)
        subtitle.alignment = .center
        subtitle.textColor = .secondaryLabelColor
        subtitle.translatesAutoresizingMaskIntoConstraints = false
        subtitle.maximumNumberOfLines = 0
        root.addSubview(subtitle)

        let qrImageView = NSImageView()
        qrImageView.translatesAutoresizingMaskIntoConstraints = false
        qrImageView.imageScaling = .scaleProportionallyUpOrDown
        qrImageView.wantsLayer = true
        qrImageView.layer?.backgroundColor = NSColor.white.cgColor
        qrImageView.layer?.cornerRadius = 12
        root.addSubview(qrImageView)

        let urlLabel = NSTextField(wrappingLabelWithString: pairingURL())
        urlLabel.font = NSFont.monospacedSystemFont(ofSize: 10, weight: .regular)
        urlLabel.alignment = .center
        urlLabel.textColor = .secondaryLabelColor
        urlLabel.translatesAutoresizingMaskIntoConstraints = false
        urlLabel.maximumNumberOfLines = 0
        urlLabel.isSelectable = true
        root.addSubview(urlLabel)

        let copyButton = NSButton(title: "Copy Pairing URL", target: self, action: #selector(copyPressed))
        copyButton.bezelStyle = .rounded
        copyButton.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(copyButton)

        let hint = NSTextField(wrappingLabelWithString:
            "After import, bind the Shortcut to a trigger of your choice in iOS Settings (Action Button / AssistiveTouch / Back Tap). When the iPhone is plugged into your Mac, screenshots also arrive automatically without any trigger — no setup needed."
        )
        hint.font = NSFont.systemFont(ofSize: 11)
        hint.alignment = .center
        hint.textColor = .tertiaryLabelColor
        hint.translatesAutoresizingMaskIntoConstraints = false
        hint.maximumNumberOfLines = 0
        root.addSubview(hint)

        NSLayoutConstraint.activate([
            title.topAnchor.constraint(equalTo: root.topAnchor, constant: 24),
            title.centerXAnchor.constraint(equalTo: root.centerXAnchor),

            subtitle.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 8),
            subtitle.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 28),
            subtitle.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -28),

            qrImageView.topAnchor.constraint(equalTo: subtitle.bottomAnchor, constant: 18),
            qrImageView.centerXAnchor.constraint(equalTo: root.centerXAnchor),
            qrImageView.widthAnchor.constraint(equalToConstant: 240),
            qrImageView.heightAnchor.constraint(equalToConstant: 240),

            urlLabel.topAnchor.constraint(equalTo: qrImageView.bottomAnchor, constant: 14),
            urlLabel.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 20),
            urlLabel.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -20),

            copyButton.topAnchor.constraint(equalTo: urlLabel.bottomAnchor, constant: 10),
            copyButton.centerXAnchor.constraint(equalTo: root.centerXAnchor),

            hint.topAnchor.constraint(equalTo: copyButton.bottomAnchor, constant: 14),
            hint.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 28),
            hint.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -28),
            hint.bottomAnchor.constraint(lessThanOrEqualTo: root.bottomAnchor, constant: -18)
        ])

        qrImageView.image = qrImage(from: pairingURL(), size: 240)
        return root
    }

    /// The QR encodes the direct HTTP URL to a small landing page on this Mac.
    /// When the iPhone Camera scans the QR, Safari opens that page, which has
    /// a single "Install Shortcut" link to /install.shortcut. iOS Safari then
    /// recognizes the `application/x-apple-shortcut` content type and prompts
    /// to open the file in the Shortcuts app.
    ///
    /// We deliberately do NOT use `shortcuts://import-shortcut?url=…` — that
    /// URL scheme requires the source URL to be HTTPS / a real DNS name
    /// (built for iCloud-hosted Shortcuts) and rejects LAN `.local` URLs
    /// with "shortcut URL provided was invalid".
    func pairingURL() -> String {
        return "http://\(LocalHostName.mdnsHostname()):\(port)/pair"
    }

    @objc private func copyPressed() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(pairingURL(), forType: .string)
    }

    /// Produces a sharp 240×240 QR code image for the given payload.
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
