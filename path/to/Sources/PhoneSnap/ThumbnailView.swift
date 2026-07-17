# complete code
import AppKit

class ThumbnailView: NSView {
    // MARK: - Accessibility Labels

    override func accessibilityLabel() -> String? {
        return "Thumbnail"
    }

    override func accessibilityRole() -> AccessibilityRole {
        return .image
    }

    // MARK: - Intent Exposure

    override func accessibilityElements() -> [Any] {
        var elements: [Any] = []
        if let image = image {
            elements.append(image)
        }
        return elements
    }
}