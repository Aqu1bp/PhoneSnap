# complete code
import AppKit

class ThumbnailPresenter {
    // MARK: - Accessibility Labels

    func getAccessibilityLabel(for button: NSButton) -> String {
        switch button.action {
        case #selector(copyScreenshot(_:)):
            return "Copy Screenshot"
        case #selector(saveScreenshot(_:)):
            return "Save Screenshot"
        case #selector(deleteScreenshot(_:)):
            return "Delete Screenshot"
        default:
            return ""
        }
    }

    func getAccessibilityLabel(for image: NSImage) -> String {
        return "Screenshot"
    }

    // MARK: - Intent Exposure

    func exposeCopyIntent() {
        // Expose copy intent for assistive tech
        let copyIntent = NSUserActivity(activityType: "com.apple.UIElement.copy")
        copyIntent.title = "Copy Screenshot"
        copyIntent.keywords = ["copy", "screenshot"]
        NSApp.shared().addUserActivity(copyIntent)
    }

    func exposeOpenIntent() {
        // Expose open intent for assistive tech
        let openIntent = NSUserActivity(activityType: "com.apple.UIElement.open")
        openIntent.title = "Open Screenshot"
        openIntent.keywords = ["open", "screenshot"]
        NSApp.shared().addUserActivity(openIntent)
    }
}