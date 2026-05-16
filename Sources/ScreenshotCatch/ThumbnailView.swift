import AppKit

@MainActor
final class ThumbnailView: NSView, NSDraggingSource {
    let fileURL: URL
    private let image: NSImage
    private let imageLayer = CALayer()
    private let confirmationLabel = NSTextField(labelWithString: "")
    private let buttonStack = NSStackView()
    private var buttonBar: NSView?
    private let closeButton = NSButton()
    private var trackingArea: NSTrackingArea?
    private var localKeyMonitor: Any?

    var onClose: (() -> Void)?
    var onCopy: (() -> Void)?
    var onSave: (() -> Void)?
    var onOpen: (() -> Void)?
    var onHoverChange: ((Bool) -> Void)?
    var onEscape: (() -> Void)?

    init(frame: NSRect, image: NSImage, fileURL: URL) {
        self.image = image
        self.fileURL = fileURL
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = 14
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.4).cgColor
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        layer?.masksToBounds = true

        // shadow can't be inside masksToBounds layer; we let the panel's hasShadow handle it.

        imageLayer.contentsGravity = .resizeAspect
        imageLayer.contents = image
        imageLayer.frame = bounds.insetBy(dx: 8, dy: 8)
        imageLayer.cornerRadius = 8
        imageLayer.masksToBounds = true
        layer?.addSublayer(imageLayer)

        // Close button (top-right) — solid dark circle with white X, always visible.
        closeButton.bezelStyle = .circular
        closeButton.isBordered = false
        let xConfig = NSImage.SymbolConfiguration(pointSize: 14, weight: .bold)
        let xImage = NSImage(systemSymbolName: "xmark", accessibilityDescription: "Close")?
            .withSymbolConfiguration(xConfig)
        closeButton.image = xImage
        closeButton.contentTintColor = NSColor.white
        closeButton.wantsLayer = true
        closeButton.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.75).cgColor
        closeButton.layer?.cornerRadius = 11
        closeButton.layer?.borderWidth = 1
        closeButton.layer?.borderColor = NSColor.white.withAlphaComponent(0.25).cgColor
        closeButton.target = self
        closeButton.action = #selector(closePressed)
        closeButton.isHidden = false
        closeButton.frame = NSRect(x: bounds.width - 26, y: bounds.height - 26, width: 22, height: 22)
        closeButton.autoresizingMask = [.minXMargin, .minYMargin]
        addSubview(closeButton)

        // Always-visible action pill at the bottom.
        let pill = NSView()
        pill.wantsLayer = true
        pill.layer?.cornerRadius = 15
        pill.layer?.masksToBounds = true
        pill.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.78).cgColor
        pill.layer?.borderWidth = 1
        pill.layer?.borderColor = NSColor.white.withAlphaComponent(0.18).cgColor
        pill.translatesAutoresizingMaskIntoConstraints = false
        addSubview(pill)
        buttonBar = pill

        buttonStack.orientation = .horizontal
        buttonStack.spacing = 0
        buttonStack.alignment = .centerY
        buttonStack.distribution = .fill
        buttonStack.translatesAutoresizingMaskIntoConstraints = false
        let copy = makeActionButton(title: "Copy", action: #selector(copyPressed))
        let save = makeActionButton(title: "Save", action: #selector(savePressed))
        let open = makeActionButton(title: "Open", action: #selector(openPressed))
        buttonStack.addArrangedSubview(copy)
        buttonStack.addArrangedSubview(makeSeparator())
        buttonStack.addArrangedSubview(save)
        buttonStack.addArrangedSubview(makeSeparator())
        buttonStack.addArrangedSubview(open)
        pill.addSubview(buttonStack)

        NSLayoutConstraint.activate([
            pill.centerXAnchor.constraint(equalTo: centerXAnchor),
            pill.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12),
            pill.heightAnchor.constraint(equalToConstant: 30),
            buttonStack.leadingAnchor.constraint(equalTo: pill.leadingAnchor),
            buttonStack.trailingAnchor.constraint(equalTo: pill.trailingAnchor),
            buttonStack.topAnchor.constraint(equalTo: pill.topAnchor),
            buttonStack.bottomAnchor.constraint(equalTo: pill.bottomAnchor)
        ])

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
        imageLayer.frame = bounds.insetBy(dx: 8, dy: 8)
    }

    // MARK: drag-out
    override func mouseDragged(with event: NSEvent) {
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
        // Click on the image (not on a button) opens the file in Preview.
        if event.clickCount == 1 {
            let pt = convert(event.locationInWindow, from: nil)
            if !(buttonBar?.frame.contains(pt) ?? false) &&
               !closeButton.frame.contains(pt) {
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
                default:
                    break
                }
            }
            return event
        }
    }

    private func makeActionButton(title: String, action: Selector) -> NSButton {
        let attrs: [NSAttributedString.Key: Any] = [
            .foregroundColor: NSColor.white,
            .font: NSFont.systemFont(ofSize: 13, weight: .semibold),
            .kern: 0.2
        ]
        let b = NSButton(title: title, target: self, action: action)
        b.attributedTitle = NSAttributedString(string: title, attributes: attrs)
        b.isBordered = false
        b.bezelStyle = .regularSquare
        b.setButtonType(.momentaryChange)
        b.focusRingType = .none
        b.wantsLayer = true
        b.layer?.backgroundColor = NSColor.clear.cgColor
        b.translatesAutoresizingMaskIntoConstraints = false
        b.widthAnchor.constraint(greaterThanOrEqualToConstant: 60).isActive = true
        return b
    }

    private func makeSeparator() -> NSView {
        let v = NSView()
        v.wantsLayer = true
        v.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.28).cgColor
        v.translatesAutoresizingMaskIntoConstraints = false
        v.widthAnchor.constraint(equalToConstant: 1).isActive = true
        v.heightAnchor.constraint(equalToConstant: 18).isActive = true
        return v
    }

    @objc private func closePressed() { onClose?() }
    @objc private func copyPressed() { onCopy?() }
    @objc private func savePressed() { onSave?() }
    @objc private func openPressed() { onOpen?() }

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
