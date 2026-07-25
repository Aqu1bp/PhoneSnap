import XCTest
import AppKit
@testable import PhoneSnap

/// The drag gesture itself needs a real mouse and cannot be exercised here.
/// These lock in the two view properties whose absence broke it: without them
/// a drag on the wired thumbnail moved the panel instead of starting a drag,
/// and the first drag attempt on either panel was swallowed to activate the
/// window.
@MainActor
final class ThumbnailDragTests: XCTestCase {
    private func makeImage() -> NSImage {
        let image = NSImage(size: NSSize(width: 10, height: 10))
        image.lockFocus()
        NSColor.red.drawSwatch(in: NSRect(x: 0, y: 0, width: 10, height: 10))
        image.unlockFocus()
        return image
    }

    private func makeFileURL() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("phonesnap-drag-\(UUID().uuidString).png")
        let data = try XCTUnwrap(
            NSBitmapImageRep(data: makeImage().tiffRepresentation ?? Data())?
                .representation(using: .png, properties: [:])
        )
        try data.write(to: url)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    func testWiredThumbnailDoesNotHandOffItsDragToTheWindow() throws {
        let view = ThumbnailView(
            frame: NSRect(x: 0, y: 0, width: 200, height: 200),
            image: makeImage(),
            fileURL: try makeFileURL(),
            barHeight: 32
        )
        XCTAssertFalse(
            view.mouseDownCanMoveWindow,
            "The panel is movable by its background, so the view must claim the drag itself."
        )
    }

    func testBothThumbnailsAcceptTheFirstClickWhileInactive() throws {
        let wired = ThumbnailView(
            frame: NSRect(x: 0, y: 0, width: 200, height: 200),
            image: makeImage(),
            fileURL: try makeFileURL(),
            barHeight: 32
        )
        let wireless = RecentFromIPhoneThumbnailView(
            image: makeImage(),
            fileURL: try makeFileURL(),
            size: NSSize(width: 120, height: 120)
        )
        let noEvent: NSEvent? = nil
        XCTAssertTrue(wired.acceptsFirstMouse(for: noEvent))
        XCTAssertTrue(wireless.acceptsFirstMouse(for: noEvent))
    }
}
