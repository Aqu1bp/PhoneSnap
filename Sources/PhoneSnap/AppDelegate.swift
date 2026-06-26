import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItemController: StatusItemController!
    private var presenter: ThumbnailPresenter!
    private var cameraBridge: CameraBridge!
    private var wirelessReceiver: WirelessReceiver!
    private var wirelessSetupWindow: WirelessSetupWindowController!
    private let store = ImageStore()
    private let wirelessPairing = WirelessPairing.load()
    private let wirelessPort: UInt16 = {
        ProcessInfo.processInfo.environment["PHONESNAP_WIRELESS_PORT"].flatMap(UInt16.init) ?? 8472
    }()
    private var wirelessState: WirelessReceiver.State = .stopped

    func applicationDidFinishLaunching(_ notification: Notification) {
        presenter = ThumbnailPresenter()
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
            wirelessStatus: { [weak self] in
                self?.wirelessState.menuTitle ?? WirelessReceiver.State.stopped.menuTitle
            },
            onShowLast: { [weak self] in self?.presenter.showLast() },
            onRevealFolder: { [weak self] in self?.store.revealInFinder() },
            onSetupWireless: { [weak self] in self?.wirelessSetupWindow.show() },
            onCopyDevSenderConfig: { [weak self] in self?.copyDevSenderConfig() }
        )

        wirelessReceiver = WirelessReceiver(
            port: wirelessPort,
            pairing: wirelessPairing,
            uploadHandler: { [weak self] data in
                guard let self else { return false }
                return self.deliver(data: data, source: "Wireless Shortcut")
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

        do {
            try wirelessReceiver.start()
        } catch {
            wirelessState = .failed(error.localizedDescription)
            Log.error("Wireless receiver could not start on port \(wirelessPort): \(error)")
            statusItemController.refresh()
        }

        Log.info("Starting wired iPhone screenshot watcher")
        cameraBridge.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        wirelessReceiver?.stop()
        cameraBridge?.stop()
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

    private func copyDevSenderConfig() {
        let info = wirelessSetupInfo()
        let uploadURL = "http://\(info.hostName):\(wirelessPort)/api/v1/upload/\(wirelessPairing.pairID)"
        var lines = [
            "# PhoneSnap dev sender config. Do not commit this token.",
            "PHONESNAP_UPLOAD_URL=\(uploadURL)",
            "PHONESNAP_TOKEN=\(wirelessPairing.token)"
        ]
        if let lanIP = info.lanIP {
            lines.append("PHONESNAP_UPLOAD_URL_FALLBACK=http://\(lanIP):\(wirelessPort)/api/v1/upload/\(wirelessPairing.pairID)")
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(lines.joined(separator: "\n"), forType: .string)
        Log.info("Copied dev sender config to clipboard")
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
}
