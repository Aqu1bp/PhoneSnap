import AppKit
import CryptoKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItemController: StatusItemController!
    private var presenter: ThumbnailPresenter!
    private var wirelessBatchPresenter: WirelessBatchPresenter!
    private var cameraBridge: CameraBridge!
    private var wirelessReceiver: WirelessReceiver!
    private var wirelessSetupWindow: WirelessSetupWindowController!
    private let store = ImageStore()
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
        wirelessBatchPresenter = WirelessBatchPresenter()
        wirelessSetupWindow = WirelessSetupWindowController(infoProvider: { [weak self] in
            self?.wirelessSetupInfo() ?? WirelessSetupInfo(
                pairID: "unavailable",
                port: 0,
                receiverState: .failed("app unavailable"),
                hostName: "localhost",
                lanIP: nil
            )
        })
        statusItemController = StatusItemController(
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
        cameraBridge = CameraBridge { [weak self] data, name in
            guard let self else { return }
            _ = self.deliver(data: data, source: "Cable(\(name))")
        }
        cameraBridge.onDevicesChanged = { [weak self] names in
            self?.statusItemController.setConnected(!names.isEmpty)
            self?.statusItemController.refresh()
        }

        if wirelessEnabled {
            startWirelessReceiver()
        } else {
            Log.info("Wireless receiver is off; no network listener started")
        }

        Log.info("Starting wired iPhone screenshot watcher")
        cameraBridge.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        wirelessReceiver?.stop()
        cameraBridge?.stop()
    }

    // MARK: wireless lifecycle

    private func makeWirelessReceiver() -> WirelessReceiver {
        WirelessReceiver(
            port: wirelessPort,
            pairing: wirelessPairing,
            batchCount: wirelessBatchCount,
            uploadHandler: { [weak self] data in
                guard let self else { return .storageFailure }
                return self.deliverWireless(data: data)
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

    @discardableResult
    private func deliver(data: Data, source: String) -> Bool {
        do {
            let url = try store.save(data: data)
            Log.info("Delivered via \(source): \(url.lastPathComponent)")
            DispatchQueue.main.async { [weak self] in
                self?.presenter.present(fileURL: url)
                Pasteboard.write(fileURL: url)
            }
            return true
        } catch {
            Log.error("Save failed (\(source)): \(error)")
            return false
        }
    }

    /// Hash → saved file for wireless uploads received this session. The
    /// Shortcut re-sends the configured recent screenshot batch on every run, so
    /// duplicates skip the disk write — but still re-surface in the panel,
    /// otherwise a second run after closing the panel shows nothing.
    private var seenWirelessUploads: [String: URL] = [:]
    private let seenWirelessUploadsLock = NSLock()

    @discardableResult
    private func deliverWireless(data: Data) -> WirelessReceiver.UploadResult {
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        seenWirelessUploadsLock.lock()
        let existing = seenWirelessUploads[digest]
        seenWirelessUploadsLock.unlock()
        if let existing {
            Log.info("Wireless upload already received this session: re-showing \(existing.lastPathComponent)")
            DispatchQueue.main.async { [weak self] in
                self?.wirelessBatchPresenter.enqueue(fileURL: existing)
            }
            return .accepted
        }
        do {
            let url = try store.save(data: data)
            seenWirelessUploadsLock.lock()
            seenWirelessUploads[digest] = url
            seenWirelessUploadsLock.unlock()
            Log.info("Delivered via Wireless Shortcut Batch: \(url.lastPathComponent)")
            DispatchQueue.main.async { [weak self] in
                self?.wirelessBatchPresenter.enqueue(fileURL: url)
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
