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
                return true
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
            imageHandler: { _, _ in
                XCTFail("Invalid PNG must not be delivered")
                return false
            }
        )

        bridge.start()
        wait(for: [discovered], timeout: 2)
        bridge.capture(serial: "SERIAL1234")
        wait(for: [failed], timeout: 2)
        bridge.stop()
    }

    func testSaveFailureIsReportedInsteadOfPublishingIdle() {
        let failed = expectation(description: "delivery failure snapshot")
        let discovered = expectation(description: "device discovered")
        discovered.assertForOverFulfill = false
        let runner = FakeADBRunner { arguments in
            if arguments == ["devices", "-l"] { return .success(Self.deviceListResult) }
            return .success(ADBCommandResult(
                standardOutput: Self.pngData,
                standardError: Data(),
                exitCode: 0
            ))
        }
        let bridge = AndroidADBBridge(
            runner: runner,
            resolveExecutable: { self.executable },
            pollInterval: 60,
            snapshotHandler: { snapshot in
                if snapshot.activity == .idle { discovered.fulfill() }
                if case .failed(let message) = snapshot.activity,
                   message.contains("could not be saved") {
                    XCTAssertTrue(snapshot.hasCurrentReadyDevice)
                    failed.fulfill()
                }
            },
            imageHandler: { _, _ in false }
        )

        bridge.start()
        wait(for: [discovered], timeout: 2)
        bridge.capture(serial: "SERIAL1234")
        wait(for: [failed], timeout: 2)
        bridge.stop()
    }

    func testCaptureFailureRemainsVisibleAcrossDevicePolls() {
        let discovered = expectation(description: "device discovered")
        discovered.assertForOverFulfill = false
        let failed = expectation(description: "capture failure")
        failed.assertForOverFulfill = false
        let prematureIdle = expectation(description: "failure was replaced by polling idle")
        prematureIdle.isInverted = true
        let disconnected = expectation(description: "device change published under failure")
        disconnected.assertForOverFulfill = false
        let tracker = FailureTracker()
        let runner = FakeADBRunner { arguments in
            if arguments == ["devices", "-l"] {
                return .success(tracker.hasCaptured ? Self.emptyDeviceListResult : Self.deviceListResult)
            }
            tracker.markCaptured()
            return .success(ADBCommandResult(
                standardOutput: Self.pngData,
                standardError: Data(),
                exitCode: 0
            ))
        }
        let bridge = AndroidADBBridge(
            runner: runner,
            resolveExecutable: { self.executable },
            pollInterval: 0.02,
            snapshotHandler: { snapshot in
                if snapshot.activity == .idle, !tracker.hasFailed {
                    discovered.fulfill()
                }
                if case .failed(let message) = snapshot.activity,
                   message.contains("could not be saved") {
                    tracker.markFailed()
                    failed.fulfill()
                    if snapshot.devices.isEmpty {
                        XCTAssertFalse(snapshot.hasCurrentReadyDevice)
                        disconnected.fulfill()
                    }
                } else if snapshot.activity == .idle, tracker.hasFailed {
                    prematureIdle.fulfill()
                }
            },
            imageHandler: { _, _ in false }
        )

        bridge.start()
        wait(for: [discovered], timeout: 2)
        bridge.capture(serial: "SERIAL1234")
        wait(for: [failed], timeout: 2)
        wait(for: [disconnected], timeout: 2)
        wait(for: [prematureIdle], timeout: 0.2)
        bridge.stop()
    }

    func testCaptureFailureRedactsEveryKnownDeviceSerialFromMenuTitle() {
        let discovered = expectation(description: "devices discovered")
        discovered.assertForOverFulfill = false
        let failed = expectation(description: "redacted capture failure")
        let deviceList = ADBCommandResult(
            standardOutput: Data("""
                List of devices attached
                SERIAL1234 device product:husky model:Pixel_8 device:husky transport_id:1
                OTHER5678 device product:panther model:Pixel_7 device:panther transport_id:2

                """.utf8),
            standardError: Data(),
            exitCode: 0
        )
        let runner = FakeADBRunner { arguments in
            if arguments == ["devices", "-l"] { return .success(deviceList) }
            return .success(ADBCommandResult(
                standardOutput: Data(),
                standardError: Data("error: device 'SERIAL1234' not found while OTHER5678 is offline".utf8),
                exitCode: 1
            ))
        }
        let bridge = AndroidADBBridge(
            runner: runner,
            resolveExecutable: { self.executable },
            pollInterval: 60,
            snapshotHandler: { snapshot in
                if snapshot.activity == .idle, snapshot.readyDevices.count == 2 {
                    discovered.fulfill()
                }
                if case .failed = snapshot.activity {
                    XCTAssertFalse(snapshot.menuTitle.contains("SERIAL1234"))
                    XCTAssertFalse(snapshot.menuTitle.contains("OTHER5678"))
                    XCTAssertTrue(snapshot.menuTitle.contains("[device]"))
                    failed.fulfill()
                }
            },
            imageHandler: { _, _ in
                XCTFail("A failed capture must not be delivered")
                return false
            }
        )

        bridge.start()
        wait(for: [discovered], timeout: 2)
        bridge.capture(serial: "SERIAL1234")
        wait(for: [failed], timeout: 2)
        bridge.stop()
    }

    func testThrownCaptureFailureRedactsKnownDeviceSerialFromMenuTitle() {
        let discovered = expectation(description: "device discovered")
        discovered.assertForOverFulfill = false
        let failed = expectation(description: "thrown capture failure was redacted")
        let runner = FakeADBRunner { arguments in
            if arguments == ["devices", "-l"] { return .success(Self.deviceListResult) }
            return .failure(NSError(
                domain: "AndroidADBBridgeTests",
                code: 1,
                userInfo: [
                    NSLocalizedDescriptionKey: "transport for SERIAL1234 closed unexpectedly"
                ]
            ))
        }
        let bridge = AndroidADBBridge(
            runner: runner,
            resolveExecutable: { self.executable },
            pollInterval: 60,
            snapshotHandler: { snapshot in
                if snapshot.activity == .idle, snapshot.hasCurrentReadyDevice {
                    discovered.fulfill()
                }
                if case .failed = snapshot.activity {
                    XCTAssertFalse(snapshot.menuTitle.contains("SERIAL1234"))
                    XCTAssertTrue(snapshot.menuTitle.contains("[device]"))
                    failed.fulfill()
                }
            },
            imageHandler: { _, _ in
                XCTFail("A failed capture must not be delivered")
                return false
            }
        )

        bridge.start()
        wait(for: [discovered], timeout: 2)
        bridge.capture(serial: "SERIAL1234")
        wait(for: [failed], timeout: 2)
        bridge.stop()
    }

    func testNonzeroDiscoveryClearsPreviouslyReadyDevices() {
        assertDiscoveryFailureClearsPreviouslyReadyDevices(
            secondResult: .success(ADBCommandResult(
                standardOutput: Data(),
                standardError: Data("adb server is unavailable".utf8),
                exitCode: 1
            ))
        )
    }

    func testThrownDiscoveryClearsPreviouslyReadyDevices() {
        assertDiscoveryFailureClearsPreviouslyReadyDevices(secondResult: .failure(TestError.failed))
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
            imageHandler: { _, _ in
                XCTFail("No image expected")
                return false
            }
        )

        bridge.start()
        wait(for: [unavailable], timeout: 2)
        bridge.stop()
    }

    private func assertDiscoveryFailureClearsPreviouslyReadyDevices(
        secondResult: Result<ADBCommandResult, Error>,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let runner = SequencedADBRunner(results: [.success(Self.deviceListResult), secondResult])
        let discovered = expectation(description: "ready device discovered")
        discovered.assertForOverFulfill = false
        let failed = expectation(description: "discovery failure clears devices")
        let bridge = AndroidADBBridge(
            runner: runner,
            resolveExecutable: { self.executable },
            pollInterval: 60,
            snapshotHandler: { snapshot in
                if snapshot.activity == .idle, snapshot.hasCurrentReadyDevice {
                    discovered.fulfill()
                }
                if case .failed = snapshot.activity {
                    XCTAssertTrue(snapshot.devices.isEmpty, file: file, line: line)
                    XCTAssertTrue(snapshot.readyDevices.isEmpty, file: file, line: line)
                    XCTAssertFalse(snapshot.hasCurrentReadyDevice, file: file, line: line)
                    failed.fulfill()
                }
            },
            imageHandler: { _, _ in true }
        )

        bridge.start()
        wait(for: [discovered], timeout: 2)
        bridge.refresh()
        wait(for: [failed], timeout: 2)
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
            imageHandler: { _, _ in true }
        )
    }

    private static let deviceListResult = ADBCommandResult(
        standardOutput: Data("List of devices attached\nSERIAL1234 device product:husky model:Pixel_8 device:husky transport_id:1\n".utf8),
        standardError: Data(),
        exitCode: 0
    )

    private static let emptyDeviceListResult = ADBCommandResult(
        standardOutput: Data("List of devices attached\n\n".utf8),
        standardError: Data(),
        exitCode: 0
    )

    private static let pngData = Data(base64Encoded:
        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=="
    )!
}

private enum TestError: Error { case failed }

private final class FailureTracker: @unchecked Sendable {
    private let lock = NSLock()
    private var failed = false
    private var captured = false

    var hasFailed: Bool {
        lock.lock()
        defer { lock.unlock() }
        return failed
    }

    var hasCaptured: Bool {
        lock.lock()
        defer { lock.unlock() }
        return captured
    }

    func markFailed() {
        lock.lock()
        failed = true
        lock.unlock()
    }

    func markCaptured() {
        lock.lock()
        captured = true
        lock.unlock()
    }
}

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

private final class SequencedADBRunner: ADBCommandRunning, @unchecked Sendable {
    private let lock = NSLock()
    private var results: [Result<ADBCommandResult, Error>]

    init(results: [Result<ADBCommandResult, Error>]) {
        self.results = results
    }

    func run(
        executable: URL,
        arguments: [String],
        timeout: TimeInterval,
        standardOutputLimit: Int,
        standardErrorLimit: Int
    ) throws -> ADBCommandResult {
        lock.lock()
        guard !results.isEmpty else {
            lock.unlock()
            XCTFail("Unexpected extra ADB invocation: \(arguments)")
            throw TestError.failed
        }
        let result = results.removeFirst()
        lock.unlock()
        return try result.get()
    }
}
