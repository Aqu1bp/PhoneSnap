import Foundation
import Darwin

struct ADBCommandResult: Equatable, Sendable {
    let standardOutput: Data
    let standardError: Data
    let exitCode: Int32
}

enum ADBCommandError: LocalizedError {
    case launchFailed(Error)
    case timedOut(TimeInterval)
    case outputLimitExceeded(stream: String, limit: Int)
    case streamReadFailed(stream: String, error: Error)
    case streamDrainTimedOut(String)

    var errorDescription: String? {
        switch self {
        case .launchFailed(let error):
            return "Could not launch adb: \(error.localizedDescription)"
        case .timedOut(let timeout):
            return "adb did not finish within \(Int(timeout)) seconds"
        case .outputLimitExceeded(let stream, let limit):
            return "adb \(stream) exceeded the \(limit)-byte safety limit"
        case .streamReadFailed(let stream, let error):
            return "Could not read adb \(stream): \(error.localizedDescription)"
        case .streamDrainTimedOut(let stream):
            return "Timed out while finishing adb \(stream)"
        }
    }
}

protocol ADBCommandRunning: Sendable {
    func run(
        executable: URL,
        arguments: [String],
        timeout: TimeInterval,
        standardOutputLimit: Int,
        standardErrorLimit: Int
    ) throws -> ADBCommandResult
}

struct ADBProcessRunner: ADBCommandRunning {
    func run(
        executable: URL,
        arguments: [String],
        timeout: TimeInterval,
        standardOutputLimit: Int,
        standardErrorLimit: Int
    ) throws -> ADBCommandResult {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        let exited = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in exited.signal() }

        do {
            try process.run()
        } catch {
            throw ADBCommandError.launchFailed(error)
        }

        // Both streams must be consumed while adb runs. A device screenshot is
        // much larger than a pipe buffer and waiting for exit before reading it
        // can deadlock the child process.
        let stdoutDrain = BoundedPipeDrain(
            fileHandle: stdoutPipe.fileHandleForReading,
            limit: standardOutputLimit
        )
        let stderrDrain = BoundedPipeDrain(
            fileHandle: stderrPipe.fileHandleForReading,
            limit: standardErrorLimit
        )
        stdoutDrain.start()
        stderrDrain.start()

        if exited.wait(timeout: .now() + timeout) == .timedOut {
            process.terminate()
            if exited.wait(timeout: .now() + 1) == .timedOut {
                kill(process.processIdentifier, SIGKILL)
                _ = exited.wait(timeout: .now() + 1)
            }
            _ = stdoutDrain.wait(timeout: .now() + 1)
            _ = stderrDrain.wait(timeout: .now() + 1)
            throw ADBCommandError.timedOut(timeout)
        }

        guard let stdout = stdoutDrain.wait(timeout: .now() + 2) else {
            throw ADBCommandError.streamDrainTimedOut("stdout")
        }
        guard let stderr = stderrDrain.wait(timeout: .now() + 2) else {
            throw ADBCommandError.streamDrainTimedOut("stderr")
        }
        if let error = stdout.readError {
            throw ADBCommandError.streamReadFailed(stream: "stdout", error: error)
        }
        if let error = stderr.readError {
            throw ADBCommandError.streamReadFailed(stream: "stderr", error: error)
        }
        if stdout.exceededLimit {
            throw ADBCommandError.outputLimitExceeded(stream: "stdout", limit: standardOutputLimit)
        }
        if stderr.exceededLimit {
            throw ADBCommandError.outputLimitExceeded(stream: "stderr", limit: standardErrorLimit)
        }

        return ADBCommandResult(
            standardOutput: stdout.data,
            standardError: stderr.data,
            exitCode: process.terminationStatus
        )
    }
}

private final class BoundedPipeDrain: @unchecked Sendable {
    struct Result {
        let data: Data
        let exceededLimit: Bool
        let readError: Error?
    }

    private let fileHandle: FileHandle
    private let limit: Int
    private let finished = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private var result = Result(data: Data(), exceededLimit: false, readError: nil)

    init(fileHandle: FileHandle, limit: Int) {
        self.fileHandle = fileHandle
        self.limit = max(0, limit)
    }

    func start() {
        DispatchQueue.global(qos: .userInitiated).async { [self] in
            var collected = Data()
            var exceeded = false
            var totalBytes = 0
            var readError: Error?
            do {
                while let chunk = try fileHandle.read(upToCount: 64 * 1024),
                      !chunk.isEmpty {
                    totalBytes += chunk.count
                    if collected.count < limit {
                        let remaining = limit - collected.count
                        collected.append(chunk.prefix(remaining))
                    }
                    exceeded = totalBytes > limit
                }
            } catch {
                readError = error
            }
            lock.lock()
            result = Result(data: collected, exceededLimit: exceeded, readError: readError)
            lock.unlock()
            finished.signal()
        }
    }

    func wait(timeout: DispatchTime) -> Result? {
        guard finished.wait(timeout: timeout) == .success else { return nil }
        lock.lock()
        defer { lock.unlock() }
        return result
    }
}
