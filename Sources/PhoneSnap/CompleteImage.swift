import Foundation
import ImageIO
import CLibIMobileDevice

/// ImageIO tolerates truncated PNG/HEIC streams. Reject incomplete containers before decoding.
enum CompleteImage {
    static func isComplete(_ data: Data) -> Bool {
        let bytes = [UInt8](data)
        func number(_ at: Int, _ count: Int) -> UInt64 {
            bytes[at..<(at + count)].reduce(0) { ($0 << 8) | UInt64($1) }
        }
        if bytes.starts(with: [137, 80, 78, 71, 13, 10, 26, 10]) {
            var position = 8
            var hasHeader = false
            var hasPixels = false
            while position <= bytes.count - 12 {
                let length = Int(number(position, 4))
                guard length <= bytes.count - position - 12 else { return false }
                let kind = String(bytes: bytes[(position + 4)..<(position + 8)], encoding: .ascii)
                let crc = bytes.withUnsafeBufferPointer { buffer in
                    crc32(0, buffer.baseAddress!.advanced(by: position + 4), UInt32(length + 4))
                }
                guard UInt64(crc) == number(position + 8 + length, 4) else { return false }
                if position == 8 { guard kind == "IHDR", length == 13 else { return false }; hasHeader = true }
                if kind == "IDAT" { hasPixels = true }
                position += length + 12
                if kind == "IEND" { return length == 0 && position == bytes.count && hasHeader && hasPixels }
            }
            return false
        }
        if bytes.count >= 12, String(bytes: bytes[4..<8], encoding: .ascii) == "ftyp" {
            var position = 0
            var types = Set<String>()
            while position < bytes.count {
                guard bytes.count - position >= 8 else { return false }
                var size = number(position, 4)
                var header = 8
                let type = String(bytes: bytes[(position + 4)..<(position + 8)], encoding: .ascii) ?? ""
                if size == 1 {
                    guard bytes.count - position >= 16 else { return false }
                    size = number(position + 8, 8)
                    header = 16
                }
                guard size >= header, size <= UInt64(bytes.count - position) else { return false }
                types.insert(type)
                position += Int(size)
            }
            return types.isSuperset(of: ["ftyp", "meta", "mdat"])
        }
        // JPEG candidates still need a complete start/end pair and successful ImageIO decode.
        return bytes.count >= 4 && bytes.starts(with: [255, 216]) && bytes.suffix(2).elementsEqual([255, 217])
    }

    static func looksLikeScreenshot(_ data: Data) -> Bool {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = props[kCGImagePropertyPixelWidth] as? Int,
              let height = props[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0 else { return false }
        // Camera optics metadata identifies photos even if resized to phone-like dimensions.
        let exif = props[kCGImagePropertyExifDictionary] as? [CFString: Any]
        guard exif?[kCGImagePropertyExifFNumber] == nil, exif?[kCGImagePropertyExifExposureTime] == nil else { return false }
        let long = max(width, height), short = min(width, height)
        return long >= 800 && long < 3500 && Double(long) / Double(short) >= 1.5
    }
}
