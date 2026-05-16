import AppKit

@MainActor
final class ThumbnailView: NSView, NSDraggingSource {
    let fileURL: URL
    private let image: NSImage
    private let imageLayer = CALayer()
    private let confirmationLabel = NSTextField(labelWithString: "")
    private let buttonStack = NSStackView()
    private var buttonBlur: NSVisualEffectView?
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

        // Close button (top-right) — dark circle with white X so it shows on light screenshots.
        closeButton.bezelStyle = .circular
        closeButton.isBordered = false
        let xConfig = NSImage.SymbolConfiguration(pointSize: 16, weight: .bold)
        let xImage = NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: "Close")?
            .withSymbolConfiguration(xConfig)
        closeButton.image = xImage
        closeButton.contentTintColor = NSColor.white
        closeButton.wantsLayer = true
        closeButton.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.55).cgColor
        closeButton.layer?.cornerRadius = 12
        closeButton.target = self
        closeButton.action = #selector(closePressed)
        closeButton.isHidden = true
        closeButton.frame = NSRect(x: bounds.width - 28, y: bounds.height - 28, width: 24, height: 24)
        closeButton.autoresizingMask = [.minXMargin, .minYMargin]
        addSubview(closeButton)

        // Button bar at bottom: capsule-pill with visible white text on dark blur.
        let blur = NSVisualEffectView()
        blur.material = .hudWindow
        blur.blendingMode = .withinWindow
        blur.state = .active
        blur.wantsLayer = true
        blur.layer?.cornerRadius = 14
        blur.layer?.masksToBounds = true
        blur.translatesAutoresizingMaskIntoConstraints = false
        blur.isHidden = true
        addSubview(blur)
        buttonBlur = blur

        buttonStack.orientation = .horizontal
        buttonStack.spacing = 2
        buttonStack.alignment = .centerY
        buttonStack.distribution = .fillEqually
        buttonStack.translatesAutoresizingMaskIntoConstraints = false
        let copy = makeActionButton(title: "Copy", action: #selector(copyPressed))
        let save = makeActionButton(title: "Save…", action: #selector(savePressed))
        let open = makeActionButton(title: "Open", action: #selector(openPressed))
        buttonStack.addArrangedSubview(copy)
        buttonStack.addArrangedSubview(makeSeparator())
        buttonStack.addArrangedSubview(save)
        buttonStack.addArrangedSubview(makeSeparator())
        buttonStack.addArrangedSubview(open)
        blur.addSubview(buttonStack)

        NSLayoutConstraint.activate([
            blur.centerXAnchor.constraint(equalTo: centerXAnchor),
            blur.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12),
            blur.heightAnchor.constraint(equalToConstant: 30),
            buttonStack.leadingAnchor.constraint(equalTo: blur.leadingAnchor, constant: 4),
            buttonStack.trailingAnchor.constraint(equalTo: blur.trailingAnchor, constant: -4),
            buttonStack.topAnchor.constraint(equalTo: blur.topAnchor),
            buttonStack.bottomAnchor.constraint(equalTo: blur.bottomAnchor)
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
        closeButton.isHidden = false
        buttonBlur?.isHidden = false
        onHoverChange?(true)
    }

    override func mouseExited(with event: NSEvent) {
        closeButton.isHidden = true
        buttonBlur?.isHidden = true
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
        // Tap on image (not over a button) opens the file.
        if event.clickCount == 1 {
            // Ignore clicks landing on buttons (hit-tested by AppKit already if hidden=false).
            if (buttonBlur?.isHidden ?? true) && closeButton.isHidden {
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
            .font: NSFont.systemFont(ofSize: 12, weight: .semibold)
        ]
        let attrTitle = NSAttributedString(string: title, attributes: attrs)
        let b = NSButton(title: title, target: self, action: action)
        b.attributedTitle = attrTitle
        b.isBordered = false
        b.bezelStyle = .regularSquare
        b.setButtonType(.momentaryChange)
        b.focusRingType = .none
        b.translatesAutoresizingMaskIntoConstraints = false
        b.widthAnchor.constraint(greaterThanOrEqualToConstant: 56).isActive = true
        return b
    }

    private func makeSeparator() -> NSView {
        let v = NSView()
        v.wantsLayer = true
        v.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.25).cgColor
        v.translatesAutoresizingMaskIntoConstraints = false
        v.widthAnchor.constraint(equalToConstant: 1).isActive = true
        v.heightAnchor.constraint(equalToConstant: 16).isActive = true
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
