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
}
