import Foundation

final class AndroidADBBridge: @unchecked Sendable {
    struct Snapshot: Equatable, Sendable {
        enum Activity: Equatable, Sendable {
            case stopped
            case checking
            case idle
            case capturing(String)
            case failed(String)
        }

        let activity: Activity
        let adbAvailable: Bool
        let devices: [ADBDevice]

        static let stopped = Snapshot(activity: .stopped, adbAvailable: false, devices: [])

        var readyDevices: [ADBDevice] {
            devices.filter { $0.connectionState == .ready }
        }

        var menuTitle: String {
            switch activity {
            case .stopped:
                return "Android: stopped"
            case .checking:
                return "Android: checking for devices..."
            case .capturing(let name):
                return "Android: capturing \(name)..."
            case .failed(let message):
                return "Android: \(message)"
            case .idle:
                break
            }

            guard adbAvailable else {
                return "Android: adb not found - install Android Platform Tools"
            }
            if readyDevices.count == 1, let device = readyDevices.first {
                return "Android: \(device.displayName) ready"
            }
            if readyDevices.count > 1 {
                return "Android: \(readyDevices.count) devices ready"
            }
            if devices.contains(where: { $0.connectionState == .unauthorized }) {
                return "Android: unlock device and allow USB debugging"
            }
            if devices.contains(where: { $0.connectionState == .offline }) {
                return "Android: device offline - reconnect it"
            }
            if !devices.isEmpty {
                return "Android: no capture-ready device"
            }
            return "Android: no device - enable USB debugging and connect it"
        }
    }

    typealias SnapshotHandler = @Sendable (Snapshot) -> Void
    typealias ImageHandler = @Sendable (Data, ADBDevice) -> Void

    private let queue: DispatchQueue
    private let runner: any ADBCommandRunning
    private let resolveExecutable: @Sendable () -> URL?
    private let snapshotHandler: SnapshotHandler
    private let imageHandler: ImageHandler
    private let pollInterval: TimeInterval
    private let discoveryTimeout: TimeInterval
    private let captureTimeout: TimeInterval

    private var timer: DispatchSourceTimer?
    private var isRunning = false
    private var commandInFlight = false
    private var executable: URL?
    private var devices: [ADBDevice] = []
    private let captureRequestLock = NSLock()
    private var captureRequested = false

    init(
        runner: any ADBCommandRunning = ADBProcessRunner(),
        resolveExecutable: @escaping @Sendable () -> URL? = { ADBExecutableResolver.resolve() },
        pollInterval: TimeInterval = 3,
        discoveryTimeout: TimeInterval = 5,
        captureTimeout: TimeInterval = 15,
        snapshotHandler: @escaping SnapshotHandler,
        imageHandler: @escaping ImageHandler
    ) {
        self.runner = runner
        self.resolveExecutable = resolveExecutable
        self.pollInterval = pollInterval
        self.discoveryTimeout = discoveryTimeout
        self.captureTimeout = captureTimeout
        self.snapshotHandler = snapshotHandler
        self.imageHandler = imageHandler
        self.queue = DispatchQueue(label: "phonesnap.android-adb", qos: .userInitiated)
    }

    func start() {
        queue.async { [weak self] in
            guard let self, !self.isRunning else { return }
            self.isRunning = true
            self.publish(activity: .checking)
            self.pollDevices()

            guard self.isRunning else { return }
            let timer = DispatchSource.makeTimerSource(queue: self.queue)
            timer.schedule(deadline: .now() + self.pollInterval, repeating: self.pollInterval)
            timer.setEventHandler { [weak self] in self?.pollDevices() }
            self.timer = timer
            timer.resume()
        }
    }

    func stop() {
        queue.async { [weak self] in
            guard let self else { return }
            self.isRunning = false
            self.timer?.cancel()
            self.timer = nil
            self.executable = nil
            self.devices = []
            self.publish(activity: .stopped)
        }
    }

    func refresh() {
        queue.async { [weak self] in self?.pollDevices() }
    }

    func capture(serial: String) {
        captureRequestLock.lock()
        guard !captureRequested else {
            captureRequestLock.unlock()
            return
        }
        captureRequested = true
        captureRequestLock.unlock()

        queue.async { [weak self] in
            guard let self else { return }
            defer {
                self.captureRequestLock.lock()
                self.captureRequested = false
                self.captureRequestLock.unlock()
            }
            self.captureOnQueue(serial: serial)
        }
    }

    private func pollDevices() {
        guard isRunning, !commandInFlight else { return }
        commandInFlight = true
        defer { commandInFlight = false }

        guard let executable = executable ?? resolveExecutable() else {
            self.executable = nil
            devices = []
            publish(activity: .idle)
            return
        }
        self.executable = executable
        publish(activity: .checking)

        do {
            let result = try runner.run(
                executable: executable,
                arguments: ["devices", "-l"],
                timeout: discoveryTimeout,
                standardOutputLimit: 512 * 1024,
                standardErrorLimit: 256 * 1024
            )
            guard result.exitCode == 0 else {
                let message = diagnosticMessage(from: result, fallback: "adb device check failed")
                publish(activity: .failed(message))
                return
            }
            let output = String(data: result.standardOutput, encoding: .utf8) ?? ""
            devices = ADBDeviceListParser.parse(output)
            publish(activity: .idle)
        } catch {
            publish(activity: .failed(Self.concise(error.localizedDescription)))
        }
    }

    private func captureOnQueue(serial: String) {
        guard isRunning else { return }
        guard !commandInFlight else {
            publish(activity: .failed("another adb command is already running"))
            return
        }
        guard let executable else {
            publish(activity: .failed("adb is unavailable"))
            return
        }
        guard let device = devices.first(where: {
            $0.serial == serial && $0.connectionState == .ready
        }) else {
            publish(activity: .failed("selected device is no longer available"))
            return
        }

        commandInFlight = true
        publish(activity: .capturing(device.displayName))
        defer {
            commandInFlight = false
        }

        do {
            let result = try runner.run(
                executable: executable,
                arguments: ["-s", serial, "exec-out", "screencap", "-p"],
                timeout: captureTimeout,
                standardOutputLimit: 64 * 1024 * 1024,
                standardErrorLimit: 256 * 1024
            )
            guard result.exitCode == 0 else {
                let message = diagnosticMessage(from: result, fallback: "capture failed")
                publish(activity: .failed(message))
                return
            }
            guard Self.isPNG(result.standardOutput) else {
                publish(activity: .failed("adb returned invalid screenshot data"))
                return
            }

            imageHandler(result.standardOutput, device)
            publish(activity: .idle)
        } catch {
            publish(activity: .failed(Self.concise(error.localizedDescription)))
        }
    }

    private func publish(activity: Snapshot.Activity) {
        snapshotHandler(Snapshot(
            activity: activity,
            adbAvailable: executable != nil,
            devices: devices
        ))
    }

    private func diagnosticMessage(from result: ADBCommandResult, fallback: String) -> String {
        let stderr = String(data: result.standardError, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let stderr, !stderr.isEmpty else { return fallback }
        return Self.concise(stderr)
    }

    private static func concise(_ message: String) -> String {
        let firstLine = message.split(whereSeparator: \Character.isNewline).first.map(String.init) ?? message
        return String(firstLine.prefix(180))
    }

    private static func isPNG(_ data: Data) -> Bool {
        let signature = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        return data.count > signature.count && data.starts(with: signature)
    }
}
