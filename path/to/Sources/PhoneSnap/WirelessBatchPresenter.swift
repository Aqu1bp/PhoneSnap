# complete code
import AppKit

class WirelessBatchPresenter {
    // MARK: - Accessibility Labels

    func getAccessibilityLabel(for button: NSButton) -> String {
        switch button.action {
        case #selector(copyBatch(_:)):
            return "Copy Batch"
        case #selector(saveBatch(_:)):
            return "Save Batch"
        case #selector(deleteBatch(_:)):
            return "Delete Batch"
        default:
            return ""
        }
    }

    func getAccessibilityLabel(for image: NSImage) -> String {
        return "Batch"
    }

    // MARK: - Intent Exposure

    func exposeCopyIntent() {
        // Expose copy intent for assistive tech
        let copyIntent = NSUserActivity(activityType: "com.apple.UIElement.copy")
        copyIntent.title = "Copy Batch"
        copyIntent.keywords = ["copy", "batch"]
        NSApp.shared().addUserActivity(copyIntent)
    }

    func exposeOpenIntent() {
        // Expose open intent for assistive tech
        let openIntent = NSUserActivity(activityType: "com.apple.UIElement.open")
        openIntent.title = "Open Batch"
        openIntent.keywords = ["open", "batch"]
        NSApp.shared().addUserActivity(openIntent)
    }
}