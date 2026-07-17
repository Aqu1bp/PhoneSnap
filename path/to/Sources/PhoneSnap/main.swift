# complete code
import AppKit

@main
class AppDelegate: NSObject, NSApplicationDelegate {
    // MARK: - Accessibility Labels

    func application(_ application: NSApplication, didFinishLaunching: NSApplication.DidFinishLaunchingNotification) -> Bool {
        // Add accessibility labels to the menu bar
        NSApp.shared().mainMenu?.menuItems[0].accessibilityLabel = "PhoneSnap Menu"
        return true
    }

    // MARK: - Intent Exposure

    func applicationDidFinishLaunching(_ notification: Notification) {
        exposeCopyIntent()
        exposeOpenIntent()
    }
}