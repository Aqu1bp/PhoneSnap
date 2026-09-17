import Foundation
import PhoneTCP

private final class PhoneOperationLifetime {
    let isCurrent: () -> Bool
    init(_ isCurrent: @escaping () -> Bool) { self.isCurrent = isCurrent }
}

/// Used only on the serial device worker. Cancellation never frees a live SSL object.
final class DirectPhoneSocket {
    private let lifetime: PhoneOperationLifetime
    private let tcp: OpaquePointer
    private(set) var isUsable = true

    private static func timeout(_ deadline: TimeInterval?, limit: Int32) throws -> Int32 {
        guard let deadline else { return limit }
        let remaining = (deadline - ProcessInfo.processInfo.systemUptime) * 1000
        guard remaining >= 1 else { throw PhoneConnectionError.transportLost(-1) }
        return Int32(min(Double(limit), remaining))
    }

    init(address: Data, port: UInt16, deadline: TimeInterval? = nil, isCurrent: @escaping () -> Bool) throws {
        lifetime = PhoneOperationLifetime(isCurrent)
        let context = Unmanaged.passUnretained(lifetime).toOpaque()
        let timeout = try Self.timeout(deadline, limit: 4000)
        let opened = address.withUnsafeBytes { bytes in
            phone_tcp_open(bytes.baseAddress, bytes.count, port, timeout, { context in
                guard let context else { return 0 }
                return Unmanaged<PhoneOperationLifetime>.fromOpaque(context).takeUnretainedValue().isCurrent() ? 1 : 0
            }, context)
        }
        guard let opened else { throw PhoneConnectionError.transportLost(-1) }
        tcp = opened
    }

    deinit { phone_tcp_close(tcp) }

    func startTLS(_ pairing: PhonePairingRecord, deadline: TimeInterval? = nil) throws {
        guard isUsable else { throw PhoneConnectionError.transportLost(-1) }
        let timeout = try Self.timeout(deadline, limit: 6000)
        let result = pairing.hostCertificate.withUnsafeBytes { cert in
            pairing.hostPrivateKey.withUnsafeBytes { key in
                pairing.deviceCertificate.withUnsafeBytes { device in
                    phone_tcp_start_tls(tcp, cert.baseAddress, cert.count, key.baseAddress, key.count,
                                        device.baseAddress, device.count, timeout)
                }
            }
        }
        guard result == 0 else { isUsable = false; throw PhoneConnectionError.failed("Verifying the trusted iPhone", result) }
    }

    func write(_ data: Data, deadline: TimeInterval? = nil) throws {
        guard lifetime.isCurrent() else { throw PhoneConnectionError.cancelled }
        guard isUsable else { throw PhoneConnectionError.transportLost(-1) }
        let timeout = try Self.timeout(deadline, limit: 8000)
        let result = data.withUnsafeBytes { phone_tcp_write(tcp, $0.baseAddress, $0.count, timeout) }
        guard result == 0 else { isUsable = false; throw PhoneConnectionError.transportLost(result) }
    }

    func read(_ count: Int, deadline: TimeInterval? = nil) throws -> Data {
        guard lifetime.isCurrent() else { throw PhoneConnectionError.cancelled }
        guard isUsable else { throw PhoneConnectionError.transportLost(-1) }
        guard (0...4 * 1024 * 1024).contains(count) else { throw PhoneConnectionError.transportLost(-1) }
        var data = Data(count: count)
        let timeout = try Self.timeout(deadline, limit: 8000)
        let result = data.withUnsafeMutableBytes { phone_tcp_read(tcp, $0.baseAddress, $0.count, timeout) }
        guard result == 0 else { isUsable = false; throw PhoneConnectionError.transportLost(result) }
        return data
    }

    func plist(_ request: [String: Any], deadline: TimeInterval? = nil) throws -> [String: Any] {
        let deadline = deadline ?? ProcessInfo.processInfo.systemUptime + 8
        let data = try PropertyListSerialization.data(fromPropertyList: request, format: .xml, options: 0)
        var length = UInt32(data.count).bigEndian
        var frame = withUnsafeBytes(of: &length) { Data($0) }; frame.append(data)
        try write(frame, deadline: deadline)
        let header = try read(4, deadline: deadline)
        let size = header.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        guard size > 0, size <= 1024 * 1024 else { throw PhoneConnectionError.transportLost(-1) }
        guard let response = try PropertyListSerialization.propertyList(from: read(Int(size), deadline: deadline), format: nil) as? [String: Any] else {
            throw PhoneConnectionError.transportLost(-1)
        }
        if let error = response["Error"] as? String {
            switch error {
            case "PasswordProtected", "DeviceLocked", "EscrowLocked", "ServiceProhibited": throw PhoneConnectionError.locked
            case "InvalidHostID", "InvalidPairRecord", "PairingDialogResponsePending", "UserDeniedPairing": throw PhoneConnectionError.trustRequired
            default: throw PhoneConnectionError.failed("Opening photo access", -1)
            }
        }
        return response
    }
}
