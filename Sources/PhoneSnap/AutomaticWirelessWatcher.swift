import Foundation

/// Device I/O and delivery stay on a serial worker. State callbacks run on main.
final class AutomaticWirelessWatcher {
    struct Status: Equatable {
        let text: String
        var connected = false
        var ready = false
    }
    var onStatus: ((Status) -> Void)?
    var onImage: ((Data, String, Date?, String, @escaping () -> Bool) -> Bool)?

    private let queue = DispatchQueue(label: "phonesnap.automatic-wireless", qos: .utility)
    private let lock = NSLock()
    private var generation = UUID()
    private var running = false
    private var connection: PhoneDeviceConnection?
    private var catalog = AutomaticCaptureCatalog()
    private var selectedID: String?
    private var lastStatus: Status?

    func start(phoneID: String) {
        stop()
        lock.lock()
        let token = UUID()
        generation = token
        running = true
        lock.unlock()
        queue.async { [weak self] in
            guard let self, self.active(token) else { return }
            if self.selectedID != phoneID { self.catalog = AutomaticCaptureCatalog() }
            self.selectedID = phoneID
            self.poll(phoneID: phoneID, token: token)
        }
    }

    func stop() {
        lock.lock()
        running = false
        generation = UUID()
        lock.unlock()
        queue.async { [weak self] in self?.connection = nil; self?.lastStatus = nil }
    }

    func resetCatalog() {
        queue.async { [weak self] in self?.catalog = AutomaticCaptureCatalog() }
    }

    private func active(_ token: UUID) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return running && generation == token
    }

    func devices(completion: @escaping (Result<[PhoneDevice], Error>) -> Void) {
        queue.async {
            let result = Result { try PhoneDeviceConnection.devices(resolveNames: true) }
            DispatchQueue.main.async { completion(result) }
        }
    }

    /// Only this explicit setup action changes a phone preference; no background pairing.
    func enableWiFi(for phone: PhoneDevice, completion: @escaping (Result<Void, Error>) -> Void) {
        queue.async {
            let result = Result {
                let connection = try PhoneDeviceConnection(phone: phone)
                try connection.enableWiFi()
            }
            DispatchQueue.main.async { completion(result) }
        }
    }

    private func publish(_ status: Status, token: UUID) {
        guard status != lastStatus else { return }
        lastStatus = status
        DispatchQueue.main.async { [weak self] in
            guard let self, self.active(token) else { return }
            Log.info("Automatic Wi-Fi: \(status.text)")
            self.onStatus?(status)
        }
    }

    private func poll(phoneID: String, token: UUID) {
        guard active(token) else { return }
        var delay = 0.75
        do {
            let devices = try PhoneDeviceConnection.devices()
            if devices.contains(where: { $0.id == phoneID && $0.isUSB }) {
                connection = nil
                publish(Status(text: "Cable connected — unplug to use automatic Wi-Fi"), token: token)
                delay = 3
            } else if let phone = devices.first(where: { $0.id == phoneID && !$0.isUSB }) {
                if connection == nil {
                    publish(Status(text: "Connecting to your iPhone over Wi-Fi…"), token: token)
                    let opened = try PhoneDeviceConnection(phone: phone)
                    try opened.openPhotos()
                    connection = opened
                }
                guard let connection, active(token) else { return }
                let paths = try connection.imagePaths(isCurrent: { self.active(token) })
                guard active(token) else { return }
                let baseline = catalog.observe(paths)
                if baseline { Log.info("Automatic Wi-Fi: catalog ready; \(paths.count) existing images skipped") }
                publish(Status(text: "Ready — take a screenshot on your iPhone", connected: true, ready: true), token: token)
                for path in catalog.due(at: Date()).prefix(4) {
                    guard active(token) else { return }
                    do {
                        let started = Date()
                        let (data, fallbackDate) = try connection.readImage(path, isCurrent: { self.active(token) })
                        guard active(token) else { return }
                        guard CompleteImage.looksLikeScreenshot(data) else { catalog.completed(path); continue }
                        let capturedAt = ScreenshotCaptureDate.fromImageData(data) ?? fallbackDate
                        let accepted = onImage?(data, path, capturedAt, phoneID, { [weak self] in
                            self?.active(token) == true
                        }) ?? false
                        if accepted {
                            catalog.completed(path)
                            Log.info("Automatic Wi-Fi: screenshot delivered in \(String(format: "%.3f", Date().timeIntervalSince(started)))s")
                        } else { catalog.backOff(path) }
                    } catch PhoneConnectionError.unsupported {
                        catalog.completed(path)
                    } catch PhoneConnectionError.incomplete {
                        catalog.backOff(path)
                    } catch PhoneConnectionError.transportLost(let code) {
                        catalog.backOff(path)
                        throw PhoneConnectionError.transportLost(code)
                    } catch PhoneConnectionError.cancelled {
                        return
                    } catch {
                        // A single unreadable file must not starve later captures.
                        catalog.backOff(path)
                        Log.error("Automatic Wi-Fi: image read deferred: \(error.localizedDescription)")
                    }
                }
            } else {
                connection = nil
                publish(Status(text: "Waiting for your iPhone — same Wi-Fi; unlock to reconnect"), token: token)
                delay = 3
            }
        } catch {
            connection = nil
            publish(Status(text: error.localizedDescription), token: token)
            delay = 5
        }
        guard active(token) else { return }
        queue.asyncAfter(deadline: .now() + delay) { [weak self] in self?.poll(phoneID: phoneID, token: token) }
    }
}
