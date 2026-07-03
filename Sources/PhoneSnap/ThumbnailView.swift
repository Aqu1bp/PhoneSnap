import AppKit

@MainActor
final class ThumbnailView: NSView, NSDraggingSource {
    let fileURL: URL
    private let image: NSImage
    private let barHeight: CGFloat
    private let imageLayer = CALayer()
    private let confirmationLabel = NSTextField(labelWithString: "")
    private let buttonStack = NSStackView()
    private var buttonBar: NSView?
    private let closeButton = HoverCursorButton()
    private var trackingArea: NSTrackingArea?
    private var localKeyMonitor: Any?

    var onClose: (() -> Void)?
    var onCopy: (() -> Void)?
    var onSave: (() -> Void)?
    var onOpen: (() -> Void)?
    var onDelete: (() -> Void)?
    var onHoverChange: ((Bool) -> Void)?
    var onEscape: (() -> Void)?

    init(frame: NSRect, image: NSImage, fileURL: URL, barHeight: CGFloat) {
        self.image = image
        self.fileURL = fileURL
        self.barHeight = barHeight
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = 14
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.45).cgColor
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        layer?.masksToBounds = true

        // Image fills the top portion of the panel, above the action bar.
        imageLayer.contentsGravity = .resizeAspect
        imageLayer.contents = image
        imageLayer.frame = imageRect()
        imageLayer.cornerRadius = 6
        imageLayer.masksToBounds = true
        layer?.addSublayer(imageLayer)

        // Always-visible bottom action bar (full panel width, sits below the image).
        let bar = NSView()
        bar.wantsLayer = true
        bar.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.92).cgColor
        bar.translatesAutoresizingMaskIntoConstraints = false
        addSubview(bar)
        buttonBar = bar

        // Subtle top separator between image and bar.
        let separator = NSView()
        separator.wantsLayer = true
        separator.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.10).cgColor
        separator.translatesAutoresizingMaskIntoConstraints = false
        bar.addSubview(separator)

        buttonStack.orientation = .horizontal
        buttonStack.spacing = 0
        buttonStack.alignment = .centerY
        buttonStack.distribution = .fillEqually
        buttonStack.translatesAutoresizingMaskIntoConstraints = false
        let copy = makeIconButton(symbol: "doc.on.clipboard", tooltip: "Copy (⌘C)", action: #selector(copyPressed))
        let save = makeIconButton(symbol: "square.and.arrow.down", tooltip: "Save to Downloads (⌘S)", action: #selector(savePressed))
        let open = makeIconButton(symbol: "arrow.up.forward.app", tooltip: "Open in Preview", action: #selector(openPressed))
        let trash = makeIconButton(symbol: "trash", tooltip: "Delete screenshot (⌘⌫)", action: #selector(deletePressed))
        trash.contentTintColor = NSColor.systemRed.blended(withFraction: 0.35, of: .white) ?? .systemRed
        buttonStack.addArrangedSubview(copy)
        buttonStack.addArrangedSubview(save)
        buttonStack.addArrangedSubview(open)
        buttonStack.addArrangedSubview(trash)
        bar.addSubview(buttonStack)

        NSLayoutConstraint.activate([
            bar.leadingAnchor.constraint(equalTo: leadingAnchor),
            bar.trailingAnchor.constraint(equalTo: trailingAnchor),
            bar.bottomAnchor.constraint(equalTo: bottomAnchor),
            bar.heightAnchor.constraint(equalToConstant: barHeight),
            separator.leadingAnchor.constraint(equalTo: bar.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: bar.trailingAnchor),
            separator.topAnchor.constraint(equalTo: bar.topAnchor),
            separator.heightAnchor.constraint(equalToConstant: 1),
            buttonStack.leadingAnchor.constraint(equalTo: bar.leadingAnchor),
            buttonStack.trailingAnchor.constraint(equalTo: bar.trailingAnchor),
            buttonStack.topAnchor.constraint(equalTo: separator.bottomAnchor),
            buttonStack.bottomAnchor.constraint(equalTo: bar.bottomAnchor)
        ])

        // Close button (top-right of the image area).
        closeButton.bezelStyle = .circular
        closeButton.isBordered = false
        let xConfig = NSImage.SymbolConfiguration(pointSize: 12, weight: .bold)
        let xImage = NSImage(systemSymbolName: "xmark", accessibilityDescription: "Close")?
            .withSymbolConfiguration(xConfig)
        closeButton.image = xImage
        closeButton.contentTintColor = NSColor.white
        closeButton.wantsLayer = true
        closeButton.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.75).cgColor
        closeButton.layer?.cornerRadius = 10
        closeButton.target = self
        closeButton.action = #selector(closePressed)
        closeButton.frame = NSRect(x: bounds.width - 24, y: bounds.height - 24, width: 20, height: 20)
        closeButton.autoresizingMask = [.minXMargin, .minYMargin]
        addSubview(closeButton)

        confirmationLabel.font = .systemFont(ofSize: 11, weight: .semibold)
        confirmationLabel.textColor = .white
        confirmationLabel.alignment = .center
        confirmationLabel.wantsLayer = true
        confirmationLabel.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.7).cgColor
        confirmationLabel.layer?.cornerRadius = 8
        confirmationLabel.isBezeled = false
        confirmationLabel.drawsBackground = false
        confirmationLabel.translatesAutoresizingMaskIntoConstraints = false
        confirmationLabel.isHidden = true
        addSubview(confirmationLabel)
        NSLayoutConstraint.activate([
            confirmationLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            confirmationLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            confirmationLabel.heightAnchor.constraint(equalToConstant: 28),
            confirmationLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 90)
        ])

        installLocalKeyMonitor()
    }

    required init?(coder: NSCoder) { fatalError("not supported") }

    deinit {
        if let monitor = localKeyMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let area = trackingArea { removeTrackingArea(area) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        onHoverChange?(true)
    }

    override func mouseExited(with event: NSEvent) {
        onHoverChange?(false)
    }

    override func layout() {
        super.layout()
        imageLayer.frame = imageRect()
    }

    private func imageRect() -> NSRect {
        let inset: CGFloat = 4
        return NSRect(
            x: inset,
            y: barHeight + inset,
            width: max(0, bounds.width - inset * 2),
            height: max(0, bounds.height - barHeight - inset * 2)
        )
    }

    // MARK: drag-out
    override func mouseDragged(with event: NSEvent) {
        let pt = convert(event.locationInWindow, from: nil)
        guard imageRect().contains(pt) else { return }
        let pbItem = NSPasteboardItem()
        pbItem.setDataProvider(self, forTypes: [.fileURL])
        // Encode the file URL inline so even simple drop targets work.
        pbItem.setString(fileURL.absoluteString, forType: .fileURL)
        let draggingItem = NSDraggingItem(pasteboardWriter: pbItem)
        let dragImage = image
        let dragSize = NSSize(width: min(160, bounds.width), height: min(120, bounds.height))
        let location = convert(event.locationInWindow, from: nil)
        let dragFrame = NSRect(
            x: location.x - dragSize.width / 2,
            y: location.y - dragSize.height / 2,
            width: dragSize.width,
            height: dragSize.height
        )
        draggingItem.setDraggingFrame(dragFrame, contents: dragImage)
        beginDraggingSession(with: [draggingItem], event: event, source: self)
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        return [.copy, .generic]
    }

    override func mouseUp(with event: NSEvent) {
        // Click directly on the image (not in the bottom bar or close button)
        // opens the file in Preview. The bar/buttons handle their own events
        // because they're real subviews and will intercept the mouseDown.
        if event.clickCount == 1 {
            let pt = convert(event.locationInWindow, from: nil)
            if imageRect().contains(pt) {
                onOpen?()
            }
        }
    }

    // MARK: keyboard
    private func installLocalKeyMonitor() {
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            if self.window?.isVisible == true {
                switch event.keyCode {
                case 53: // escape
                    self.onEscape?()
                    return nil
                case 8 where event.modifierFlags.contains(.command): // ⌘C
                    self.onCopy?()
                    return nil
                case 1 where event.modifierFlags.contains(.command): // ⌘S
                    self.onSave?()
                    return nil
                case 51 where event.modifierFlags.contains(.command): // ⌘⌫
                    self.onDelete?()
                    return nil
                default:
                    break
                }
            }
            return event
        }
    }

    private func makeIconButton(symbol: String, tooltip: String, action: Selector) -> NSButton {
        let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .semibold)
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: tooltip)?
            .withSymbolConfiguration(config)
        let b = HoverCursorButton(image: image ?? NSImage(), target: self, action: action)
        b.title = ""
        b.contentTintColor = .white
        b.isBordered = false
        b.bezelStyle = .regularSquare
        b.setButtonType(.momentaryChange)
        b.focusRingType = .none
        b.imagePosition = .imageOnly
        b.imageScaling = .scaleProportionallyDown
        b.wantsLayer = true
        b.layer?.backgroundColor = NSColor.clear.cgColor
        b.toolTip = tooltip
        b.translatesAutoresizingMaskIntoConstraints = false
        // No minimum width — icons fit in any width, distribute equally across
        // the action bar via the parent stack view.
        return b
    }

    @objc private func closePressed() { onClose?() }
    @objc private func copyPressed() { onCopy?() }
    @objc private func savePressed() { onSave?() }
    @objc private func openPressed() { onOpen?() }
    @objc private func deletePressed() { onDelete?() }

    func flashConfirmation(_ text: String) {
        confirmationLabel.stringValue = "  \(text)  "
        confirmationLabel.isHidden = false
        confirmationLabel.alphaValue = 1.0
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 1.0
            confirmationLabel.animator().alphaValue = 0.0
        }, completionHandler: { [weak self] in
            self?.confirmationLabel.isHidden = true
        })
    }
}

extension ThumbnailView: NSPasteboardItemDataProvider {
    nonisolated func pasteboard(_ pasteboard: NSPasteboard?, item: NSPasteboardItem, provideDataForType type: NSPasteboard.PasteboardType) {
        // The file URL is already inline on the pasteboard item; nothing extra to provide.
    }
}

/// NSButton that swaps the pointer to `.pointingHand` while hovered AND
/// shows a visible background tint so users get clear feedback on
/// non-activating-panel windows (where AppKit's default cursor / hover
/// machinery doesn't reliably fire).
final class HoverCursorButton: NSButton {
    private var trackingArea: NSTrackingArea?
    private var isHovering = false
    private var isPressed = false
    /// Hover tint color. Override at construction time if you want a different
    /// look (e.g. the close button uses a darker baseline).
    var hoverTint: NSColor = NSColor.white.withAlphaComponent(0.14)
    var pressTint: NSColor = NSColor.white.withAlphaComponent(0.24)

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let area = trackingArea { removeTrackingArea(area) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect, .cursorUpdate],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        isHovering = true
        NSCursor.pointingHand.set()
        refreshTint()
    }

    override func mouseExited(with event: NSEvent) {
        isHovering = false
        NSCursor.arrow.set()
        refreshTint()
    }

    override func cursorUpdate(with event: NSEvent) {
        // Belt-and-suspenders: AppKit calls this whenever the cursor crosses the
        // tracking area boundary; ensures the cursor is right even if a stale
        // override leaked from elsewhere.
        NSCursor.pointingHand.set()
    }

    override func mouseDown(with event: NSEvent) {
        isPressed = true
        refreshTint()
        super.mouseDown(with: event)
        isPressed = false
        refreshTint()
    }

    private func refreshTint() {
        wantsLayer = true
        if isPressed {
            layer?.backgroundColor = pressTint.cgColor
        } else if isHovering {
            layer?.backgroundColor = hoverTint.cgColor
        } else {
            layer?.backgroundColor = NSColor.clear.cgColor
        }
    }
}
