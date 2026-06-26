import AppKit

@MainActor
final class WirelessBatchPresenter {
    private var pending: [URL] = []
    private var debounceTimer: Timer?
    private var panelController: RecentFromIPhonePanelController?

    private static let debounceInterval: TimeInterval = 2.4
    private static let maxBatchSize = 20

    func enqueue(fileURL: URL) {
        pending.append(fileURL)
        if pending.count > Self.maxBatchSize {
            pending.removeFirst(pending.count - Self.maxBatchSize)
        }
        debounceTimer?.invalidate()
        debounceTimer = Timer.scheduledTimer(withTimeInterval: Self.debounceInterval, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.flush()
            }
        }
    }

    private func flush() {
        debounceTimer?.invalidate()
        debounceTimer = nil

        guard !pending.isEmpty else { return }
        let urls = pending
        pending.removeAll()

        if let panelController {
            panelController.update(fileURLs: urls)
            panelController.show()
        } else {
            let controller = RecentFromIPhonePanelController(fileURLs: urls) { [weak self] controller in
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
    private let onClosed: (RecentFromIPhonePanelController) -> Void

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

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: root.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: root.bottomAnchor),

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
            guard let image = NSImage(contentsOf: url) else {
                Log.error("Could not load wireless batch image at \(url.path)")
                continue
            }
            let item = RecentFromIPhoneThumbnailView(image: image, fileURL: url, size: Self.itemSize)
            item.translatesAutoresizingMaskIntoConstraints = false
            stackView.addArrangedSubview(item)
            NSLayoutConstraint.activate([
                item.widthAnchor.constraint(equalToConstant: Self.itemSize.width),
                item.heightAnchor.constraint(equalToConstant: Self.itemSize.height)
            ])
        }
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

    override func layout() {
        super.layout()
        imageLayer.frame = imageRect()
    }

    override func mouseDragged(with event: NSEvent) {
        let pbItem = NSPasteboardItem()
        pbItem.setDataProvider(self, forTypes: [.fileURL])
        pbItem.setString(fileURL.absoluteString, forType: .fileURL)

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

    override func mouseUp(with event: NSEvent) {
        if event.clickCount >= 2 {
            NSWorkspace.shared.open(fileURL)
        } else {
            Pasteboard.write(fileURL: fileURL)
            flashCopied()
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
