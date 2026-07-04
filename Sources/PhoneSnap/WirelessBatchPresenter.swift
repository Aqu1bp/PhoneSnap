import AppKit

@MainActor
final class WirelessBatchPresenter {
    /// Newest first. Persists across batches so the panel shows a running
    /// "recent from iPhone" strip rather than only the last run.
    private var items: [URL] = []
    private var panelController: RecentFromIPhonePanelController?

    private static let maxItems = 20

    /// Shows the panel immediately on the first upload and appends live as
    /// the rest of the batch streams in — no debounce; waiting for the batch
    /// to go quiet made the panel feel several seconds late.
    func enqueue(fileURL: URL) {
        items.insert(fileURL, at: 0)
        if items.count > Self.maxItems {
            items.removeLast(items.count - Self.maxItems)
        }

        if let panelController {
            panelController.update(fileURLs: items)
            panelController.show()
        } else {
            let controller = RecentFromIPhonePanelController(fileURLs: items) { [weak self] controller in
                if self?.panelController === controller {
                    self?.panelController = nil
                }
            }
            panelController = controller
            controller.show()
        }
    }
}

@MainActor
final class RecentFromIPhonePanelController: NSObject {
    private let panel: NSPanel
    private let scrollView = NSScrollView()
    private let stackView = NSStackView()
    private let emptyLabel = NSTextField(labelWithString: "No recent images")
    private let hintLabel = NSTextField(labelWithString: "Drag a thumbnail into any chat  •  Click to copy  •  Double-click to open")
    private let onClosed: (RecentFromIPhonePanelController) -> Void
    /// Cache so live batch updates reuse views instead of re-decoding images.
    private var itemViews: [URL: RecentFromIPhoneThumbnailView] = [:]

    private static let panelSize = NSSize(width: 760, height: 270)
    private static let edgeInset: CGFloat = 18
    private static let contentInset: CGFloat = 14
    private static let itemSize = NSSize(width: 118, height: 172)

    init(fileURLs: [URL], onClosed: @escaping (RecentFromIPhonePanelController) -> Void) {
        self.onClosed = onClosed
        let frame = Self.defaultFrame(size: Self.panelSize)
        panel = NSPanel(
            contentRect: frame,
            styleMask: [.titled, .closable, .utilityWindow, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        super.init()

        panel.title = "Recent from iPhone"
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isMovableByWindowBackground = true
        panel.delegate = self

        let root = NSView(frame: NSRect(origin: .zero, size: Self.panelSize))
        root.wantsLayer = true
        root.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        panel.contentView = root

        scrollView.drawsBackground = false
        scrollView.hasHorizontalScroller = true
        scrollView.hasVerticalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(scrollView)

        stackView.orientation = .horizontal
        stackView.alignment = .top
        stackView.distribution = .gravityAreas
        stackView.spacing = 10
        stackView.edgeInsets = NSEdgeInsets(
            top: Self.contentInset,
            left: Self.contentInset,
            bottom: Self.contentInset,
            right: Self.contentInset
        )
        stackView.translatesAutoresizingMaskIntoConstraints = false

        let documentView = NSView()
        documentView.translatesAutoresizingMaskIntoConstraints = false
        documentView.addSubview(stackView)
        scrollView.documentView = documentView

        emptyLabel.textColor = .secondaryLabelColor
        emptyLabel.alignment = .center
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        emptyLabel.isHidden = true
        root.addSubview(emptyLabel)

        hintLabel.font = .systemFont(ofSize: 11)
        hintLabel.textColor = .tertiaryLabelColor
        hintLabel.alignment = .center
        hintLabel.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(hintLabel)

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: root.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: hintLabel.topAnchor, constant: -4),

            hintLabel.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 12),
            hintLabel.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -12),
            hintLabel.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -8),

            documentView.heightAnchor.constraint(equalTo: scrollView.contentView.heightAnchor),
            documentView.topAnchor.constraint(equalTo: scrollView.contentView.topAnchor),
            documentView.leadingAnchor.constraint(equalTo: scrollView.contentView.leadingAnchor),

            stackView.leadingAnchor.constraint(equalTo: documentView.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: documentView.trailingAnchor),
            stackView.topAnchor.constraint(equalTo: documentView.topAnchor),
            stackView.bottomAnchor.constraint(lessThanOrEqualTo: documentView.bottomAnchor),
            stackView.heightAnchor.constraint(equalTo: documentView.heightAnchor),

            emptyLabel.centerXAnchor.constraint(equalTo: root.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: root.centerYAnchor)
        ])

        update(fileURLs: fileURLs)
    }

    func show() {
        panel.setFrame(Self.defaultFrame(size: panel.frame.size), display: false)
        panel.orderFrontRegardless()
    }

    func update(fileURLs: [URL]) {
        stackView.arrangedSubviews.forEach { view in
            stackView.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        emptyLabel.isHidden = !fileURLs.isEmpty
        for url in fileURLs {
            let item: RecentFromIPhoneThumbnailView
            if let cached = itemViews[url] {
                item = cached
            } else {
                guard let image = NSImage(contentsOf: url) else {
                    Log.error("Could not load wireless batch image at \(url.path)")
                    continue
                }
                item = RecentFromIPhoneThumbnailView(image: image, fileURL: url, size: Self.itemSize)
                item.translatesAutoresizingMaskIntoConstraints = false
                NSLayoutConstraint.activate([
                    item.widthAnchor.constraint(equalToConstant: Self.itemSize.width),
                    item.heightAnchor.constraint(equalToConstant: Self.itemSize.height)
                ])
                itemViews[url] = item
            }
            stackView.addArrangedSubview(item)
        }
        let live = Set(fileURLs)
        itemViews = itemViews.filter { live.contains($0.key) }
        scrollView.contentView.scroll(to: .zero)
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }

    private static func defaultFrame(size: NSSize) -> NSRect {
        let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) })
            ?? NSScreen.main
            ?? NSScreen.screens.first!
        let vf = screen.visibleFrame
        let width = min(size.width, vf.width - 2 * edgeInset)
        let height = min(size.height, vf.height - 2 * edgeInset)
        let x = vf.maxX - width - edgeInset
        let y = vf.maxY - height - edgeInset
        return NSRect(x: x, y: y, width: width, height: height)
    }
}

extension RecentFromIPhonePanelController: NSWindowDelegate {
    nonisolated func windowWillClose(_ notification: Notification) {
        Task { @MainActor in
            onClosed(self)
        }
    }
}

@MainActor
final class RecentFromIPhoneThumbnailView: NSView, NSDraggingSource {
    private let image: NSImage
    private let fileURL: URL
    private let imageLayer = CALayer()
    private let label = NSTextField(labelWithString: "")
    private let copiedLabel = NSTextField(labelWithString: "Copied")

    init(image: NSImage, fileURL: URL, size: NSSize) {
        self.image = image
        self.fileURL = fileURL
        super.init(frame: NSRect(origin: .zero, size: size))

        wantsLayer = true
        layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        layer?.borderColor = NSColor.separatorColor.cgColor
        layer?.borderWidth = 1
        layer?.cornerRadius = 8
        layer?.masksToBounds = true

        imageLayer.contents = image
        imageLayer.contentsGravity = .resizeAspect
        imageLayer.backgroundColor = NSColor.black.withAlphaComponent(0.05).cgColor
        imageLayer.cornerRadius = 6
        imageLayer.masksToBounds = true
        layer?.addSublayer(imageLayer)

        label.stringValue = fileURL.lastPathComponent
        label.font = .systemFont(ofSize: 10)
        label.textColor = .secondaryLabelColor
        label.lineBreakMode = .byTruncatingMiddle
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)

        copiedLabel.font = .systemFont(ofSize: 11, weight: .semibold)
        copiedLabel.textColor = .white
        copiedLabel.alignment = .center
        copiedLabel.wantsLayer = true
        copiedLabel.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.72).cgColor
        copiedLabel.layer?.cornerRadius = 8
        copiedLabel.translatesAutoresizingMaskIntoConstraints = false
        copiedLabel.isHidden = true
        addSubview(copiedLabel)

        toolTip = fileURL.lastPathComponent

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -7),
            label.heightAnchor.constraint(equalToConstant: 14),

            copiedLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            copiedLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            copiedLabel.widthAnchor.constraint(equalToConstant: 64),
            copiedLabel.heightAnchor.constraint(equalToConstant: 26)
        ])
    }

    required init?(coder: NSCoder) { fatalError("not supported") }

    /// The panel moves when dragged by its background; a drag that starts on
    /// a thumbnail must start an image drag instead of moving the window.
    override var mouseDownCanMoveWindow: Bool { false }

    override func layout() {
        super.layout()
        imageLayer.frame = imageRect()
        setHovered(mouseIsInside())
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways],
            owner: self,
            userInfo: nil
        ))
    }

    override func mouseEntered(with event: NSEvent) {
        setHovered(mouseIsInside())
    }

    override func mouseExited(with event: NSEvent) {
        setHovered(false)
    }

    /// Views shift under a stationary cursor as new thumbnails stream in, so
    /// enter/exit events alone leave stale highlights — recheck on layout.
    private func mouseIsInside() -> Bool {
        guard let window else { return false }
        let point = convert(window.mouseLocationOutsideOfEventStream, from: nil)
        return bounds.contains(point)
    }

    private var isHovered = false

    private func setHovered(_ hovered: Bool) {
        guard hovered != isHovered else { return }
        isHovered = hovered
        layer?.borderColor = hovered ? NSColor.controlAccentColor.cgColor : NSColor.separatorColor.cgColor
        layer?.borderWidth = hovered ? 2 : 1
        if hovered { NSCursor.openHand.set() } else { NSCursor.arrow.set() }
    }

    private var mouseDownLocation: NSPoint?
    private var dragSessionActive = false

    override func mouseDown(with event: NSEvent) {
        mouseDownLocation = event.locationInWindow
        dragSessionActive = false
    }

    override func mouseDragged(with event: NSEvent) {
        // Start exactly one drag session per gesture, and only after the
        // cursor has actually moved — beginning a session on every drag
        // event made drags flaky and turned click jitter into failed drags.
        guard !dragSessionActive else { return }
        guard let down = mouseDownLocation else { return }
        let dx = event.locationInWindow.x - down.x
        let dy = event.locationInWindow.y - down.y
        guard dx * dx + dy * dy >= 9 else { return }
        dragSessionActive = true

        let pbItem = NSPasteboardItem()
        pbItem.setDataProvider(self, forTypes: [.fileURL])
        pbItem.setString(fileURL.absoluteString, forType: .fileURL)
        // Also carry raw PNG bytes so drop targets that don't accept file
        // URLs (web chat boxes, some agent UIs) still receive the image.
        if let data = try? Data(contentsOf: fileURL) {
            pbItem.setData(data, forType: .png)
        }

        let draggingItem = NSDraggingItem(pasteboardWriter: pbItem)
        let dragSize = NSSize(width: min(140, bounds.width), height: min(120, bounds.height))
        let location = convert(event.locationInWindow, from: nil)
        let dragFrame = NSRect(
            x: location.x - dragSize.width / 2,
            y: location.y - dragSize.height / 2,
            width: dragSize.width,
            height: dragSize.height
        )
        draggingItem.setDraggingFrame(dragFrame, contents: image)
        beginDraggingSession(with: [draggingItem], event: event, source: self)
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        dragSessionActive = false
        mouseDownLocation = nil
    }

    private var pendingCopy: DispatchWorkItem?

    override func mouseUp(with event: NSEvent) {
        mouseDownLocation = nil
        if dragSessionActive { dragSessionActive = false; return }
        if event.clickCount >= 2 {
            // Cancel the pending single-click copy — otherwise a double
            // click copies on the first click and opens on the second.
            pendingCopy?.cancel()
            pendingCopy = nil
            NSWorkspace.shared.open(fileURL)
        } else {
            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                self.pendingCopy = nil
                Pasteboard.write(fileURL: self.fileURL)
                self.flashCopied()
            }
            pendingCopy = work
            DispatchQueue.main.asyncAfter(deadline: .now() + NSEvent.doubleClickInterval, execute: work)
        }
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        [.copy, .generic]
    }

    private func imageRect() -> NSRect {
        NSRect(
            x: 6,
            y: 27,
            width: max(0, bounds.width - 12),
            height: max(0, bounds.height - 34)
        )
    }

    private func flashCopied() {
        copiedLabel.isHidden = false
        copiedLabel.alphaValue = 1
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.9
            copiedLabel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            self?.copiedLabel.isHidden = true
        })
    }
}

extension RecentFromIPhoneThumbnailView: NSPasteboardItemDataProvider {
    nonisolated func pasteboard(_ pasteboard: NSPasteboard?, item: NSPasteboardItem, provideDataForType type: NSPasteboard.PasteboardType) {
        // The file URL is written inline on the pasteboard item.
    }
}
