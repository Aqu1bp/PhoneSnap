import AppKit

enum Pasteboard {
    /// Place a screenshot on the general pasteboard so any app's "Paste" works:
    /// - `public.png` raw PNG bytes (Electron apps, browsers, Slack, Notion, Claude Code, Cursor)
    /// - `public.tiff` (legacy AppKit consumers)
    /// - `public.file-url` (Finder, file-aware text fields)
    /// - `NSStringPboardType` (filename, for plain-text fallback)
    static func write(fileURL: URL) {
        let pb = NSPasteboard.general
        pb.clearContents()
        let item = NSPasteboardItem()

        if let pngData = try? Data(contentsOf: fileURL) {
            item.setData(pngData, forType: .png)
        }
        if let image = NSImage(contentsOf: fileURL),
           let tiff = image.tiffRepresentation {
            item.setData(tiff, forType: .tiff)
        }
        item.setString(fileURL.absoluteString, forType: .fileURL)
        item.setString(fileURL.lastPathComponent, forType: .string)

        let ok = pb.writeObjects([item])
        if !ok {
            Log.error("Pasteboard write returned false")
        }
    }
}
