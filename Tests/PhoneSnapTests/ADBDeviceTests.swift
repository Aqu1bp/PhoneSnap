import XCTest
@testable import PhoneSnap

final class ADBDeviceTests: XCTestCase {
    func testParsesReadyDeviceAndFriendlyModel() {
        let output = """
        List of devices attached
        1234567890ABCDEF device product:husky_beta model:Pixel_8_Pro device:husky transport_id:4

        """

        let devices = ADBDeviceListParser.parse(output)

        XCTAssertEqual(devices.count, 1)
        XCTAssertEqual(devices[0].serial, "1234567890ABCDEF")
        XCTAssertEqual(devices[0].connectionState, .ready)
        XCTAssertEqual(devices[0].model, "Pixel_8_Pro")
        XCTAssertEqual(devices[0].displayName, "Pixel 8 Pro")
        XCTAssertEqual(devices[0].transportID, "4")
        XCTAssertEqual(devices[0].serialSuffix, "CDEF")
    }

    func testParsesUnauthorizedOfflineAndNetworkDevices() {
        let output = """
        List of devices attached
        R5CT123456 unauthorized usb:1-2 transport_id:1
        emulator-5554 offline transport_id:2
        192.168.1.44:37123 device product:panther model:Pixel_7 device:panther transport_id:3
        """

        let devices = ADBDeviceListParser.parse(output)

        XCTAssertEqual(devices.map(\.connectionState), [.unauthorized, .offline, .ready])
        XCTAssertEqual(devices[2].serial, "192.168.1.44:37123")
        XCTAssertEqual(devices[2].displayName, "Pixel 7")
    }

    func testIgnoresHeadersBlankLinesAndDaemonMessages() {
        let output = """
        * daemon not running; starting now at tcp:5037
        * daemon started successfully
        List of devices attached

        """

        XCTAssertTrue(ADBDeviceListParser.parse(output).isEmpty)
    }

    func testPreservesUnknownConnectionState() {
        let devices = ADBDeviceListParser.parse("SERIAL recovery product:test\n")
        XCTAssertEqual(devices.first?.connectionState, .other("recovery"))
    }
}

final class ADBExecutableResolverTests: XCTestCase {
    private let home = URL(fileURLWithPath: "/Users/tester", isDirectory: true)

    func testExplicitOverrideHasHighestPriorityAndExpandsTilde() {
        let expected = "/Users/tester/custom/adb"
        let resolved = ADBExecutableResolver.resolve(
            environment: [
                "PHONESNAP_ADB_PATH": "~/custom/adb",
                "ANDROID_SDK_ROOT": "/sdk",
                "PATH": "/bin"
            ],
            homeDirectory: home,
            isExecutable: { $0.path == expected }
        )
        XCTAssertEqual(resolved?.path, expected)
    }

    func testUsesAndroidSDKRootBeforePath() {
        let candidates = ["/sdk/platform-tools/adb", "/path/adb"]
        let resolved = ADBExecutableResolver.resolve(
            environment: ["ANDROID_SDK_ROOT": "/sdk", "PATH": "/path"],
            homeDirectory: home,
            isExecutable: { candidates.contains($0.path) }
        )
        XCTAssertEqual(resolved?.path, "/sdk/platform-tools/adb")
    }

    func testFindsDefaultAndroidStudioSDKForGUIApps() {
        let expected = "/Users/tester/Library/Android/sdk/platform-tools/adb"
        let resolved = ADBExecutableResolver.resolve(
            environment: [:],
            homeDirectory: home,
            isExecutable: { $0.path == expected }
        )
        XCTAssertEqual(resolved?.path, expected)
    }

    func testReturnsNilWhenNoCandidateIsExecutable() {
        XCTAssertNil(ADBExecutableResolver.resolve(
            environment: [:],
            homeDirectory: home,
            isExecutable: { _ in false }
        ))
    }
}
