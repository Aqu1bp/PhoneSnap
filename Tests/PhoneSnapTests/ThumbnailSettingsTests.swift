import XCTest
@testable import PhoneSnap

final class ThumbnailSettingsTests: XCTestCase {
    private var defaults: InMemoryStore!

    override func setUp() {
        super.setUp()
        defaults = InMemoryStore()
    }

    func testDefaultsToTheRecentStripForEveryCaptureSource() {
        XCTAssertEqual(ThumbnailSettings.mode(defaults: defaults), .recentStrip)
    }

    func testModeRoundTrips() {
        ThumbnailSettings.setMode(.latestOnly, defaults: defaults)
        XCTAssertEqual(ThumbnailSettings.mode(defaults: defaults), .latestOnly)

        ThumbnailSettings.setMode(.recentStrip, defaults: defaults)
        XCTAssertEqual(ThumbnailSettings.mode(defaults: defaults), .recentStrip)
    }

    func testUnrecognisedStoredValueFallsBackInsteadOfCrashing() {
        defaults.set("something-else", forKey: "PhoneSnapThumbnailMode")
        XCTAssertEqual(ThumbnailSettings.mode(defaults: defaults), .recentStrip)
    }
}
