import XCTest
import AppKit
@testable import PhoneSnap

final class WirelessBatchPresenterTests: XCTestCase {
    @MainActor
    func testPanelPlacesTenCapturesLeftToRightAndReusesViewsDuringReplay() throws {
        _ = NSApplication.shared
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let png = Data(base64Encoded:
            "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=="
        )!
        let urls = try (1...10).map { number -> URL in
            let url = folder.appendingPathComponent("capture-\(number).png")
            try png.write(to: url)
            return url
        }
        let presenter = WirelessBatchPresenter()
        for number in [4, 10, 2, 8, 1, 7, 3, 9, 5, 6] {
            presenter.enqueue(fileURL: urls[number - 1], date: Date(timeIntervalSince1970: Double(number)))
        }
        let panel = try XCTUnwrap(NSApp.windows.first { $0.title == "Recent from iPhone" })
        defer { panel.close() }
        let root = try XCTUnwrap(panel.contentView)
        root.layoutSubtreeIfNeeded()
        let thumbnails = descendants(of: root).compactMap { $0 as? RecentFromIPhoneThumbnailView }
            .sorted { $0.convert($0.bounds, to: root).minX < $1.convert($1.bounds, to: root).minX }
        XCTAssertEqual(thumbnails.map(\.toolTip), urls.reversed().map { Optional($0.lastPathComponent) })

        for number in [3, 9, 2] {
            presenter.enqueue(fileURL: urls[number - 1], date: Date(timeIntervalSince1970: Double(number)))
            root.layoutSubtreeIfNeeded()
            let replayed = descendants(of: root).compactMap { $0 as? RecentFromIPhoneThumbnailView }
                .sorted { $0.convert($0.bounds, to: root).minX < $1.convert($1.bounds, to: root).minX }
            XCTAssertEqual(replayed.map(ObjectIdentifier.init), thumbnails.map(ObjectIdentifier.init))
        }
    }

    @MainActor
    private func descendants(of view: NSView) -> [NSView] {
        view.subviews.flatMap { [$0] + descendants(of: $0) }
    }
}
