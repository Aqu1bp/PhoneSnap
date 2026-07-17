# complete code
import AppKit

class StatusItemController: NSObject {
    // MARK: - Accessibility Labels

    func statusItemAccessibilityLabel() -> String {
        return "PhoneSnap Status Item"
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