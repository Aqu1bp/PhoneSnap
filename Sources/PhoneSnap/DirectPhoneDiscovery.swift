import Foundation
import CryptoKit
import Darwin

struct DirectPhoneEndpoint: Equatable {
    let serviceName: String
    let addresses: [Data]
    let txt: [String: Data]
}

enum PhoneAdvertisement {
    /// Discovery is candidate selection, not authentication. TLS pins the device later.
    static func matches(name: String, txt: [String: Data], hostID: String, wifiMAC: String?) -> Bool {
        let tags = txt.filter { $0.key == "authTag" || $0.key.hasPrefix("authTag#") }.map(\.value)
        if txt["identifier"] != nil || !tags.isEmpty {
            guard let identifier = txt["identifier"], !identifier.isEmpty, !tags.isEmpty else { return false }
            let key = HKDF<SHA512>.deriveKey(inputKeyMaterial: SymmetricKey(data: Data(hostID.utf8)),
                                            salt: Data(), info: Data(), outputByteCount: 32)
            let expected = Data(HMAC<SHA256>.authenticationCode(for: identifier, using: key).prefix(8))
            return tags.contains { raw in
                guard let value = String(data: raw, encoding: .utf8) else { return false }
                let padded = value + String(repeating: "=", count: (4 - value.count % 4) % 4)
                guard let decoded = Data(base64Encoded: padded), decoded.count == 8 else { return false }
                return decoded == expected
            }
        }
        guard let wifiMAC, !wifiMAC.isEmpty else { return false }
        return name.split(separator: "@", maxSplits: 1).first?.lowercased() == wifiMAC.lowercased()
    }
}

/// NetService delivers on main; the watcher reads immutable snapshots under a lock.
final class DirectPhoneDiscovery: NSObject, NetServiceBrowserDelegate, NetServiceDelegate {
    var onChange: (() -> Void)?
    private let browser = NetServiceBrowser()
    private var services: [NetService] = []
    private var started = false
    private let lock = NSLock()
    private var endpoints: [DirectPhoneEndpoint] = []
    private var generation = UUID()
    private var resolving = Set<ObjectIdentifier>()
    private var lastResolve: [ObjectIdentifier: TimeInterval] = [:]

    override init() { super.init(); browser.delegate = self }

    func start() {
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.started else { return }
            self.started = true
            self.generation = UUID()
            self.browser.searchForServices(ofType: "_apple-mobdev2._tcp.", inDomain: "local.")
            self.refreshLater(self.generation)
        }
    }

    func stop() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.browser.stop()
            self.services.forEach { $0.stopMonitoring(); $0.stop(); $0.delegate = nil }
            self.services.removeAll(); self.started = false
            self.generation = UUID(); self.resolving.removeAll(); self.lastResolve.removeAll()
            self.lock.lock(); self.endpoints.removeAll(); self.lock.unlock()
        }
    }

    func endpoint(for pairing: PhonePairingRecord) -> DirectPhoneEndpoint? {
        lock.lock(); let snapshot = endpoints; lock.unlock()
        return snapshot.first { PhoneAdvertisement.matches(name: $0.serviceName, txt: $0.txt,
                                                            hostID: pairing.hostID, wifiMAC: pairing.wifiMAC) }
    }

    func netServiceBrowser(_ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool) {
        guard started, !services.contains(service) else { return }
        services.append(service); service.delegate = self
        resolve(service)
    }

    func netServiceBrowser(_ browser: NetServiceBrowser, didRemove service: NetService, moreComing: Bool) {
        for existing in services.filter({ $0 == service }) {
            existing.stopMonitoring(); existing.stop(); existing.delegate = nil
            resolving.remove(ObjectIdentifier(existing)); lastResolve[ObjectIdentifier(existing)] = nil
        }
        services.removeAll { $0 == service }
        rebuild()
    }

    func netServiceDidResolveAddress(_ sender: NetService) {
        guard started, services.contains(where: { $0 === sender }) else { return }
        resolving.remove(ObjectIdentifier(sender)); sender.startMonitoring(); rebuild()
    }
    func netService(_ sender: NetService, didNotResolve errorDict: [String: NSNumber]) {
        guard started, services.contains(where: { $0 === sender }) else { return }
        resolving.remove(ObjectIdentifier(sender))
    }
    func netService(_ sender: NetService, didUpdateTXTRecord data: Data) {
        guard started, services.contains(where: { $0 === sender }) else { return }
        rebuild()
    }

    private func resolve(_ service: NetService) {
        let key = ObjectIdentifier(service)
        guard !resolving.contains(key) else { return }
        resolving.insert(key); lastResolve[key] = ProcessInfo.processInfo.systemUptime
        service.resolve(withTimeout: 4)
    }

    private func refreshLater(_ token: UUID) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            guard let self, self.started, self.generation == token else { return }
            for service in self.services {
                let interval: TimeInterval = service.addresses?.isEmpty == false ? 15 : 5
                if ProcessInfo.processInfo.systemUptime - (self.lastResolve[ObjectIdentifier(service)] ?? 0) >= interval {
                    self.resolve(service)
                }
            }
            self.refreshLater(token)
        }
    }

    private func rebuild() {
        let values = services.compactMap { service -> DirectPhoneEndpoint? in
            guard let addresses = service.addresses, !addresses.isEmpty, let txt = service.txtRecordData() else { return nil }
            // Prefer IPv4 when both resolve; IPv6 sockaddr retains its interface scope.
            let sorted = addresses.sorted { ($0.count > 1 && $0[1] == UInt8(AF_INET) ? 0 : 1) < ($1.count > 1 && $1[1] == UInt8(AF_INET) ? 0 : 1) }
            return DirectPhoneEndpoint(serviceName: service.name, addresses: sorted,
                                       txt: NetService.dictionary(fromTXTRecord: txt))
        }
        lock.lock(); let changed = endpoints != values; endpoints = values; lock.unlock()
        if changed { onChange?() }
    }
}
