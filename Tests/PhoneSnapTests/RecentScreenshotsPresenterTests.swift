import XCTest
import AppKit
@testable import PhoneSnap

final class RecentScreenshotsPresenterTests: XCTestCase {
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
        let presenter = RecentScreenshotsPresenter()
        for number in [4, 10, 2, 8, 1, 7, 3, 9, 5, 6] {
            presenter.enqueue(fileURL: urls[number - 1], date: Date(timeIntervalSince1970: Double(number)))
        }
        let panel = try XCTUnwrap(NSApp.windows.first { $0.title == "Recent Screenshots" })
        defer { panel.close() }
        let root = try XCTUnwrap(panel.contentView)
        root.layoutSubtreeIfNeeded()
        let thumbnails = descendants(of: root).compactMap { $0 as? RecentScreenshotThumbnailView }
            .sorted { $0.convert($0.bounds, to: root).minX < $1.convert($1.bounds, to: root).minX }
        XCTAssertEqual(thumbnails.map(\.toolTip), urls.reversed().map { Optional($0.lastPathComponent) })

        for number in [3, 9, 2] {
            presenter.enqueue(fileURL: urls[number - 1], date: Date(timeIntervalSince1970: Double(number)))
            root.layoutSubtreeIfNeeded()
            let replayed = descendants(of: root).compactMap { $0 as? RecentScreenshotThumbnailView }
                .sorted { $0.convert($0.bounds, to: root).minX < $1.convert($1.bounds, to: root).minX }
            XCTAssertEqual(replayed.map(ObjectIdentifier.init), thumbnails.map(ObjectIdentifier.init))
        }

        // The upstream panel's Trash action removes the item from the model;
        // a later capture must not resurrect it while restoring capture order.
        let controller = try XCTUnwrap(panel.delegate as? RecentScreenshotsPanelController)
        controller.onItemRemoved?(urls[5])
        presenter.enqueue(fileURL: urls[0], date: Date(timeIntervalSince1970: 1))
        root.layoutSubtreeIfNeeded()
        let remaining = descendants(of: root).compactMap { $0 as? RecentScreenshotThumbnailView }
            .sorted { $0.convert($0.bounds, to: root).minX < $1.convert($1.bounds, to: root).minX }
        XCTAssertEqual(remaining.map(\.toolTip), urls.reversed().filter { $0 != urls[5] }.map { Optional($0.lastPathComponent) })
    }

    @MainActor
    private func descendants(of view: NSView) -> [NSView] {
        view.subviews.flatMap { [$0] + descendants(of: $0) }
    }
}
