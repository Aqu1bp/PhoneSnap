import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItemController: StatusItemController!
    private var presenter: ThumbnailPresenter!
    private var cameraBridge: CameraBridge!
    private let store = ImageStore()

    func applicationDidFinishLaunching(_ notification: Notification) {
        presenter = ThumbnailPresenter()
        statusItemController = StatusItemController(
            onShowLast: { [weak self] in self?.presenter.showLast() },
            onRevealFolder: { [weak self] in self?.store.revealInFinder() }
        )

        // ImageCaptureCore watches trusted USB-connected iPhones and emits
        // new camera-roll items created after app startup.
        cameraBridge = CameraBridge { [weak self] data, name in
            guard let self else { return }
            _ = self.deliver(data: data, source: "Cable(\(name))")
        }

        Log.info("Starting wired iPhone screenshot watcher")
        cameraBridge.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        cameraBridge?.stop()
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
