import XCTest
@testable import PhoneSnap

final class ADBProcessRunnerTests: XCTestCase {
    private let runner = ADBProcessRunner()

    func testCapturesStandardOutputAndExitCode() throws {
        let result = try runner.run(
            executable: URL(fileURLWithPath: "/usr/bin/printf"),
            arguments: ["hello"],
            timeout: 2,
            standardOutputLimit: 1024,
            standardErrorLimit: 1024
        )

        XCTAssertEqual(String(data: result.standardOutput, encoding: .utf8), "hello")
        XCTAssertEqual(result.standardError, Data())
        XCTAssertEqual(result.exitCode, 0)
    }

    func testReportsNonzeroExitWithoutThrowing() throws {
        let result = try runner.run(
            executable: URL(fileURLWithPath: "/usr/bin/false"),
            arguments: [],
            timeout: 2,
            standardOutputLimit: 1024,
            standardErrorLimit: 1024
        )

        XCTAssertNotEqual(result.exitCode, 0)
    }

    func testTimesOutHungProcess() {
        XCTAssertThrowsError(try runner.run(
            executable: URL(fileURLWithPath: "/bin/sleep"),
            arguments: ["2"],
            timeout: 0.05,
            standardOutputLimit: 1024,
            standardErrorLimit: 1024
        )) { error in
            guard case ADBCommandError.timedOut = error else {
                return XCTFail("Expected timeout, got \(error)")
            }
        }
    }

    func testRejectsOutputBeyondLimit() {
        XCTAssertThrowsError(try runner.run(
            executable: URL(fileURLWithPath: "/usr/bin/printf"),
            arguments: ["12345"],
            timeout: 2,
            standardOutputLimit: 4,
            standardErrorLimit: 1024
        )) { error in
            guard case ADBCommandError.outputLimitExceeded(let stream, let limit) = error else {
                return XCTFail("Expected output limit failure, got \(error)")
            }
            XCTAssertEqual(stream, "stdout")
            XCTAssertEqual(limit, 4)
        }
    }

    func testAllowsOutputExactlyAtLimit() throws {
        let result = try runner.run(
            executable: URL(fileURLWithPath: "/usr/bin/printf"),
            arguments: ["1234"],
            timeout: 2,
            standardOutputLimit: 4,
            standardErrorLimit: 4
        )
        XCTAssertEqual(result.standardOutput, Data("1234".utf8))
    }

    func testDrainsLargeStandardOutputAndErrorConcurrently() throws {
        let script = "BEGIN { for (i = 0; i < 20000; i++) { print \"stdout-line\"; print \"stderr-line\" > \"/dev/stderr\" } }"
        let result = try runner.run(
            executable: URL(fileURLWithPath: "/usr/bin/awk"),
            arguments: [script],
            timeout: 5,
            standardOutputLimit: 512 * 1024,
            standardErrorLimit: 512 * 1024
        )
        XCTAssertGreaterThan(result.standardOutput.count, 64 * 1024)
        XCTAssertGreaterThan(result.standardError.count, 64 * 1024)
        XCTAssertEqual(result.exitCode, 0)
    }

    func testRejectsStandardErrorBeyondLimit() {
        let script = "BEGIN { for (i = 0; i < 100; i++) print \"stderr-line\" > \"/dev/stderr\" }"
        XCTAssertThrowsError(try runner.run(
            executable: URL(fileURLWithPath: "/usr/bin/awk"),
            arguments: [script],
            timeout: 2,
            standardOutputLimit: 1024,
            standardErrorLimit: 8
        )) { error in
            guard case ADBCommandError.outputLimitExceeded(let stream, _) = error else {
                return XCTFail("Expected stderr limit failure, got \(error)")
            }
            XCTAssertEqual(stream, "stderr")
        }
    }

    func testReportsLaunchFailure() {
        XCTAssertThrowsError(try runner.run(
            executable: URL(fileURLWithPath: "/definitely/missing/adb"),
            arguments: [],
            timeout: 2,
            standardOutputLimit: 1024,
            standardErrorLimit: 1024
        )) { error in
            guard case ADBCommandError.launchFailed = error else {
                return XCTFail("Expected launch failure, got \(error)")
            }
        }
    }
}
