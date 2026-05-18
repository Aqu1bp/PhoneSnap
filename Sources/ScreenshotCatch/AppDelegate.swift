import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItemController: StatusItemController!
    private var presenter: ThumbnailPresenter!
    private var server: HTTPListener!
    private var cameraBridge: CameraBridge!
    private var pairingWindow: PairingWindow!
    private let store = ImageStore()

    /// Recent screenshot signatures, keyed by `(byteCount, prefix-hash)`, used
    /// to suppress double-pops when both the cable path and the LAN HTTP path
    /// deliver the same screenshot within a few seconds.
    private var recentSignatures: [(key: String, at: Date)] = []
    private let dedupeWindow: TimeInterval = 5.0
    private let dedupeLock = NSLock()

    func applicationDidFinishLaunching(_ notification: Notification) {
        let port = UInt16(ProcessInfo.processInfo.environment["SCREENSHOTCATCH_PORT"].flatMap(UInt16.init) ?? 8472)

        presenter = ThumbnailPresenter()
        pairingWindow = PairingWindow(port: port)
        statusItemController = StatusItemController(
            port: port,
            onShowLast: { [weak self] in self?.presenter.showLast() },
            onRevealFolder: { [weak self] in self?.store.revealInFinder() },
            onPair: { [weak self] in self?.pairingWindow.show() }
        )

        // Source 1: LAN HTTP server (the Shortcut-driven wireless path).
        // urlProvider gives the Shortcut generator the canonical Mac URL when
        // it needs to bake one into a `/install.shortcut` response.
        server = HTTPListener(
            port: port,
            urlProvider: {
                return "http://\(LocalHostName.mdnsHostname()):\(port)/screenshot"
            },
            handler: { [weak self] data in
                guard let self else { return false }
                return self.deliver(data: data, source: "HTTP")
            }
        )

        // Source 2: ImageCaptureCore (the cable path — zero tap when iPhone is docked).
        cameraBridge = CameraBridge { [weak self] data, name in
            guard let self else { return }
            _ = self.deliver(data: data, source: "Cable(\(name))")
        }

        do {
            try server.start()
            Log.info("Listening on http://\(LANAddress.current() ?? "0.0.0.0"):\(port)/screenshot")
            statusItemController.refresh()
        } catch {
            Log.error("Failed to start listener: \(error)")
            NSApp.terminate(nil)
        }

        cameraBridge.start()
    }

    @discardableResult
    private func deliver(data: Data, source: String) -> Bool {
        // Dedupe: if a screenshot with the same byte signature arrived in the
        // last few seconds (likely from the other transport), skip.
        if isDuplicate(data: data) {
            Log.info("Dedupe: skipping duplicate from \(source) (\(data.count) bytes)")
            return true   // tell HTTP client OK; we just don't re-pop
        }
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

    private func isDuplicate(data: Data) -> Bool {
        dedupeLock.lock(); defer { dedupeLock.unlock() }
        let now = Date()
        // Drop expired entries.
        recentSignatures.removeAll { now.timeIntervalSince($0.at) > dedupeWindow }
        let key = "\(data.count):\(data.prefix(64).hashValue)"
        if recentSignatures.contains(where: { $0.key == key }) {
            return true
        }
        recentSignatures.append((key, now))
        return false
    }
}
