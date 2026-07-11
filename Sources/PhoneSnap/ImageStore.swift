import Foundation
import AppKit
import ImageIO

final class ImageStore {
    enum SaveError: Error {
        case noImage
        case imageTooLarge
    }

    /// Bounds decoded memory use for authenticated LAN uploads. Current phone
    /// screenshots are far below this threshold, while compressed image bombs
    /// can advertise enormous dimensions in a small request body.
    private static let maxPixelCount = 50_000_000

    let folder: URL

    init() {
        let envPath = ProcessInfo.processInfo.environment["PHONESNAP_DIR"]
        if let envPath, !envPath.isEmpty {
            folder = URL(fileURLWithPath: (envPath as NSString).expandingTildeInPath, isDirectory: true)
        } else {
            let pictures = FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Pictures", isDirectory: true)
            folder = pictures.appendingPathComponent("PhoneSnap", isDirectory: true)
        }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    func save(data: Data) throws -> URL {
        let (image, pngData) = try normalize(data: data)
        _ = image // ensure decode succeeds
        let url = folder.appendingPathComponent(filename(), isDirectory: false)
        try pngData.write(to: url, options: .atomic)
        Log.info("Saved \(url.lastPathComponent) (\(pngData.count) bytes)")
        return url
    }

    /// Newest saved screenshot in the folder, if any.
    func latestFile() -> URL? {
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        return contents
            .filter { $0.pathExtension.lowercased() == "png" }
            .max { a, b in
                let da = (try? a.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let db = (try? b.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return da < db
            }
    }

    func revealInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([folder])
    }

    private func filename() -> String {
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_US_POSIX")
        // Millisecond resolution prevents collisions when multiple screenshots
        // arrive within the same second (e.g. via the cable bridge during a
        // catalog refresh, or two rapid taps).
        fmt.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss.SSS"
        return "Screenshot \(fmt.string(from: Date())).png"
    }

    /// Decode incoming bytes, convert anything that loads to PNG.
    private func normalize(data: Data) throws -> (NSImage, Data) {
        if Self.hasAcceptableDimensions(data) == false {
            throw SaveError.imageTooLarge
        }
        if let image = NSImage(data: data),
           let png = Self.png(from: image) {
            return (image, png)
        }
        // Fallback: scan for an embedded PNG/JPEG signature inside the body (e.g. unparsed multipart).
        if let extracted = Self.extractImageBytes(from: data),
           Self.hasAcceptableDimensions(extracted),
           let image = NSImage(data: extracted),
           let png = Self.png(from: image) {
            return (image, png)
        }
        throw SaveError.noImage
    }

    private static func hasAcceptableDimensions(_ data: Data) -> Bool {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
              let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue,
              width > 0,
              height > 0 else {
            // Dimension parsing is part of image validation. Unknown formats
            // continue to NSImage so supported system decoders still work.
            return true
        }
        guard width <= maxPixelCount / height else { return false }
        return width * height <= maxPixelCount
    }

    private static func png(from image: NSImage) -> Data? {
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }

    private static func extractImageBytes(from data: Data) -> Data? {
        let pngSig: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
        if let range = data.range(of: Data(pngSig)) {
            return data.subdata(in: range.lowerBound..<data.count)
        }
        let jpegSig: [UInt8] = [0xFF, 0xD8, 0xFF]
        if let range = data.range(of: Data(jpegSig)) {
            return data.subdata(in: range.lowerBound..<data.count)
        }
        return nil
    }
}
