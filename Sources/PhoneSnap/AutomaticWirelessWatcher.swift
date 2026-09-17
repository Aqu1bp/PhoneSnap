import Foundation

/// Device I/O and delivery stay on a serial worker. State callbacks run on main.
final class AutomaticWirelessWatcher {
    struct Status: Equatable {
        let text: String
        var connected = false
        var ready = false
    }
    var onStatus: ((Status) -> Void)?
    var onImage: ((Data, String, Date?, String, @escaping () -> Bool) throws -> Bool)?

    private let queue = DispatchQueue(label: "phonesnap.automatic-wireless", qos: .utility)
    private let lock = NSLock()
    private var generation = UUID()
    private var running = false
    private var requestedPhoneID: String?
    private var connection: PhonePhotoConnection?
    private let discovery = DirectPhoneDiscovery()
    private var scheduledPoll: DispatchWorkItem?
    private var connectionStartedAt: TimeInterval?
    private let bonjourOnly = ProcessInfo.processInfo.environment["PHONESNAP_DIRECT_WIFI_ONLY"] == "1"
    private var catalog = AutomaticCaptureCatalog()
    private var selectedID: String?
    private var lastStatus: Status?

    init() {
        discovery.onChange = { [weak self] in
            self?.queue.async { [weak self] in
                guard let self, let target = self.activeTarget() else { return }
                self.schedule(phoneID: target.phoneID, token: target.token, after: 0)
            }
        }
    }

    private func activeTarget() -> (phoneID: String, token: UUID)? {
        lock.lock(); defer { lock.unlock() }
        guard running, let requestedPhoneID else { return nil }
        return (requestedPhoneID, generation)
    }

    private func schedule(phoneID: String, token: UUID, after delay: TimeInterval) {
        scheduledPoll?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.poll(phoneID: phoneID, token: token) }
        scheduledPoll = item
        queue.asyncAfter(deadline: .now() + delay, execute: item)
    }

    func start(phoneID: String) {
        stop()
        discovery.start()
        lock.lock()
        let token = UUID()
        generation = token
        requestedPhoneID = phoneID
        running = true
        lock.unlock()
        queue.async { [weak self] in
            guard let self, self.active(token) else { return }
            if self.selectedID != phoneID { self.catalog = AutomaticCaptureCatalog() }
            self.selectedID = phoneID
            self.connectionStartedAt = ProcessInfo.processInfo.systemUptime
            self.poll(phoneID: phoneID, token: token)
        }
    }

    func stop() {
        lock.lock()
        running = false
        requestedPhoneID = nil
        generation = UUID()
        lock.unlock()
        discovery.stop()
        queue.async { [weak self] in
            self?.scheduledPoll?.cancel(); self?.scheduledPoll = nil
            self?.connection = nil; self?.lastStatus = nil
        }
    }

    func resetCatalog() {
        queue.async { [weak self] in self?.catalog = AutomaticCaptureCatalog() }
    }

    private func active(_ token: UUID) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return running && generation == token
    }

    func devices(completion: @escaping (Result<[PhoneDevice], Error>) -> Void) {
        discovery.start()
        queue.async {
            let result = Result {
                var devices = try PhoneDeviceConnection.devices(resolveNames: true)
                if let id = AutomaticWirelessSettings.phoneID, !devices.contains(where: { $0.id == id }),
                   let pairing = try? PhonePairingRecord(deviceID: id), let endpoint = self.discovery.endpoint(for: pairing) {
                    let name = AppDefaults.store.string(forKey: "PhoneSnapAutomaticWirelessPhoneName") ?? "iPhone"
                    devices.append(PhoneDevice(id: id, name: name, isUSB: false, directEndpoint: endpoint))
                }
                return devices
            }
            DispatchQueue.main.async { completion(result) }
        }
    }

    /// Only this explicit setup action changes a phone preference; no background pairing.
    func enableWiFi(for phone: PhoneDevice, completion: @escaping (Result<Void, Error>) -> Void) {
        queue.async {
            let result = Result {
                if !phone.isUSB {
                    let pairing = try PhonePairingRecord(deviceID: phone.id)
                    guard let endpoint = PhoneWiFiRoute.endpoint(phoneID: phone.id, devices: [phone], bonjour: self.discovery.endpoint(for: pairing)) else {
                        throw PhoneConnectionError.unavailable
                    }
                    _ = try DirectPhoneConnection(endpoint: endpoint, pairing: pairing, isCurrent: { true })
                } else {
                    let connection = try PhoneDeviceConnection(phone: phone)
                    try connection.enableWiFi()
                }
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
        // A discovery wake can precede start's queued catalog initialization.
        guard active(token), selectedID == phoneID else { return }
        var delay = 0.75
        do {
            let devices = try PhoneDeviceConnection.devices()
            if devices.contains(where: { $0.id == phoneID && $0.isUSB }) {
                connection = nil
                publish(Status(text: "Cable connected — unplug to use automatic Wi-Fi"), token: token)
                delay = 3
            } else {
                if connection == nil {
                    let pairing = try PhonePairingRecord(deviceID: phoneID)
                    let endpoint = PhoneWiFiRoute.endpoint(phoneID: phoneID, devices: devices,
                                                          bonjour: discovery.endpoint(for: pairing), bonjourOnly: bonjourOnly)
                    if let endpoint {
                        publish(Status(text: "Connecting to your iPhone over Wi-Fi…"), token: token)
                        let opened = try DirectPhoneConnection(endpoint: endpoint, pairing: pairing, isCurrent: { [weak self] in self?.active(token) == true })
                        try opened.openPhotos(); connection = opened
                        Log.info("Automatic Wi-Fi: connected with verified phone identity")
                    }
                    if connection == nil {
                        publish(Status(text: "Looking for your iPhone on Wi-Fi. Unlock it to reconnect."), token: token)
                        schedule(phoneID: phoneID, token: token, after: 1)
                        return
                    }
                }
                guard let connection, active(token) else { return }
                let paths = try connection.imagePaths(isCurrent: { self.active(token) })
                guard active(token) else { return }
                let baseline = catalog.observe(paths)
                if baseline { Log.info("Automatic Wi-Fi: catalog ready; \(paths.count) existing images skipped") }
                if let started = connectionStartedAt {
                    Log.info("Automatic Wi-Fi: Ready after \(String(format: "%.3f", ProcessInfo.processInfo.systemUptime - started))s")
                    connectionStartedAt = nil
                }
                publish(Status(text: "Ready — take a screenshot on your iPhone", connected: true, ready: true), token: token)
                for path in catalog.due(at: Date()).prefix(4) {
                    guard active(token) else { return }
                    do {
                        let started = Date()
                        let image = try connection.readImage(path, rejectedRevision: catalog.suspendedRevision(for: path), isCurrent: { self.active(token) })
                        let data = image.data
                        guard active(token) else { return }
                        guard CompleteImage.looksLikeScreenshot(data) else { catalog.completed(path); continue }
                        let capturedAt = ScreenshotCaptureDate.fromImageData(data) ?? image.capturedAt
                        let accepted = try image.deliver {
                            try onImage?(data, path, capturedAt, phoneID, { [weak self] in
                                self?.active(token) == true
                            }) ?? false
                        }
                        if accepted {
                            catalog.completed(path)
                            Log.info("Automatic Wi-Fi: screenshot delivered in \(String(format: "%.3f", Date().timeIntervalSince(started)))s")
                        } else { catalog.backOff(path) }
                    } catch PhoneConnectionError.unsupported {
                        catalog.completed(path)
                    } catch PhoneConnectionError.incomplete {
                        catalog.backOff(path)
                    } catch PhoneConnectionError.invalidImage(let revision) {
                        catalog.rejectedImage(path, revision: revision)
                    } catch PhoneConnectionError.unchangedRejectedImage {
                        // Only metadata is read after repeated unchanged validation
                        // failures. A changed revision is downloaded automatically.
                        catalog.retry(path, after: Date().addingTimeInterval(60))
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
            }
        } catch {
            connection = nil
            publish(Status(text: error.localizedDescription), token: token)
            delay = 5
        }
        guard active(token) else { return }
        schedule(phoneID: phoneID, token: token, after: delay)
    }
}
