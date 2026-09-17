import XCTest
import ImageIO
@testable import PhoneSnap

final class ScreenshotCaptureDateTests: XCTestCase {
    func testHeaderHandlesOffsetsAndFractionalSeconds() throws {
        let utc = try XCTUnwrap(ScreenshotCaptureDate.parseISO8601("2026-09-17T06:00:00Z"))
        let local = try XCTUnwrap(ScreenshotCaptureDate.parseISO8601("2026-09-17T11:30:00.125+05:30"))
        XCTAssertEqual(local.timeIntervalSince(utc), 0.125, accuracy: 0.001)
    }

    func testMissingOrInvalidHeaderDoesNotInventACaptureDate() {
        for value in [nil, "", "not a date", "2026-09-17", String(repeating: "1", count: 100),
                      "2026-09-17T11:30:00.125Zgarbage", "2026-02-30T06:00:00Z",
                      "2026-09-17T11:30:00+99:99", "2026-09-17T11:30:00Z\n"] as [String?] {
            XCTAssertNil(ScreenshotCaptureDate.parseISO8601(value))
        }
    }

    func testReadsOriginalEXIFDateBeforeNormalization() throws {
        let original = try pngWithProperties([
            kCGImagePropertyExifDictionary: [
                kCGImagePropertyExifDateTimeOriginal: "2026:09:17 11:30:00",
                kCGImagePropertyExifOffsetTimeOriginal: "+05:30",
                kCGImagePropertyExifSubsecTimeOriginal: "125"
            ]
        ])
        let expected = try XCTUnwrap(ScreenshotCaptureDate.parseISO8601("2026-09-17T06:00:00.125Z"))
        XCTAssertEqual(try XCTUnwrap(ScreenshotCaptureDate.fromImageData(original)).timeIntervalSince(expected), 0, accuracy: 0.001)

        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let saved = try ImageStore(folder: folder).save(data: original)
        XCTAssertNil(ScreenshotCaptureDate.fromImageData(try Data(contentsOf: saved)),
                     "Saved PNGs have no capture date; sorting must use the original upload")
    }

    func testMissingMetadataAndInvalidImagesHaveNoCaptureDate() {
        XCTAssertNil(ScreenshotCaptureDate.fromImageData(png))
        XCTAssertNil(ScreenshotCaptureDate.fromImageData(Data("not an image".utf8)))
    }

    private func pngWithProperties(_ properties: [CFString: Any]) throws -> Data {
        let source = try XCTUnwrap(CGImageSourceCreateWithData(png as CFData, nil))
        let output = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(output, "public.png" as CFString, 1, nil))
        CGImageDestinationAddImageFromSource(destination, source, 0, properties as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return output as Data
    }

    private let png = Data(base64Encoded:
        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=="
    )!
}
