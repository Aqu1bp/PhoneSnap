import AppKit
import CryptoKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItemController: StatusItemController!
    private var presenter: ThumbnailPresenter!
    private var wirelessBatchPresenter: WirelessBatchPresenter!
    private var cameraBridge: CameraBridge!
    private var androidBridge: AndroidADBBridge!
    private var wirelessReceiver: WirelessReceiver!
    private var wirelessSetupWindow: WirelessSetupWindowController!
    private let store = ImageStore()
    private let wirelessPairing = WirelessPairing.load()
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
    private var androidSnapshot: AndroidADBBridge.Snapshot = .stopped
    private var hasConnectedAppleDevice = false

    func applicationDidFinishLaunching(_ notification: Notification) {
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
            androidStatus: { [weak self] in
                self?.androidSnapshot.menuTitle ?? AndroidADBBridge.Snapshot.stopped.menuTitle
            },
            androidCaptureDevices: { [weak self] in
                guard let snapshot = self?.androidSnapshot,
                      snapshot.activity == .idle else { return [] }
                return snapshot.readyDevices
            },
            wirelessStatus: { [weak self] in
                self?.wirelessState.menuTitle ?? WirelessReceiver.State.stopped.menuTitle
            },
            onCaptureAndroid: { [weak self] serial in
                self?.androidBridge.capture(serial: serial)
            },
            onShowLast: { [weak self] in self?.showLastScreenshot() },
            onRevealFolder: { [weak self] in self?.store.revealInFinder() },
            onSetupWireless: { [weak self] in self?.wirelessSetupWindow.show() }
        )

        wirelessReceiver = WirelessReceiver(
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

        // ImageCaptureCore watches trusted USB-connected iPhones and emits
        // new camera-roll items created after app startup.
        cameraBridge = CameraBridge { [weak self] data, name in
            guard let self else { return }
            _ = self.deliver(data: data, source: "Cable(\(name))")
        }
        cameraBridge.onDevicesChanged = { [weak self] names in
            self?.hasConnectedAppleDevice = !names.isEmpty
            self?.refreshConnectedState()
            self?.statusItemController.refresh()
        }

        androidBridge = AndroidADBBridge(
            snapshotHandler: { [weak self] snapshot in
                DispatchQueue.main.async {
                    self?.androidSnapshot = snapshot
                    self?.refreshConnectedState()
                    self?.statusItemController.refresh()
                }
            },
            imageHandler: { [weak self] data, device in
                guard let self else { return false }
                return self.deliver(data: data, source: "Android ADB(\(device.displayName))")
            }
        )

        do {
            try wirelessReceiver.start()
        } catch {
            wirelessState = .failed(error.localizedDescription)
            Log.error("Wireless receiver could not start on port \(wirelessPort): \(error)")
            statusItemController.refresh()
        }

        Log.info("Starting wired iPhone screenshot watcher")
        cameraBridge.start()
        Log.info("Starting optional Android ADB watcher")
        androidBridge.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        wirelessReceiver?.stop()
        cameraBridge?.stop()
        androidBridge?.stop()
    }

    @MainActor
    private func refreshConnectedState() {
        statusItemController.setConnected(
            hasConnectedAppleDevice || !androidSnapshot.readyDevices.isEmpty
        )
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
