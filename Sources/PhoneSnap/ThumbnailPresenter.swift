import AppKit

@MainActor
final class ThumbnailPresenter {
    private var controllers: [ThumbnailWindowController] = []
    private(set) var lastFileURL: URL?

    func present(fileURL: URL) {
        lastFileURL = fileURL
        // Dismiss any existing thumbnails before showing the new one.
        for c in controllers { c.dismissImmediately() }
        controllers.removeAll()

        guard let image = NSImage(contentsOf: fileURL) else {
            Log.error("Could not load image at \(fileURL.path)")
            return
        }
        let controller = ThumbnailWindowController(image: image, fileURL: fileURL) { [weak self] c in
            self?.controllers.removeAll { $0 === c }
        }
        controllers.append(controller)
        controller.show()
    }

    func showLast() {
        guard let url = lastFileURL else { return }
        present(fileURL: url)
    }
}
