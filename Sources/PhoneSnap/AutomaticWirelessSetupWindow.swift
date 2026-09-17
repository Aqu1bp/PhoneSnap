import AppKit

@MainActor
final class AutomaticWirelessSetupWindow: NSObject {
    private let watcher: AutomaticWirelessWatcher
    private let onEnabled: (PhoneDevice) -> Void
    private var window: NSWindow?
    private let picker = NSPopUpButton()
    private let status = NSTextField(wrappingLabelWithString: "")
    private let enable = NSButton(title: "Enable Wireless", target: nil, action: nil)
    private let refreshButton = NSButton(title: "Refresh Devices", target: nil, action: nil)
    private var phones: [PhoneDevice] = []
    private var busy = false
    private var setupGeneration = UUID()
    private var currentStatus = "Connect once by cable, unlock your iPhone, and trust this Mac."

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

    func updateStatus(_ text: String) {
        currentStatus = text
        if !busy { status.stringValue = text }
    }

    func cancelPendingEnable() {
        setupGeneration = UUID()
        busy = false
        enable.isEnabled = !phones.isEmpty
        refreshButton.isEnabled = true
        picker.isEnabled = true
    }

    private func buildWindow() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 540, height: 400),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Automatic Wi-Fi Screenshots"
        window.isReleasedWhenClosed = false
        window.center()
        self.window = window
        let title = NSTextField(labelWithString: "Take a screenshot. It appears on your Mac.")
        title.font = .systemFont(ofSize: 20, weight: .semibold)
        let instructions = NSTextField(wrappingLabelWithString: "1. Plug your iPhone into this Mac once.\n2. Open Finder, select your iPhone, and approve Trust on both devices.\n3. Select the iPhone below and enable wireless access. Then unplug.")
        instructions.font = .systemFont(ofSize: 14)
        let note = NSTextField(wrappingLabelWithString: "Keep PhoneSnap running and both devices on the same Wi-Fi. Once the status says Ready, save screenshots normally. No Shortcut or iPhone app is needed.")
        note.textColor = .secondaryLabelColor
        note.font = .systemFont(ofSize: 12)
        status.font = .systemFont(ofSize: 13, weight: .medium)
        status.stringValue = currentStatus
        status.setAccessibilityIdentifier("automatic-wireless-status")
        picker.setAccessibilityIdentifier("automatic-wireless-device")
        enable.target = self; enable.action = #selector(enableWireless)
        refreshButton.target = self; refreshButton.action = #selector(refreshDevices)
        let finder = NSButton(title: "Open Finder", target: self, action: #selector(openFinder))
        let buttons = NSStackView(views: [enable, refreshButton, finder])
        buttons.orientation = .horizontal
        buttons.spacing = 10
        let stack = NSStackView(views: [title, instructions, picker, buttons, status, note])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 18
        stack.translatesAutoresizingMaskIntoConstraints = false
        window.contentView?.addSubview(stack)
        if let root = window.contentView {
            NSLayoutConstraint.activate([
                stack.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 24),
                stack.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -24),
                stack.topAnchor.constraint(equalTo: root.topAnchor, constant: 24),
                instructions.widthAnchor.constraint(equalTo: stack.widthAnchor),
                status.widthAnchor.constraint(equalTo: stack.widthAnchor),
                note.widthAnchor.constraint(equalTo: stack.widthAnchor),
                picker.widthAnchor.constraint(equalTo: stack.widthAnchor)
            ])
        }
    }

    @objc private func refreshDevices() {
        guard !busy else { return }
        busy = true; enable.isEnabled = false; refreshButton.isEnabled = false
        status.stringValue = "Looking for your iPhone…"
        watcher.devices { [weak self] result in
            guard let self else { return }
            self.busy = false; self.refreshButton.isEnabled = true
            switch result {
            case .success(let devices):
                // One row per device. Setup through USB when both transports are advertised.
                var unique: [String: PhoneDevice] = [:]
                for device in devices where unique[device.id] == nil || device.isUSB { unique[device.id] = device }
                self.phones = unique.values.sorted { ($0.name, $0.id) < ($1.name, $1.id) }
                self.picker.removeAllItems()
                for phone in self.phones { self.picker.addItem(withTitle: "\(phone.name) — \(phone.isUSB ? "Cable" : "Wi-Fi")") }
                if let selected = self.phones.firstIndex(where: { $0.id == AutomaticWirelessSettings.phoneID }) {
                    self.picker.selectItem(at: selected)
                }
                self.enable.isEnabled = !self.phones.isEmpty
                self.status.stringValue = self.phones.isEmpty ? "No iPhone found. Connect by cable, unlock it, and approve Trust in Finder." : self.currentStatus
            case .failure(let error): self.status.stringValue = error.localizedDescription
            }
        }
    }

    @objc private func enableWireless() {
        guard !busy, phones.indices.contains(picker.indexOfSelectedItem) else { return }
        let phone = phones[picker.indexOfSelectedItem]
        let token = UUID()
        setupGeneration = token
        busy = true; enable.isEnabled = false; refreshButton.isEnabled = false; picker.isEnabled = false
        status.stringValue = "Enabling wireless access for \(phone.name)…"
        watcher.enableWiFi(for: phone) { [weak self] result in
            guard let self, self.setupGeneration == token else { return }
            self.busy = false; self.enable.isEnabled = true; self.refreshButton.isEnabled = true; self.picker.isEnabled = true
            switch result {
            case .success:
                self.currentStatus = phone.isUSB ? "Wireless access enabled. Unplug your iPhone and wait for Ready." : "Wireless access enabled. Connecting…"
                self.status.stringValue = self.currentStatus
                self.onEnabled(phone)
            case .failure(let error): self.status.stringValue = error.localizedDescription
            }
        }
    }

    @objc private func openFinder() { NSWorkspace.shared.open(FileManager.default.homeDirectoryForCurrentUser) }
}
