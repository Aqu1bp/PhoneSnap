import Foundation

/// A unique image keeps its first receipt time as a fallback. If the same
/// screen is captured again, its latest known capture determines its position.
struct WirelessScreenshot {
    let fileURL: URL
    private(set) var capturedAt: Date?
    let receivedAt: Date

    init(fileURL: URL, capturedAt: Date?, receivedAt: Date) {
        self.fileURL = fileURL
        self.capturedAt = capturedAt
        self.receivedAt = receivedAt
    }

    var sortDate: Date { capturedAt ?? receivedAt }

    mutating func recordCaptureDate(_ date: Date?) {
        guard let date else { return }
        capturedAt = max(capturedAt ?? date, date)
    }
}

/// Keeps capture chronology independent of upload order and repeated batches.
struct RecentScreenshots {
    private struct Item {
        let fileURL: URL
        let date: Date
    }

    private var items: [Item] = []
    private let limit: Int

    init(limit: Int = 20) {
        self.limit = max(0, limit)
    }

    var fileURLs: [URL] { items.map(\.fileURL) }

    mutating func insert(fileURL: URL, date: Date) {
        items.removeAll { $0.fileURL == fileURL }
        items.append(Item(fileURL: fileURL, date: date))
        items.sort {
            if $0.date != $1.date { return $0.date > $1.date }
            // Equal timestamps must not shuffle when an image is re-sent.
            return $0.fileURL.absoluteString < $1.fileURL.absoluteString
        }
        if items.count > limit { items.removeLast(items.count - limit) }
    }
}
