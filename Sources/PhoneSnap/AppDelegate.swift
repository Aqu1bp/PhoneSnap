import AppKit
import CryptoKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItemController: StatusItemController!
    private var presenter: ThumbnailPresenter!
    private var recentPresenter: RecentScreenshotsPresenter!
    private var cameraBridge: CameraBridge!
    private var wirelessReceiver: WirelessReceiver!
    private var wirelessSetupWindow: WirelessSetupWindowController!
    private var settingsWindow: SettingsWindowController!
    private let store = ImageStore()
    private let automaticWatcher = AutomaticWirelessWatcher()
    private var automaticSetup: AutomaticWirelessSetupWindow!
    private var automaticState = AutomaticWirelessWatcher.Status(text: "Off")
    private var automaticEnabled = false
    private let captureQueue = DispatchQueue(label: "phonesnap.capture-delivery", qos: .userInitiated)
    private var captureDelivery = AutomaticCaptureDelivery()
    private var lastDeliveredURL: URL?
    private var workspaceObservers: [NSObjectProtocol] = []
    /// Assigned in `applicationDidFinishLaunching`, after the enablement
    /// migration has had a chance to observe whether a pairing already
    /// existed — `WirelessPairing.load()` provisions one as a side effect.
    private var wirelessPairing: WirelessPairing!
    private var wirelessEnabled = false
    private let wirelessPort: UInt16 = {
        ProcessInfo.processInfo.environment["PHONESNAP_WIRELESS_PORT"].flatMap(UInt16.init) ?? 8472
    }()
    /// How many recent screenshots the generated Shortcut sends per run.
    /// Baked into the Shortcut at download time — changing it requires
    /// re-downloading and re-adding the Shortcut on the iPhone.
    private let wirelessBatchCount: Int = {
        let value = ProcessInfo.processInfo.environment["PHONESNAP_BATCH_COUNT"].flatMap(Int.init) ?? 10
        return min(max(value, 1), 50)
    }()
    private var wirelessState: WirelessReceiver.State = .stopped

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Order matters: the migration inspects the stored pairing, which
        // loading one would create.
        wirelessEnabled = WirelessSettings.resolveEnabled()
        wirelessPairing = WirelessPairing.load()

        presenter = ThumbnailPresenter()
        recentPresenter = RecentScreenshotsPresenter()
        wirelessSetupWindow = WirelessSetupWindowController(infoProvider: { [weak self] in
            self?.wirelessSetupInfo() ?? WirelessSetupInfo(
                pairID: "unavailable",
                port: 0,
                receiverState: .failed("app unavailable"),
                hostName: "localhost",
                lanIP: nil
            )
        })
        automaticSetup = AutomaticWirelessSetupWindow(watcher: automaticWatcher) { [weak self] phone in
            AutomaticWirelessSettings.select(phone)
            self?.setAutomaticEnabled(true)
        }
        automaticWatcher.onStatus = { [weak self] status in
            self?.automaticState = status
            self?.automaticSetup.updateStatus(status.text)
            self?.refreshConnectionStatus()
        }
        automaticWatcher.onImage = { [weak self] data, name, capturedAt, phoneID, isCurrent in
            self?.deliverAutomatic(data: data, name: name, capturedAt: capturedAt, deviceID: phoneID, wireless: true, isCurrent: isCurrent) ?? false
        }
        settingsWindow = SettingsWindowController(
            wirelessEnabled: { [weak self] in self?.wirelessEnabled ?? false },
            onToggleWireless: { [weak self] enabled in self?.setWirelessEnabled(enabled) },
            onModeChanged: { [weak self] mode in
                Log.info("Thumbnail display set to \(mode.rawValue)")
                self?.statusItemController.refresh()
            }
        )
        statusItemController = StatusItemController(
            automaticStatus: { [weak self] in self?.automaticState.text ?? "Off" },
            automaticEnabled: { [weak self] in self?.automaticEnabled ?? false },
            onToggleAutomatic: { [weak self] in self?.setAutomaticEnabled($0) },
            onSetupAutomatic: { [weak self] in self?.automaticSetup.show() },
            wiredStatus: { [weak self] in
                let names = self?.cameraBridge?.connectedDeviceNames ?? []
                if names.isEmpty {
                    return "Wired: no iPhone connected — plug in and trust this Mac"
                }
                return "Wired: connected to \(names.joined(separator: ", "))"
            },
            wirelessStatus: { [weak self] in
                guard let self else { return WirelessReceiver.State.stopped.menuTitle }
                guard self.wirelessEnabled else {
                    return "Wireless Shortcut batch receiver: off"
                }
                return self.wirelessState.menuTitle
            },
            wirelessEnabled: { [weak self] in self?.wirelessEnabled ?? false },
            onToggleWireless: { [weak self] enabled in
                self?.setWirelessEnabled(enabled)
            },
            onOpenSettings: { [weak self] in self?.settingsWindow.show() },
            onRotatePairing: { [weak self] in self?.confirmRotatePairing() },
            onShowLast: { [weak self] in self?.showLastScreenshot() },
            onRevealFolder: { [weak self] in self?.store.revealInFinder() },
            onSetupWireless: { [weak self] in
                // Setting wireless up implies wanting it to run.
                self?.setWirelessEnabled(true)
                self?.wirelessSetupWindow.show()
            }
        )

        wirelessReceiver = makeWirelessReceiver()

        // ImageCaptureCore watches trusted USB-connected iPhones and emits
        // new camera-roll items created after app startup.
        cameraBridge = CameraBridge { [weak self] data, name, capturedAt, deviceID in
            guard let self else { return }
            _ = self.deliverAutomatic(data: data, name: name, capturedAt: capturedAt, deviceID: deviceID, wireless: false, isCurrent: { true })
        }
        cameraBridge.onDevicesChanged = { [weak self] names in
            self?.refreshConnectionStatus()
        }

        if wirelessEnabled {
            startWirelessReceiver()
        } else {
            Log.info("Wireless receiver is off; no network listener started")
        }

        Log.info("Starting wired iPhone screenshot watcher")
        cameraBridge.start()
        if AutomaticWirelessSettings.enabled { setAutomaticEnabled(true) }
        let center = NSWorkspace.shared.notificationCenter
        workspaceObservers.append(center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            self?.automaticWatcher.stop()
        })
        workspaceObservers.append(center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self, self.automaticEnabled, let id = AutomaticWirelessSettings.phoneID else { return }
            self.automaticWatcher.start(phoneID: id)
        })
        if ProcessInfo.processInfo.arguments.contains("--setup-wireless") { automaticSetup.show() }
    }

    func applicationWillTerminate(_ notification: Notification) {
        automaticWatcher.stop()
        for observer in workspaceObservers { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        wirelessReceiver?.stop()
        cameraBridge?.stop()
    }

    private func refreshConnectionStatus() {
        statusItemController.setConnected(automaticState.connected || !(cameraBridge?.connectedDeviceNames.isEmpty ?? true))
        statusItemController.refresh()
    }

    @MainActor
    private func setAutomaticEnabled(_ enabled: Bool) {
        if enabled, AutomaticWirelessSettings.phoneID == nil { automaticSetup.show(); return }
        automaticEnabled = enabled
        AutomaticWirelessSettings.setEnabled(enabled)
        if enabled, let id = AutomaticWirelessSettings.phoneID {
            automaticState = .init(text: "Connecting…")
            automaticWatcher.start(phoneID: id)
        } else {
            automaticSetup.cancelPendingEnable()
            automaticWatcher.stop()
            automaticWatcher.resetCatalog()
            automaticState = .init(text: "Off")
        }
        automaticSetup.updateStatus(automaticState.text)
        refreshConnectionStatus()
    }

    /// Save once across USB/Wi-Fi, then present on main. Shortcut replays keep their own semantics.
    private func deliverAutomatic(data: Data, name: String, capturedAt: Date?, deviceID: String?, wireless: Bool, isCurrent: @escaping () -> Bool) -> Bool {
        guard isCurrent() else { return false }
        Log.info("Capture identity via \(wireless ? "Wi-Fi" : "USB"): \(AutomaticCaptureDelivery.fingerprint(deviceID))")
        var savedURL: URL?
        let accepted: Bool = captureQueue.sync {
            let key = AutomaticCaptureDelivery.key(deviceID: deviceID, name: name, capturedAt: capturedAt, data: data)
            if captureDelivery.contains(key) { return true }
            do {
                guard isCurrent() else { return false }
                let url = try store.save(data: data)
                captureDelivery.record(key)
                savedURL = url
                return true
            } catch { Log.error("Automatic screenshot save failed: \(error)"); return false }
        }
        if let url = savedURL {
            DispatchQueue.main.async { [weak self] in
                guard let self, isCurrent() else { return }
                self.lastDeliveredURL = url
                self.surface(fileURL: url, date: capturedAt ?? Date(), captureOrder: name)
                Pasteboard.write(fileURL: url)
                Log.info("Delivered via \(wireless ? "Automatic Wi-Fi" : "Cable"): \(url.lastPathComponent)")
            }
        }
        return accepted
    }

    // MARK: wireless lifecycle

    private func makeWirelessReceiver() -> WirelessReceiver {
        WirelessReceiver(
            port: wirelessPort,
            pairing: wirelessPairing,
            batchCount: wirelessBatchCount,
            uploadHandler: { [weak self] data, capturedAt in
                guard let self else { return .storageFailure }
                return self.deliverWireless(data: data, capturedAt: capturedAt)
            },
            stateHandler: { [weak self] state in
                DispatchQueue.main.async {
                    self?.wirelessState = state
                    self?.statusItemController.refresh()
                    self?.wirelessSetupWindow.refreshIfVisible()
                }
            }
        )
    }

    private func startWirelessReceiver() {
        do {
            try wirelessReceiver.start()
        } catch {
            wirelessState = .failed(error.localizedDescription)
            Log.error("Wireless receiver could not start on port \(wirelessPort): \(error)")
            statusItemController.refresh()
        }
    }

    @MainActor
    private func setWirelessEnabled(_ enabled: Bool) {
        guard enabled != wirelessEnabled else { return }
        wirelessEnabled = enabled
        WirelessSettings.setEnabled(enabled)
        if enabled {
            Log.info("Wireless receiver turned on")
            startWirelessReceiver()
        } else {
            Log.info("Wireless receiver turned off")
            wirelessReceiver.stop()
            wirelessState = .stopped
        }
        statusItemController.refresh()
        wirelessSetupWindow.refreshIfVisible()
    }

    /// Rotating invalidates every Shortcut already installed on a phone, so
    /// confirm before doing it.
    @MainActor
    private func confirmRotatePairing() {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Rotate the PhoneSnap pairing?"
        alert.informativeText = """
        A new pair ID and upload token are generated. Every PhoneSnap Shortcut \
        already added to an iPhone stops working and must be set up again from \
        the new QR code.

        Do this if you think the current setup link or token has been seen by \
        someone else.
        """
        alert.addButton(withTitle: "Rotate")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        rotatePairing()
    }

    @MainActor
    private func rotatePairing() {
        wirelessReceiver.stop()
        wirelessPairing = WirelessPairing.rotate()
        wirelessReceiver = makeWirelessReceiver()
        wirelessState = .stopped
        Log.info("Rotated the wireless pairing; previously installed Shortcuts are now rejected")
        if wirelessEnabled {
            startWirelessReceiver()
        }
        statusItemController.refresh()
        wirelessSetupWindow.refreshIfVisible()
    }

    /// Prefer the last screenshot delivered this session (wired or wireless);
    /// fall back to the newest file in the save folder so the menu item works
    /// right after launch too.
    @MainActor
    private func showLastScreenshot() {
        if let lastDeliveredURL, FileManager.default.fileExists(atPath: lastDeliveredURL.path) {
            presenter.present(fileURL: lastDeliveredURL)
            return
        }
        if presenter.lastFileURL != nil {
            presenter.showLast()
            return
        }
        if let latest = store.latestFile() {
            presenter.present(fileURL: latest)
        } else {
            Log.info("Show Last Screenshot: no screenshots in \(store.folder.path)")
        }
    }

    private func wirelessSetupInfo() -> WirelessSetupInfo {
        WirelessSetupInfo(
            pairID: wirelessPairing.pairID,
            port: wirelessPort,
            receiverState: wirelessState,
            hostName: LANAddress.bonjourHostName(),
            lanIP: LANAddress.currentIPv4()
        )
    }

    /// Single surfacing path for every capture source. Which presenter is used
    /// is the user's preference, not a property of how the screenshot arrived.
    @MainActor
    private func surface(fileURL: URL, date: Date, captureOrder: String? = nil) {
        let mode = ThumbnailSettings.mode()
        Log.info("Surfacing \(fileURL.lastPathComponent) as \(mode.rawValue)")
        switch mode {
        case .latestOnly:
            presenter.present(fileURL: fileURL)
        case .recentStrip:
            recentPresenter.enqueue(fileURL: fileURL, date: date, captureOrder: captureOrder)
        }
    }

    /// Hash → saved file for wireless uploads received this session. The
    /// Shortcut re-sends the configured recent screenshot batch on every run, so
    /// duplicates skip the disk write — but still re-surface in the panel,
    /// otherwise a second run after closing the panel shows nothing.
    private var seenWirelessUploads: [String: WirelessScreenshot] = [:]
    private let seenWirelessUploadsLock = NSLock()

    @discardableResult
    private func deliverWireless(data: Data, capturedAt: Date?) -> WirelessReceiver.UploadResult {
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        let captureDate = capturedAt ?? ScreenshotCaptureDate.fromImageData(data)
        seenWirelessUploadsLock.lock()
        var existing = seenWirelessUploads[digest]
        // Upgrade missing dates, and recognize a newer capture of identical
        // pixels without letting an older batch replay move it backwards.
        existing?.recordCaptureDate(captureDate)
        if let existing { seenWirelessUploads[digest] = existing }
        seenWirelessUploadsLock.unlock()
        if let existing {
            Log.info("Wireless upload already received this session: re-showing \(existing.fileURL.lastPathComponent)")
            DispatchQueue.main.async { [weak self] in
                self?.surface(fileURL: existing.fileURL, date: existing.sortDate)
            }
            return .accepted
        }
        do {
            let url = try store.save(data: data)
            let item = WirelessScreenshot(fileURL: url, capturedAt: captureDate, receivedAt: Date())
            seenWirelessUploadsLock.lock()
            seenWirelessUploads[digest] = item
            seenWirelessUploadsLock.unlock()
            Log.info("Delivered via Wireless Shortcut Batch: \(url.lastPathComponent)")
            DispatchQueue.main.async { [weak self] in
                self?.lastDeliveredURL = url
                self?.surface(fileURL: url, date: item.sortDate)
                Pasteboard.write(fileURL: url)
            }
            return .accepted
        } catch ImageStore.SaveError.noImage {
            Log.error("Save failed (Wireless Shortcut Batch): uploaded data is not an image")
            return .invalidImage
        } catch ImageStore.SaveError.imageTooLarge {
            Log.error("Save failed (Wireless Shortcut Batch): image dimensions exceed the safety limit")
            return .invalidImage
        } catch {
            Log.error("Save failed (Wireless Shortcut Batch): \(error)")
            return .storageFailure
        }
    }
}
