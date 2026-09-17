import XCTest
@testable import PhoneSnap

final class WirelessSettingsTests: XCTestCase {
    private var defaults: InMemoryStore!

    override func setUp() {
        super.setUp()
        defaults = InMemoryStore()
    }

    func testFreshInstallStartsDisabled() {
        XCTAssertFalse(WirelessSettings.resolveEnabled(defaults: defaults))
    }

    /// An install that already provisioned a pairing was using the receiver
    /// before this preference existed. Turning it off underneath such a user
    /// would silently break a Shortcut already added to their iPhone.
    func testInstallWithExistingPairingIsMigratedToEnabled() {
        _ = WirelessPairing.load(defaults: defaults)
        XCTAssertTrue(WirelessSettings.resolveEnabled(defaults: defaults))
    }

    func testMigrationPersistsSoItIsDecidedOnlyOnce() {
        _ = WirelessPairing.load(defaults: defaults)
        XCTAssertTrue(WirelessSettings.resolveEnabled(defaults: defaults))

        // A later rotation that clears the pairing must not re-run the
        // migration and flip a deliberate choice back on.
        WirelessSettings.setEnabled(false, defaults: defaults)
        XCTAssertFalse(WirelessSettings.resolveEnabled(defaults: defaults))
    }

    func testStoredPreferenceIsHonoured() {
        WirelessSettings.setEnabled(true, defaults: defaults)
        XCTAssertTrue(WirelessSettings.resolveEnabled(defaults: defaults))

        WirelessSettings.setEnabled(false, defaults: defaults)
        XCTAssertFalse(WirelessSettings.resolveEnabled(defaults: defaults))
    }

    func testPairingExistenceIsReportedBeforeAndAfterLoad() {
        XCTAssertFalse(WirelessPairing.exists(defaults: defaults))
        _ = WirelessPairing.load(defaults: defaults)
        XCTAssertTrue(WirelessPairing.exists(defaults: defaults))
    }

    func testRotateReplacesBothValues() {
        let original = WirelessPairing.load(defaults: defaults)
        let rotated = WirelessPairing.rotate(defaults: defaults)

        XCTAssertNotEqual(original.pairID, rotated.pairID)
        XCTAssertNotEqual(original.token, rotated.token)
        XCTAssertTrue(WirelessPairing.exists(defaults: defaults))
        XCTAssertEqual(WirelessPairing.load(defaults: defaults).token, rotated.token)
    }
}
