# complete code
import AppKit

class ThumbnailWindowController: NSWindowController {
    // MARK: - Accessibility Labels

    override func windowDidLoad() {
        super.windowDidLoad()
        window?.titleAccessibilityLabel = "Thumbnail Window"
    }

    // MARK: - Intent Exposure

    override func windowWillClose(_ notification: Notification) {
        super.windowWillClose(notification)
        exposeCopyIntent()
        exposeOpenIntent()
    }
}