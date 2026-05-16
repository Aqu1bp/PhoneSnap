import AppKit

@MainActor
final class ThumbnailWindowController: NSObject {
    private let panel: NSPanel
    private let view: ThumbnailView
    private let onDismissed: (ThumbnailWindowController) -> Void
    private var dismissTimer: Timer?
    private static let displayDuration: TimeInterval = 8.0
    private static let imageMaxHeight: CGFloat = 220
    private static let imageMaxWidth: CGFloat = 340
    private static let barHeight: CGFloat = 34
    private static let edgeInset: CGFloat = 16

    init(image: NSImage, fileURL: URL, onDismissed: @escaping (ThumbnailWindowController) -> Void) {
        self.onDismissed = onDismissed
        let imageSize = Self.scaledImageSize(for: image.size)
        let panelSize = NSSize(width: imageSize.width, height: imageSize.height + Self.barHeight)
        let frame = Self.bottomRightFrame(panelSize: panelSize)
        // NOTE: do NOT include `.utilityWindow` in the style mask — that style
        // silently enforces a ~180pt minimum width and pushes narrow portrait
        // thumbnails off the right edge of the screen. `.borderless` +
        // `.nonactivatingPanel` is all we need for a floating, focus-stealing-
        // free thumbnail. We also clear minSize/maxSize and re-clamp the frame
        // after `setFrame` to defend against any future AppKit silent resizes.
        let panel = NSPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.minSize = .zero
        panel.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude,
                               height: CGFloat.greatestFiniteMagnitude)
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        panel.isMovableByWindowBackground = true
        panel.hasShadow = true
        panel.backgroundColor = .clear
        panel.isOpaque = false

        let view = ThumbnailView(frame: NSRect(origin: .zero, size: panelSize), image: image, fileURL: fileURL, barHeight: Self.barHeight)
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
        // Re-anchor right before showing, in case the screens or cursor moved
        // between init and show. After setFrame, verify AppKit didn't silently
        // enlarge the window (some style masks do) and re-clamp to fit the
        // current screen's visibleFrame if so.
        let target = Self.bottomRightFrame(panelSize: panel.frame.size)
        panel.setFrame(target, display: false)
        if panel.frame != target {
            Log.info("AppKit adjusted frame to \(panel.frame); re-clamping")
            let clamped = Self.clampInsideScreen(of: panel.frame)
            panel.setFrame(clamped, display: false)
        }
        panel.alphaValue = 0.0
        panel.orderFrontRegardless()
        Log.info("show(): final panel frame=\(panel.frame)")
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.18
            panel.animator().alphaValue = 1.0
        })
        scheduleDismiss()
    }

    private static func clampInsideScreen(of frame: NSRect) -> NSRect {
        let mouseLocation = NSEvent.mouseLocation
        let screen: NSScreen = NSScreen.screens.first(where: {
            $0.frame.contains(mouseLocation)
        }) ?? NSScreen.main ?? NSScreen.screens.first!
        let vf = screen.visibleFrame
        var f = frame
        // Trim size if window is bigger than the visible area minus margins.
        f.size.width = min(f.size.width, vf.width - 2 * edgeInset)
        f.size.height = min(f.size.height, vf.height - 2 * edgeInset)
        // Re-anchor bottom-right.
        f.origin.x = max(vf.minX + edgeInset, min(vf.maxX - f.size.width - edgeInset, f.origin.x))
        f.origin.y = max(vf.minY + edgeInset, min(vf.maxY - f.size.height - edgeInset, f.origin.y))
        return f
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

    /// Anchor the panel to the bottom-right of whichever screen the mouse
    /// pointer is currently on (or main screen as a fallback). Clamp to
    /// `visibleFrame` so menu bar, Dock, notch, and external monitors can
    /// never cause it to spill off the visible area.
    private static func bottomRightFrame(panelSize: NSSize) -> NSRect {
        // Diagnostics: log every screen so we can see what AppKit reports.
        for (i, s) in NSScreen.screens.enumerated() {
            Log.info("screen[\(i)] \(s.localizedName) frame=\(s.frame) visibleFrame=\(s.visibleFrame) safeArea=\(s.safeAreaInsets)")
        }
        Log.info("mouseLocation=\(NSEvent.mouseLocation), NSScreen.main=\(NSScreen.main?.localizedName ?? "nil")")

        let mouseLocation = NSEvent.mouseLocation
        let screen: NSScreen = NSScreen.screens.first(where: {
            $0.frame.contains(mouseLocation)
        }) ?? NSScreen.main ?? NSScreen.screens.first!
        let vf = screen.visibleFrame

        // Compute panel size capped to fit.
        let width = min(panelSize.width, vf.width - 2 * edgeInset)
        let height = min(panelSize.height, vf.height - 2 * edgeInset)

        // Bottom-right anchor with generous safety margins from the Dock.
        var x = vf.maxX - width - edgeInset
        var y = vf.minY + edgeInset

        // Hard clamp inside visibleFrame.
        x = max(vf.minX + edgeInset, min(x, vf.maxX - width - edgeInset))
        y = max(vf.minY + edgeInset, min(y, vf.maxY - height - edgeInset))

        let result = NSRect(x: x, y: y, width: width, height: height)
        Log.info("→ panel chosen on '\(screen.localizedName)' at \(result)")
        return result
    }

    /// Size of the image area inside the panel (the panel itself is taller by
    /// `barHeight` to make room for the action bar below the image).
    private static func scaledImageSize(for imageSize: NSSize) -> NSSize {
        guard imageSize.width > 0, imageSize.height > 0 else {
            return NSSize(width: 200, height: 200)
        }
        let aspect = imageSize.width / imageSize.height
        var height = imageMaxHeight
        var width = height * aspect
        if width > imageMaxWidth {
            width = imageMaxWidth
            height = width / aspect
        }
        return NSSize(width: ceil(width), height: ceil(height))
    }
}
