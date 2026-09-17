import Foundation
import ImageIO

enum ScreenshotCaptureDate {
    static func parseISO8601(_ value: String?) -> Date? {
        guard let value, value.utf8.count <= 64 else { return nil }
        // ISO8601DateFormatter alone accepts trailing text and normalizes
        // impossible dates. An invalid header should use the metadata fallback.
        let pattern = #"[0-9]{4}-(0[1-9]|1[0-2])-(0[1-9]|[12][0-9]|3[01])T([01][0-9]|2[0-3]):[0-5][0-9]:[0-5][0-9](\.[0-9]{1,9})?(Z|[+-]([01][0-9]|2[0-3]):[0-5][0-9])"#
        guard value.range(of: pattern, options: .regularExpression) == value.startIndex..<value.endIndex else { return nil }
        let parts = value.prefix(10).split(separator: "-").compactMap { Int($0) }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let components = DateComponents(year: parts[0], month: parts[1], day: parts[2])
        guard parts[0] > 0, let day = calendar.date(from: components),
              calendar.dateComponents([.year, .month, .day], from: day) == components else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }

    /// Read the original upload, before ImageStore normalizes it to a PNG
    /// without metadata. This also supports previously installed Shortcuts.
    static func fromImageData(_ data: Data) -> Date? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any] else {
            return nil
        }
        if let exif = properties[kCGImagePropertyExifDictionary as String] as? [String: Any],
           let value = exif[kCGImagePropertyExifDateTimeOriginal as String] as? String {
            let offset = exif[kCGImagePropertyExifOffsetTimeOriginal as String] as? String
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.calendar = Calendar(identifier: .gregorian)
            formatter.isLenient = false
            formatter.dateFormat = offset == nil ? "yyyy:MM:dd HH:mm:ss" : "yyyy:MM:dd HH:mm:ssXXXXX"
            if let date = formatter.date(from: value + (offset ?? "")) {
                let subseconds = exif[kCGImagePropertyExifSubsecTimeOriginal as String] as? String
                let fraction = subseconds.flatMap { text -> Double? in
                    guard !text.isEmpty, text.count <= 9,
                          text.utf8.allSatisfy({ (48...57).contains($0) }) else { return nil }
                    return Double("0." + text)
                } ?? 0
                return date.addingTimeInterval(fraction)
            }
        }
        if let png = properties[kCGImagePropertyPNGDictionary as String] as? [String: Any] {
            return parseISO8601(png[kCGImagePropertyPNGCreationTime as String] as? String)
        }
        return nil
    }
}
