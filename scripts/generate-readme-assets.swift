import AppKit
import Foundation

@main
@MainActor
struct ReadmeAssetGenerator {
    static func main() throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let assetDir = root.appendingPathComponent("docs/assets", isDirectory: true)
        try FileManager.default.createDirectory(at: assetDir, withIntermediateDirectories: true)

        NSApplication.shared.setActivationPolicy(.accessory)
        NSApplication.shared.appearance = NSAppearance(named: .aqua)
        NSApplication.shared.finishLaunching()

        let sampleURLs = try makeSampleScreenshots()
        try renderWiredThumbnail(sampleURL: sampleURLs[0], to: assetDir.appendingPathComponent("phonesnap-wired-thumbnail.png"))
        try renderWirelessSetup(to: assetDir.appendingPathComponent("phonesnap-wireless-setup.png"))
        try renderWirelessBatch(sampleURLs: sampleURLs, to: assetDir.appendingPathComponent("phonesnap-wireless-batch.png"))
    }

    private static func renderWiredThumbnail(sampleURL: URL, to outputURL: URL) throws {
        guard let image = NSImage(contentsOf: sampleURL) else {
            throw AssetError.message("Could not load sample screenshot")
        }
        let frame = NSRect(x: 0, y: 0, width: 230, height: 348)
        let view = ThumbnailView(frame: frame, image: image, fileURL: sampleURL, barHeight: 46)
        try renderFramed(view: view, size: frame.size, padding: 36, title: "Wired thumbnail", to: outputURL)
    }

    private static func renderWirelessSetup(to outputURL: URL) throws {
        let controller = WirelessSetupWindowController(infoProvider: {
            WirelessSetupInfo(
                pairID: "demo-pair",
                port: 8472,
                receiverState: .ready,
                hostName: "PhoneSnap-Mac.local",
                lanIP: "192.168.1.42"
            )
        })
        controller.show()
        pumpMainRunLoop()
        guard let window = NSApp.windows.first(where: { $0.title == "Set Up PhoneSnap Wireless Shortcut" }),
              let view = window.contentView else {
            throw AssetError.message("Could not find wireless setup window")
        }
        try renderFramed(view: view, size: view.bounds.size, padding: 34, title: "Wireless Shortcut setup", to: outputURL)
        window.close()
    }

    private static func renderWirelessBatch(sampleURLs: [URL], to outputURL: URL) throws {
        let controller = RecentFromIPhonePanelController(fileURLs: sampleURLs) { _ in }
        controller.show()
        pumpMainRunLoop()
        guard let window = NSApp.windows.first(where: { $0.title == "Recent from iPhone" }),
              let view = window.contentView else {
            throw AssetError.message("Could not find recent panel")
        }
        try renderFramed(view: view, size: view.bounds.size, padding: 34, title: "Recent from iPhone", to: outputURL)
        window.close()
    }

    private static func renderFramed(view: NSView, size: NSSize, padding: CGFloat, title: String, to outputURL: URL) throws {
        view.frame = NSRect(origin: .zero, size: size)
        view.layoutSubtreeIfNeeded()

        let headerHeight: CGFloat = 74
        let outputSize = NSSize(width: size.width + padding * 2, height: size.height + padding * 2 + headerHeight)
        let backingScale: CGFloat = 2
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(outputSize.width * backingScale),
            pixelsHigh: Int(outputSize.height * backingScale),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            throw AssetError.message("Could not create bitmap")
        }
        rep.size = outputSize

        NSGraphicsContext.saveGraphicsState()
        guard let context = NSGraphicsContext(bitmapImageRep: rep) else {
            throw AssetError.message("Could not create graphics context")
        }
        NSGraphicsContext.current = context
        context.cgContext.interpolationQuality = .high

        NSColor(calibratedRed: 0.94, green: 0.96, blue: 0.98, alpha: 1).setFill()
        NSRect(origin: .zero, size: outputSize).fill()

        drawSoftShadow(in: context.cgContext, rect: NSRect(x: padding, y: padding, width: size.width, height: size.height), radius: 18)

        let titleRect = NSRect(x: padding, y: outputSize.height - padding - 42, width: outputSize.width - padding * 2, height: 34)
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        (title as NSString).draw(in: titleRect, withAttributes: [
            .font: NSFont.systemFont(ofSize: 20, weight: .semibold),
            .foregroundColor: NSColor(calibratedRed: 0.07, green: 0.09, blue: 0.13, alpha: 1),
            .paragraphStyle: paragraph
        ])

        context.cgContext.translateBy(x: padding, y: padding)
        view.displayIgnoringOpacity(view.bounds, in: context)
        NSGraphicsContext.restoreGraphicsState()

        guard let data = rep.representation(using: .png, properties: [:]) else {
            throw AssetError.message("Could not encode PNG")
        }
        try data.write(to: outputURL)
        try stripPNGMetadata(at: outputURL)
    }

    /// Keep README assets free of hidden machine/user metadata. The rendered
    /// images should contain only pixels plus basic PNG color/geometry chunks.
    private static func stripPNGMetadata(at url: URL) throws {
        let data = try Data(contentsOf: url)
        let signature = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        guard data.starts(with: signature) else {
            throw AssetError.message("Not a PNG: \(url.lastPathComponent)")
        }

        var output = signature
        var cursor = signature.count
        let allowedAncillaryChunks: Set<String> = ["sRGB", "pHYs"]

        while cursor + 12 <= data.count {
            let chunkStart = cursor
            let length = Int(data[cursor]) << 24
                | Int(data[cursor + 1]) << 16
                | Int(data[cursor + 2]) << 8
                | Int(data[cursor + 3])
            let typeStart = cursor + 4
            let typeData = data[typeStart..<typeStart + 4]
            guard let type = String(data: typeData, encoding: .ascii) else {
                throw AssetError.message("Invalid PNG chunk type")
            }
            cursor += 8 + length + 4
            guard cursor <= data.count else {
                throw AssetError.message("Invalid PNG chunk length")
            }

            let isCritical = typeData.first.map { ($0 & 0x20) == 0 } ?? false
            if isCritical || allowedAncillaryChunks.contains(type) {
                output.append(data[chunkStart..<cursor])
            }
            if type == "IEND" { break }
        }

        try output.write(to: url)
    }

    private static func drawSoftShadow(in context: CGContext, rect: NSRect, radius: CGFloat) {
        context.saveGState()
        context.setShadow(offset: CGSize(width: 0, height: -10), blur: 24, color: NSColor.black.withAlphaComponent(0.18).cgColor)
        let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
        NSColor.white.setFill()
        path.fill()
        context.restoreGState()
    }

    private static func makeSampleScreenshots() throws -> [URL] {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("phonesnap-readme-assets", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return try (1...5).map { index in
            let url = dir.appendingPathComponent("Screenshot \(index).png")
            let image = sampleScreenshot(index: index)
            guard let data = image.tiffRepresentation,
                  let rep = NSBitmapImageRep(data: data),
                  let png = rep.representation(using: .png, properties: [:]) else {
                throw AssetError.message("Could not encode sample screenshot")
            }
            try png.write(to: url)
            return url
        }
    }

    private static func sampleScreenshot(index: Int) -> NSImage {
        let size = NSSize(width: 390, height: 844)
        let image = NSImage(size: size)
        image.lockFocus()
        let colors: [(NSColor, NSColor)] = [
            (NSColor(calibratedRed: 0.15, green: 0.42, blue: 0.96, alpha: 1), NSColor(calibratedRed: 0.69, green: 0.86, blue: 1.0, alpha: 1)),
            (NSColor(calibratedRed: 0.12, green: 0.66, blue: 0.48, alpha: 1), NSColor(calibratedRed: 0.76, green: 0.95, blue: 0.84, alpha: 1)),
            (NSColor(calibratedRed: 0.78, green: 0.28, blue: 0.47, alpha: 1), NSColor(calibratedRed: 1.0, green: 0.82, blue: 0.87, alpha: 1)),
            (NSColor(calibratedRed: 0.84, green: 0.52, blue: 0.1, alpha: 1), NSColor(calibratedRed: 1.0, green: 0.91, blue: 0.64, alpha: 1)),
            (NSColor(calibratedRed: 0.39, green: 0.31, blue: 0.86, alpha: 1), NSColor(calibratedRed: 0.83, green: 0.82, blue: 1.0, alpha: 1))
        ]
        let pair = colors[(index - 1) % colors.count]
        NSGradient(starting: pair.0, ending: pair.1)?.draw(in: NSRect(origin: .zero, size: size), angle: 90)

        drawSampleCard(rect: NSRect(x: 28, y: 642, width: 334, height: 132), title: "Checkout", subtitle: "Real iPhone screenshot \(index)")
        drawSampleCard(rect: NSRect(x: 28, y: 438, width: 334, height: 174), title: "Shipping address", subtitle: "Live device state")
        drawSampleButton(rect: NSRect(x: 28, y: 82, width: 334, height: 58), title: "Continue")

        let smallAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 14, weight: .medium),
            .foregroundColor: NSColor.white.withAlphaComponent(0.92)
        ]
        ("9:41" as NSString).draw(at: NSPoint(x: 30, y: 804), withAttributes: smallAttrs)
        image.unlockFocus()
        return image
    }

    private static func drawSampleCard(rect: NSRect, title: String, subtitle: String) {
        let path = NSBezierPath(roundedRect: rect, xRadius: 24, yRadius: 24)
        NSColor.white.withAlphaComponent(0.9).setFill()
        path.fill()
        (title as NSString).draw(at: NSPoint(x: rect.minX + 22, y: rect.maxY - 48), withAttributes: [
            .font: NSFont.systemFont(ofSize: 24, weight: .bold),
            .foregroundColor: NSColor(calibratedWhite: 0.08, alpha: 1)
        ])
        (subtitle as NSString).draw(at: NSPoint(x: rect.minX + 22, y: rect.maxY - 78), withAttributes: [
            .font: NSFont.systemFont(ofSize: 15),
            .foregroundColor: NSColor(calibratedWhite: 0.34, alpha: 1)
        ])
    }

    private static func drawSampleButton(rect: NSRect, title: String) {
        let path = NSBezierPath(roundedRect: rect, xRadius: 18, yRadius: 18)
        NSColor(calibratedWhite: 0.08, alpha: 0.92).setFill()
        path.fill()
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        (title as NSString).draw(in: NSRect(x: rect.minX, y: rect.minY + 17, width: rect.width, height: 24), withAttributes: [
            .font: NSFont.systemFont(ofSize: 17, weight: .semibold),
            .foregroundColor: NSColor.white,
            .paragraphStyle: paragraph
        ])
    }

    private static func pumpMainRunLoop() {
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))
    }
}

enum AssetError: LocalizedError {
    case message(String)

    var errorDescription: String? {
        switch self {
        case .message(let message): return message
        }
    }
}
