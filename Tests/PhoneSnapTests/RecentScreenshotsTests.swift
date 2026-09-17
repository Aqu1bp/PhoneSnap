import XCTest
@testable import PhoneSnap

final class RecentScreenshotsTests: XCTestCase {
    func testTenScreenshotsSortByCaptureDateRegardlessOfUploadOrder() {
        for order in [Array(1...10), Array((1...10).reversed()), [4, 10, 2, 8, 1, 7, 3, 9, 5, 6]] {
            var screenshots = RecentScreenshots()
            for number in order { insert(number, into: &screenshots) }
            XCTAssertEqual(screenshots.fileURLs, (1...10).reversed().map(url))
        }
    }

    func testOverlappingAndInterruptedReplaysDoNotPromoteOlderImages() {
        var screenshots = RecentScreenshots()
        for number in 1...10 { insert(number, into: &screenshots) }
        insert(11, into: &screenshots)
        for number in [3, 9, 2, 10] {
            insert(number, into: &screenshots)
            XCTAssertEqual(screenshots.fileURLs, (1...11).reversed().map(url))
        }
    }

    func testLimitKeepsNewestCapturesEvenWhenOldUploadsArriveLast() {
        var screenshots = RecentScreenshots()
        for number in (1...30).reversed() { insert(number, into: &screenshots) }
        XCTAssertEqual(screenshots.fileURLs, (11...30).reversed().map(url))
        insert(1, into: &screenshots)
        XCTAssertEqual(screenshots.fileURLs, (11...30).reversed().map(url))
    }

    func testEqualDatesKeepDeterministicOrderAcrossReplays() {
        var screenshots = RecentScreenshots()
        for number in [3, 1, 2] { screenshots.insert(fileURL: url(number), date: .distantPast) }
        let expected = screenshots.fileURLs
        for number in [2, 3, 1] {
            screenshots.insert(fileURL: url(number), date: .distantPast)
            XCTAssertEqual(screenshots.fileURLs, expected)
        }
    }

    func testCaptureDateCanReplaceAnUnknownImagesReceiptDate() {
        var screenshots = RecentScreenshots()
        insert(2, into: &screenshots)
        screenshots.insert(fileURL: url(1), date: Date(timeIntervalSince1970: 100))
        XCTAssertEqual(screenshots.fileURLs, [url(1), url(2)])
        insert(1, into: &screenshots)
        XCTAssertEqual(screenshots.fileURLs, [url(2), url(1)])
    }

    func testIdenticalScreenCapturedAgainBecomesNewestWithoutRegressingOnReplay() {
        var screenshot = WirelessScreenshot(fileURL: url(1), capturedAt: nil, receivedAt: Date(timeIntervalSince1970: 100))
        screenshot.recordCaptureDate(nil)
        XCTAssertEqual(screenshot.sortDate, Date(timeIntervalSince1970: 100))
        screenshot.recordCaptureDate(Date(timeIntervalSince1970: 1))
        XCTAssertEqual(screenshot.sortDate, Date(timeIntervalSince1970: 1))

        var screenshots = RecentScreenshots()
        screenshots.insert(fileURL: screenshot.fileURL, date: screenshot.sortDate)
        insert(2, into: &screenshots)
        XCTAssertEqual(screenshots.fileURLs, [url(2), url(1)])
        for captureTime in [3.0, 1.0, 3.0] {
            screenshot.recordCaptureDate(Date(timeIntervalSince1970: captureTime))
            screenshots.insert(fileURL: screenshot.fileURL, date: screenshot.sortDate)
            XCTAssertEqual(screenshots.fileURLs, [url(1), url(2)])
        }
    }

    private func insert(_ number: Int, into screenshots: inout RecentScreenshots) {
        screenshots.insert(fileURL: url(number), date: Date(timeIntervalSince1970: Double(number)))
    }

    private func url(_ number: Int) -> URL {
        URL(fileURLWithPath: "/tmp/screenshot-\(number).png")
    }
}
