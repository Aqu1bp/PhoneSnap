import Foundation

/// Read-only AFC operations used by the direct transport. No write/delete operations exist here.
enum AFCFrame {
    static let magic = Data("CFA6LPAA".utf8)
    static let maxPayload = 4 * 1024 * 1024

    static func number(_ value: UInt64) -> Data {
        var little = value.littleEndian
        return withUnsafeBytes(of: &little) { Data($0) }
    }

    static func integer(_ data: Data, at offset: Int = 0) throws -> UInt64 {
        guard offset >= 0, offset <= data.count - 8 else { throw PhoneConnectionError.transportLost(-1) }
        return data.dropFirst(offset).prefix(8).enumerated().reduce(UInt64(0)) { $0 | (UInt64($1.element) << ($1.offset * 8)) }
    }

    static func request(sequence: UInt64, operation: UInt64, payload: Data) -> Data {
        let length = UInt64(40 + payload.count)
        return magic + number(length) + number(length) + number(sequence) + number(operation) + payload
    }

    static func responseHeader(_ data: Data, sequence: UInt64) throws -> (length: Int, operation: UInt64) {
        guard data.count == 40, data.prefix(8) == magic else { throw PhoneConnectionError.transportLost(-1) }
        let entire = try integer(data, at: 8), current = try integer(data, at: 16)
        guard entire >= 40, entire <= UInt64(40 + maxPayload), current >= 40, current <= entire,
              try integer(data, at: 24) == sequence else { throw PhoneConnectionError.transportLost(-1) }
        return (Int(entire - 40), try integer(data, at: 32))
    }

    static func strings(_ data: Data) throws -> [String] {
        guard data.isEmpty || data.last == 0 else { throw PhoneConnectionError.transportLost(-1) }
        return try data.split(separator: 0).map {
            guard let value = String(data: $0, encoding: .utf8) else { throw PhoneConnectionError.transportLost(-1) }
            return value
        }
    }
}

/// Connects only to a candidate matching the selected pairing, then pins TLS identity.
/// Serialized with the native path; it never pairs, writes settings, or modifies photos.
final class DirectPhoneConnection: PhonePhotoConnection {
    private let pairing: PhonePairingRecord
    private let address: Data
    private let isCurrent: () -> Bool
    private var lockdown: DirectPhoneSocket?
    private var afc: DirectPhoneSocket?
    private var sequence: UInt64 = 0
    private(set) var photosUseTLS = false

    init(endpoint: DirectPhoneEndpoint, pairing: PhonePairingRecord, lockdownPort: UInt16 = 62078, isCurrent: @escaping () -> Bool) throws {
        self.pairing = pairing; self.isCurrent = isCurrent
        var selected: (Data, DirectPhoneSocket)?
        var lastError: Error = PhoneConnectionError.unavailable
        let deadline = ProcessInfo.processInfo.systemUptime + 12
        for candidate in endpoint.addresses.prefix(3) {
            guard isCurrent() else { throw PhoneConnectionError.cancelled }
            guard ProcessInfo.processInfo.systemUptime < deadline else { break }
            do {
                // The advertised port can be RemotePairing; classic lockdown remains 62078.
                let socket = try DirectPhoneSocket(address: candidate, port: lockdownPort, deadline: deadline, isCurrent: isCurrent)
                let session = try socket.plist(["Request": "StartSession", "Label": "PhoneSnap",
                                               "HostID": pairing.hostID, "SystemBUID": pairing.systemBUID], deadline: deadline)
                guard session["EnableSessionSSL"] as? Bool == true else { throw PhoneConnectionError.secureWiFiRequired }
                try socket.startTLS(pairing, deadline: deadline)
                let identity = try socket.plist(["Request": "GetValue", "Key": "UniqueDeviceID", "Label": "PhoneSnap"], deadline: deadline)
                guard identity["Value"] as? String == pairing.deviceID else { throw PhoneConnectionError.trustRequired }
                selected = (candidate, socket); break
            } catch { lastError = error }
        }
        guard let selected else { throw lastError }
        address = selected.0; lockdown = selected.1
    }

    func openPhotos() throws {
        guard let lockdown else { throw PhoneConnectionError.unavailable }
        let deadline = ProcessInfo.processInfo.systemUptime + 12
        let reply = try lockdown.plist(["Request": "StartService", "Service": "com.apple.afc", "Label": "PhoneSnap"], deadline: deadline)
        guard let rawPort = reply["Port"] as? Int, let port = UInt16(exactly: rawPort), port > 0 else {
            throw PhoneConnectionError.transportLost(-1)
        }
        // Authenticating lockdown is insufficient if photo bytes use a separate,
        // unauthenticated socket. Reject a service that cannot verify its peer.
        guard reply["EnableServiceSSL"] as? Bool == true else { throw PhoneConnectionError.secureWiFiRequired }
        let socket = try DirectPhoneSocket(address: address, port: port, deadline: deadline, isCurrent: isCurrent)
        try socket.startTLS(pairing, deadline: deadline)
        photosUseTLS = true
        afc = socket; self.lockdown = nil
        Log.info("Automatic Wi-Fi: direct photo connection opened; service TLS \(photosUseTLS ? "enabled" : "not requested by iPhone")")
    }

    private func pathData(_ path: String) throws -> Data {
        guard (path == "/DCIM" || path.hasPrefix("/DCIM/")), !path.utf8.contains(0),
              !path.split(separator: "/").contains("..") else { throw PhoneConnectionError.unsupported }
        return Data(path.utf8) + Data([0])
    }

    private func request(_ operation: UInt64, _ payload: Data, expecting: UInt64, deadline: TimeInterval? = nil) throws -> Data {
        do { return try exchange(operation, payload, expecting: expecting, deadline: deadline) }
        catch let error as PhoneConnectionError {
            switch error {
            case .transportLost, .cancelled: afc = nil
            default: break
            }
            throw error
        }
    }

    private func exchange(_ operation: UInt64, _ payload: Data, expecting: UInt64, deadline: TimeInterval?) throws -> Data {
        guard isCurrent() else { throw PhoneConnectionError.cancelled }
        guard let afc else { throw PhoneConnectionError.transportLost(-1) }
        let deadline = deadline ?? ProcessInfo.processInfo.systemUptime + 8
        sequence &+= 1
        let header: (length: Int, operation: UInt64)
        let data: Data
        do {
            try afc.write(AFCFrame.request(sequence: sequence, operation: operation, payload: payload), deadline: deadline)
            header = try AFCFrame.responseHeader(afc.read(40, deadline: deadline), sequence: sequence)
            data = try afc.read(header.length, deadline: deadline)
        } catch { self.afc = nil; throw error }
        if header.operation == 1 {
            guard data.count == 8 else { throw PhoneConnectionError.transportLost(-1) }
            let status = try AFCFrame.integer(data)
            if [11, 12, 30, 32].contains(status) { throw PhoneConnectionError.transportLost(Int32(status)) }
            guard status == 0 else {
                if status == 14 { throw PhoneConnectionError.incomplete }
                throw PhoneConnectionError.failed("Reading photo data", Int32(clamping: status))
            }
            guard expecting == 1 else { throw PhoneConnectionError.transportLost(-1) }
            return Data()
        }
        guard header.operation == expecting else { throw PhoneConnectionError.transportLost(-1) }
        return data
    }

    func list(_ path: String) throws -> [String] {
        try AFCFrame.strings(request(3, pathData(path), expecting: 2)).filter { $0 != "." && $0 != ".." && !$0.contains("/") }
    }

    func info(_ path: String) throws -> [String: String] {
        let values = try AFCFrame.strings(request(10, pathData(path), expecting: 2))
        guard values.count.isMultiple(of: 2) else { throw PhoneConnectionError.transportLost(-1) }
        var result: [String: String] = [:]
        for index in stride(from: 0, to: values.count, by: 2) { result[values[index]] = values[index + 1] }
        return result
    }

    func readFile(_ path: String, size: Int, deadline: TimeInterval, isCurrent: () -> Bool) throws -> Data {
        let opened = try request(13, AFCFrame.number(1) + pathData(path), expecting: 14, deadline: deadline) // AFC_FOPEN_RDONLY
        guard opened.count == 8 else { throw PhoneConnectionError.transportLost(-1) }
        let handle = try AFCFrame.integer(opened)
        defer {
            if afc?.isUsable == true, isCurrent(), ProcessInfo.processInfo.systemUptime < deadline {
                if (try? request(20, AFCFrame.number(handle), expecting: 1, deadline: min(deadline, ProcessInfo.processInfo.systemUptime + 1))) == nil { afc = nil }
            } else { afc = nil }
        }
        var data = Data(); data.reserveCapacity(size)
        while data.count < size {
            guard isCurrent() else { throw PhoneConnectionError.cancelled }
            guard ProcessInfo.processInfo.systemUptime < deadline else { throw PhoneConnectionError.incomplete }
            let wanted = min(256 * 1024, size - data.count)
            let chunk = try request(15, AFCFrame.number(handle) + AFCFrame.number(UInt64(wanted)), expecting: 2, deadline: deadline)
            guard !chunk.isEmpty else { throw PhoneConnectionError.incomplete }
            guard chunk.count <= wanted else { afc = nil; throw PhoneConnectionError.transportLost(-1) }
            data.append(chunk)
        }
        return data
    }
}
