import AppKit

@MainActor
final class ThumbnailWindowController: NSObject {
    private let panel: NSPanel
    private let view: ThumbnailView
    private let onDismissed: (ThumbnailWindowController) -> Void
    private var dismissTimer: Timer?
    private static let displayDuration: TimeInterval = 8.0
    private static let maxHeight: CGFloat = 220
    private static let maxWidth: CGFloat = 340
    private static let minWidth: CGFloat = 230   // enough to fit Copy | Save | Open pill
    private static let edgeInset: CGFloat = 24

    init(image: NSImage, fileURL: URL, onDismissed: @escaping (ThumbnailWindowController) -> Void) {
        self.onDismissed = onDismissed
        let size = Self.scaledSize(for: image.size)
        let screenFrame = (NSScreen.main ?? NSScreen.screens.first!).visibleFrame
        let origin = NSPoint(
            x: screenFrame.maxX - size.width - Self.edgeInset,
            y: screenFrame.minY + Self.edgeInset
        )
        let frame = NSRect(origin: origin, size: size)
        let panel = NSPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        panel.isMovableByWindowBackground = true
        panel.hasShadow = true
        panel.backgroundColor = .clear
        panel.isOpaque = false

        let view = ThumbnailView(frame: NSRect(origin: .zero, size: size), image: image, fileURL: fileURL)
        panel.contentView = view
        self.view = view
        self.panel = panel
        super.init()

        view.onClose = { [weak self] in self?.dismissImmediately() }
        view.onCopy = { [weak self] in self?.copyToPasteboard() }
        view.onSave = { [weak self] in self?.saveAs() }
        view.onOpen = { [weak self] in self?.openInPreview() }
        view.onHoverChange = { [weak self] hovering in
            if hovering {
                self?.cancelTimer()
            } else {
                self?.scheduleDismiss()
            }
        }
        // Local key monitor so ESC closes when our panel is key.
        view.onEscape = { [weak self] in self?.dismissImmediately() }
    }

    func show() {
        panel.alphaValue = 0.0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.18
            panel.animator().alphaValue = 1.0
        })
        scheduleDismiss()
    }

    func dismissImmediately() {
        cancelTimer()
        let panel = self.panel
        let onDismissed = self.onDismissed
        let selfRef = self
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.18
            panel.animator().alphaValue = 0.0
        }, completionHandler: {
            MainActor.assumeIsolated {
                panel.orderOut(nil)
                onDismissed(selfRef)
            }
        })
    }

    private func scheduleDismiss() {
        cancelTimer()
        dismissTimer = Timer.scheduledTimer(withTimeInterval: Self.displayDuration, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.dismissImmediately() }
        }
    }
    private func cancelTimer() {
        dismissTimer?.invalidate(); dismissTimer = nil
    }

    private func copyToPasteboard() {
        Pasteboard.write(fileURL: view.fileURL)
        view.flashConfirmation("Copied")
    }

    private func saveAs() {
        let savePanel = NSSavePanel()
        savePanel.nameFieldStringValue = view.fileURL.lastPathComponent
        savePanel.allowedContentTypes = [.png]
        savePanel.canCreateDirectories = true
        cancelTimer()
        savePanel.begin { [weak self] response in
            guard let self else { return }
            if response == .OK, let dest = savePanel.url {
                do {
                    if FileManager.default.fileExists(atPath: dest.path) {
                        try FileManager.default.removeItem(at: dest)
                    }
                    try FileManager.default.copyItem(at: self.view.fileURL, to: dest)
                    self.view.flashConfirmation("Saved")
                } catch {
                    Log.error("Save copy failed: \(error)")
                }
            }
            self.scheduleDismiss()
        }
    }

    private func openInPreview() {
        NSWorkspace.shared.open(view.fileURL)
    }

    /// Size of the panel itself. For tall portrait screenshots we widen the panel
    /// (with empty side margins around the image) so the bottom action pill
    /// can render at its natural width without being clipped by the rounded
    /// view bounds. The image inside uses .resizeAspect, so it stays centered.
    private static func scaledSize(for imageSize: NSSize) -> NSSize {
        guard imageSize.width > 0, imageSize.height > 0 else {
            return NSSize(width: minWidth, height: 200)
        }
        let aspect = imageSize.width / imageSize.height
        var height = maxHeight
        var width = height * aspect
        if width > maxWidth {
            width = maxWidth
            height = width / aspect
        }
        // Enforce a minimum width to keep the action pill un-clipped.
        if width < minWidth {
            width = minWidth
        }
        return NSSize(width: ceil(width), height: ceil(height))
    }
}
