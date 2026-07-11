import XCTest
@testable import PhoneSnap

final class AndroidADBBridgeTests: XCTestCase {
    private let executable = URL(fileURLWithPath: "/test/adb")

    func testDiscoversReadyDevice() {
        let runner = FakeADBRunner { arguments in
            XCTAssertEqual(arguments, ["devices", "-l"])
            return .success(Self.deviceListResult)
        }
        let ready = expectation(description: "ready snapshot")
        ready.assertForOverFulfill = false
        let bridge = makeBridge(runner: runner) { snapshot in
            if snapshot.activity == .idle, snapshot.readyDevices.count == 1 {
                XCTAssertEqual(snapshot.readyDevices.first?.displayName, "Pixel 8")
                XCTAssertEqual(snapshot.menuTitle, "Android: Pixel 8 ready")
                ready.fulfill()
            }
        }

        bridge.start()
        wait(for: [ready], timeout: 2)
        bridge.stop()
    }

    func testCaptureUsesSelectedSerialAndDeliversPNG() {
        let captured = expectation(description: "image delivered")
        let captureArguments = expectation(description: "capture command")
        let runner = FakeADBRunner { arguments in
            if arguments == ["devices", "-l"] {
                return .success(Self.deviceListResult)
            }
            XCTAssertEqual(arguments, ["-s", "SERIAL1234", "exec-out", "screencap", "-p"])
            captureArguments.fulfill()
            return .success(ADBCommandResult(
                standardOutput: Self.pngData,
                standardError: Data(),
                exitCode: 0
            ))
        }
        let discovered = expectation(description: "device discovered")
        discovered.assertForOverFulfill = false
        let bridge = AndroidADBBridge(
            runner: runner,
            resolveExecutable: { self.executable },
            pollInterval: 60,
            snapshotHandler: { snapshot in
                if snapshot.readyDevices.count == 1 { discovered.fulfill() }
            },
            imageHandler: { data, device in
                XCTAssertEqual(data, Self.pngData)
                XCTAssertEqual(device.serial, "SERIAL1234")
                captured.fulfill()
            }
        )

        bridge.start()
        wait(for: [discovered], timeout: 2)
        bridge.capture(serial: "SERIAL1234")
        wait(for: [captureArguments, captured], timeout: 2)
        bridge.stop()
    }

    func testInvalidCaptureDataPublishesFailureWithoutDelivery() {
        let failed = expectation(description: "failure snapshot")
        let discovered = expectation(description: "device discovered")
        discovered.assertForOverFulfill = false
        let runner = FakeADBRunner { arguments in
            if arguments == ["devices", "-l"] { return .success(Self.deviceListResult) }
            return .success(ADBCommandResult(
                standardOutput: Data("not a png".utf8),
                standardError: Data(),
                exitCode: 0
            ))
        }
        let bridge = AndroidADBBridge(
            runner: runner,
            resolveExecutable: { self.executable },
            pollInterval: 60,
            snapshotHandler: { snapshot in
                if snapshot.readyDevices.count == 1 { discovered.fulfill() }
                if case .failed(let message) = snapshot.activity,
                   message.contains("invalid screenshot") {
                    failed.fulfill()
                }
            },
            imageHandler: { _, _ in XCTFail("Invalid PNG must not be delivered") }
        )

        bridge.start()
        wait(for: [discovered], timeout: 2)
        bridge.capture(serial: "SERIAL1234")
        wait(for: [failed], timeout: 2)
        bridge.stop()
    }

    func testUnavailableADBIsNonfatalAndActionable() {
        let unavailable = expectation(description: "unavailable snapshot")
        let bridge = AndroidADBBridge(
            runner: FakeADBRunner { _ in XCTFail("runner should not be called"); return .failure(TestError.failed) },
            resolveExecutable: { nil },
            pollInterval: 60,
            snapshotHandler: { snapshot in
                if snapshot.activity == .idle, !snapshot.adbAvailable {
                    XCTAssertTrue(snapshot.menuTitle.contains("adb not found"))
                    unavailable.fulfill()
                }
            },
            imageHandler: { _, _ in XCTFail("No image expected") }
        )

        bridge.start()
        wait(for: [unavailable], timeout: 2)
        bridge.stop()
    }

    private func makeBridge(
        runner: FakeADBRunner,
        snapshotHandler: @escaping AndroidADBBridge.SnapshotHandler
    ) -> AndroidADBBridge {
        AndroidADBBridge(
            runner: runner,
            resolveExecutable: { self.executable },
            pollInterval: 60,
            snapshotHandler: snapshotHandler,
            imageHandler: { _, _ in }
        )
    }

    private static let deviceListResult = ADBCommandResult(
        standardOutput: Data("List of devices attached\nSERIAL1234 device product:husky model:Pixel_8 device:husky transport_id:1\n".utf8),
        standardError: Data(),
        exitCode: 0
    )

    private static let pngData = Data([
        0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00
    ])
}

private enum TestError: Error { case failed }

private final class FakeADBRunner: ADBCommandRunning, @unchecked Sendable {
    typealias Handler = ([String]) -> Result<ADBCommandResult, Error>
    private let handler: Handler

    init(handler: @escaping Handler) {
        self.handler = handler
    }

    func run(
        executable: URL,
        arguments: [String],
        timeout: TimeInterval,
        standardOutputLimit: Int,
        standardErrorLimit: Int
    ) throws -> ADBCommandResult {
        try handler(arguments).get()
    }
}
