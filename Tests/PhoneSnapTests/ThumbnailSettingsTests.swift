import XCTest
@testable import PhoneSnap

final class ThumbnailSettingsTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "phonesnap.tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
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
