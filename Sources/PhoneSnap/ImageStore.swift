import Foundation
import AppKit
import ImageIO

final class ImageStore: @unchecked Sendable {
    enum SaveError: Error {
        case noImage
        case imageTooLarge
    }

    /// Bounds decoded memory use for authenticated LAN uploads. Current phone
    /// screenshots are far below this threshold, while compressed image bombs
    /// can advertise enormous dimensions in a small request body.
    private static let maxPixelCount = 50_000_000

    let folder: URL
    private let saveLock = NSLock()

    init(folder overrideFolder: URL? = nil) {
        let envPath = ProcessInfo.processInfo.environment["PHONESNAP_DIR"]
        if let overrideFolder {
            folder = overrideFolder
        } else if let envPath, !envPath.isEmpty {
            folder = URL(fileURLWithPath: (envPath as NSString).expandingTildeInPath, isDirectory: true)
        } else {
            let pictures = FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Pictures", isDirectory: true)
            folder = pictures.appendingPathComponent("PhoneSnap", isDirectory: true)
        }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    func save(data: Data) throws -> URL {
        // Image decoding is intentionally serialized. Wired, ADB, and wireless
        // callbacks arrive on different queues; serializing bounds aggregate
        // decoder memory and makes destination allocation collision-free.
        saveLock.lock()
        defer { saveLock.unlock() }

        let pngData = try normalize(data: data)
        let url = nextAvailableURL()
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

    private func nextAvailableURL() -> URL {
        let preferred = folder.appendingPathComponent(filename(), isDirectory: false)
        guard FileManager.default.fileExists(atPath: preferred.path) else { return preferred }

        let base = preferred.deletingPathExtension().lastPathComponent
        for suffix in 2...9_999 {
            let candidate = folder.appendingPathComponent("\(base) (\(suffix)).png", isDirectory: false)
            if !FileManager.default.fileExists(atPath: candidate.path) { return candidate }
        }
        return folder.appendingPathComponent("\(base) \(UUID().uuidString).png", isDirectory: false)
    }

    /// Decode incoming bytes, convert anything that loads to PNG.
    private func normalize(data: Data) throws -> Data {
        switch Self.dimensionValidation(data) {
        case .acceptable:
            if let png = Self.png(fromEncodedData: data) { return png }
        case .tooLarge:
            throw SaveError.imageTooLarge
        case .unknown:
            break
        }

        // Fallback: scan for an embedded PNG/JPEG signature inside the body (e.g. unparsed multipart).
        if let extracted = Self.extractImageBytes(from: data) {
            switch Self.dimensionValidation(extracted) {
            case .acceptable:
                if let png = Self.png(fromEncodedData: extracted) { return png }
            case .tooLarge:
                throw SaveError.imageTooLarge
            case .unknown:
                break
            }
        }
        throw SaveError.noImage
    }

    private enum DimensionValidation {
        case acceptable(width: Int, height: Int)
        case tooLarge
        case unknown
    }

    private static func dimensionValidation(_ data: Data) -> DimensionValidation {
        let dimensions = pngDimensions(data) ?? imageIODimensions(data)
        guard let (width, height) = dimensions, width > 0, height > 0 else {
            // Fail closed. NSImage also supports vector/PDF content, which can
            // report no raster dimensions and allocate enormous TIFF buffers.
            return .unknown
        }
        guard width <= maxPixelCount / height,
              width * height <= maxPixelCount else { return .tooLarge }
        return .acceptable(width: width, height: height)
    }

    private static func pngDimensions(_ data: Data) -> (Int, Int)? {
        let signature: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
        guard data.count >= 24,
              data.prefix(signature.count).elementsEqual(signature),
              data[12] == 0x49, data[13] == 0x48,
              data[14] == 0x44, data[15] == 0x52 else { return nil }

        func uint32(at offset: Int) -> UInt32 {
            data[offset..<(offset + 4)].reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        }
        return (Int(uint32(at: 16)), Int(uint32(at: 20)))
    }

    private static func imageIODimensions(_ data: Data) -> (Int, Int)? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
              let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue else {
            return nil
        }
        return (width, height)
    }

    private static func png(fromEncodedData data: Data) -> Data? {
        guard case .acceptable(let width, let height) = dimensionValidation(data),
              let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(width, height)
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary),
              image.width > 0,
              image.height > 0,
              image.width <= maxPixelCount / image.height,
              image.width * image.height <= maxPixelCount else { return nil }

        let rep = NSBitmapImageRep(cgImage: image)
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
