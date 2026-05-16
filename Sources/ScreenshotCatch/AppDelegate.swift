import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItemController: StatusItemController!
    private var presenter: ThumbnailPresenter!
    private var server: HTTPListener!
    private let store = ImageStore()

    func applicationDidFinishLaunching(_ notification: Notification) {
        let port = UInt16(ProcessInfo.processInfo.environment["SCREENSHOTCATCH_PORT"].flatMap(UInt16.init) ?? 8472)

        presenter = ThumbnailPresenter()
        statusItemController = StatusItemController(port: port, onShowLast: { [weak self] in
            self?.presenter.showLast()
        }, onRevealFolder: { [weak self] in
            self?.store.revealInFinder()
        })

        server = HTTPListener(port: port) { [weak self] data in
            guard let self else { return false }
            return self.handleIncoming(data: data)
        }

        do {
            try server.start()
            Log.info("Listening on http://\(LANAddress.current() ?? "0.0.0.0"):\(port)/screenshot")
            statusItemController.refresh()
        } catch {
            Log.error("Failed to start listener: \(error)")
            NSApp.terminate(nil)
        }
    }

    private func handleIncoming(data: Data) -> Bool {
        do {
            let url = try store.save(data: data)
            DispatchQueue.main.async { [weak self] in
                self?.presenter.present(fileURL: url)
                Pasteboard.write(fileURL: url)
            }
            return true
        } catch {
            Log.error("Save failed: \(error)")
            return false
        }
    }
}
