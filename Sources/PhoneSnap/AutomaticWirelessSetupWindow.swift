import AppKit

@MainActor
final class AutomaticWirelessSetupWindow: NSObject {
    private let watcher: AutomaticWirelessWatcher
    private let onEnabled: (PhoneDevice) -> Void
    private var window: NSWindow?
    private let picker = NSPopUpButton()
    private let status = NSTextField(wrappingLabelWithString: "")
    private let statusDot = NSView()
    private let enable = NSButton(title: "Enable Wireless", target: nil, action: nil)
    private let refreshButton = NSButton(title: "Refresh Devices", target: nil, action: nil)
    private var phones: [PhoneDevice] = []
    private var busy = false
    private var setupGeneration = UUID()
    private var currentStatus = "Not set up"
    private var currentReady = false

    init(watcher: AutomaticWirelessWatcher, onEnabled: @escaping (PhoneDevice) -> Void) {
        self.watcher = watcher
        self.onEnabled = onEnabled
        super.init()
    }

    func show() {
        if window == nil { buildWindow() }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        refreshDevices()
    }

    func updateStatus(_ text: String, ready: Bool = false) {
        currentStatus = text
        currentReady = ready
        if !busy { showStatus(text) }
    }

    func cancelPendingEnable() {
        setupGeneration = UUID()
        busy = false
        enable.isEnabled = !phones.isEmpty
        refreshButton.isEnabled = true
        picker.isEnabled = true
    }

    private func buildWindow() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 420, height: 200),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Automatic Wi-Fi Screenshots"
        window.isReleasedWhenClosed = false
        self.window = window
        let title = NSTextField(labelWithString: "Set up your iPhone")
        title.font = .systemFont(ofSize: 15, weight: .semibold)
        let instructions = NSTextField(wrappingLabelWithString: "Plug in once, tap Trust, then enable wireless and unplug.")
        instructions.font = .systemFont(ofSize: 12)
        instructions.textColor = .secondaryLabelColor
        let header = NSStackView(views: [title, instructions])
        header.orientation = .vertical
        header.alignment = .leading
        header.spacing = 4

        picker.setAccessibilityIdentifier("automatic-wireless-device")
        refreshButton.title = ""
        refreshButton.image = NSImage(systemSymbolName: "arrow.clockwise", accessibilityDescription: "Refresh Devices")
        refreshButton.imagePosition = .imageOnly
        refreshButton.toolTip = "Refresh Devices"
        refreshButton.target = self; refreshButton.action = #selector(refreshDevices)
        refreshButton.setContentHuggingPriority(.required, for: .horizontal)
        let deviceRow = NSStackView(views: [picker, refreshButton])
        deviceRow.orientation = .horizontal
        deviceRow.spacing = 8

        statusDot.wantsLayer = true
        statusDot.layer?.cornerRadius = 4
        status.font = .systemFont(ofSize: 12)
        status.setAccessibilityIdentifier("automatic-wireless-status")
        let statusRow = NSStackView(views: [statusDot, status])
        statusRow.orientation = .horizontal
        statusRow.alignment = .firstBaseline
        statusRow.spacing = 8
        showStatus(currentStatus)

        enable.target = self; enable.action = #selector(enableWireless)
        enable.keyEquivalent = "\r"
        let finder = NSButton(title: "Open Finder", target: self, action: #selector(openFinder))
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let buttons = NSStackView(views: [finder, spacer, enable])
        buttons.orientation = .horizontal

        let stack = NSStackView(views: [header, deviceRow, statusRow, buttons])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 16
        stack.setCustomSpacing(10, after: deviceRow)
        stack.setCustomSpacing(20, after: statusRow)
        stack.translatesAutoresizingMaskIntoConstraints = false
        window.contentView?.addSubview(stack)
        if let root = window.contentView {
            NSLayoutConstraint.activate([
                root.widthAnchor.constraint(equalToConstant: 420),
                stack.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 20),
                stack.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -20),
                stack.topAnchor.constraint(equalTo: root.topAnchor, constant: 20),
                stack.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -20),
                statusDot.widthAnchor.constraint(equalToConstant: 8),
                statusDot.heightAnchor.constraint(equalToConstant: 8),
                header.widthAnchor.constraint(equalTo: stack.widthAnchor),
                deviceRow.widthAnchor.constraint(equalTo: stack.widthAnchor),
                statusRow.widthAnchor.constraint(equalTo: stack.widthAnchor),
                buttons.widthAnchor.constraint(equalTo: stack.widthAnchor)
            ])
        }
        window.layoutIfNeeded()
        window.center()
    }

    private func showStatus(_ text: String, working: Bool = false, failed: Bool = false) {
        status.stringValue = text
        let color: NSColor = failed ? .systemRed : working ? .systemOrange : (currentReady ? .systemGreen : .tertiaryLabelColor)
        statusDot.layer?.backgroundColor = color.cgColor
    }

    @objc private func refreshDevices() {
        guard !busy else { return }
        busy = true; enable.isEnabled = false; refreshButton.isEnabled = false
        showStatus("Looking for your iPhone…", working: true)
        watcher.devices { [weak self] result in
            guard let self else { return }
            self.busy = false; self.refreshButton.isEnabled = true
            switch result {
            case .success(let devices):
                // One row per device. Setup through USB when both transports are advertised.
                var unique: [String: PhoneDevice] = [:]
                for device in devices where unique[device.id] == nil || device.isUSB { unique[device.id] = device }
                self.phones = unique.values.sorted { ($0.name, $0.id) < ($1.name, $1.id) }
                PhoneDevicePicker.populate(self.picker, phones: self.phones, selectedID: AutomaticWirelessSettings.phoneID)
                self.enable.isEnabled = !self.phones.isEmpty
                self.showStatus(self.phones.isEmpty ? "No iPhone found — plug it in and unlock it" : self.currentStatus)
            case .failure(let error): self.showStatus(error.localizedDescription, failed: true)
            }
        }
    }

    @objc private func enableWireless() {
        guard !busy, let phone = PhoneDevicePicker.selectedPhone(in: picker, phones: phones) else { return }
        let token = UUID()
        setupGeneration = token
        busy = true; enable.isEnabled = false; refreshButton.isEnabled = false; picker.isEnabled = false
        showStatus("Enabling wireless for \(phone.name)…", working: true)
        watcher.enableWiFi(for: phone) { [weak self] result in
            guard let self, self.setupGeneration == token else { return }
            self.busy = false; self.enable.isEnabled = true; self.refreshButton.isEnabled = true; self.picker.isEnabled = true
            switch result {
            case .success:
                self.currentStatus = phone.isUSB ? "Enabled — unplug your iPhone" : "Enabled — connecting…"
                self.showStatus(self.currentStatus)
                self.onEnabled(phone)
            case .failure(let error): self.showStatus(error.localizedDescription, failed: true)
            }
        }
    }

    @objc private func openFinder() { NSWorkspace.shared.open(FileManager.default.homeDirectoryForCurrentUser) }
}
