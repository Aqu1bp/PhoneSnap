import Foundation
import CUsbmuxd

/// One selected phone's existing system pairing. Never persists or logs credentials.
struct PhonePairingRecord {
    let deviceID: String
    let hostID: String
    let systemBUID: String
    let hostCertificate: Data
    let hostPrivateKey: Data
    let deviceCertificate: Data
    let wifiMAC: String?

    init(deviceID: String) throws {
        var bytes: UnsafeMutablePointer<CChar>?
        var length: UInt32 = 0
        guard usbmuxd_read_pair_record(deviceID, &bytes, &length) == 0, let bytes else {
            throw PhoneConnectionError.trustRequired
        }
        defer { free(bytes) }
        guard length > 0, length <= 1024 * 1024,
              let record = try PropertyListSerialization.propertyList(from: Data(bytes: bytes, count: Int(length)), format: nil) as? [String: Any] else { throw PhoneConnectionError.trustRequired }
        try self.init(deviceID: deviceID, values: record)
    }

    init(deviceID: String, values record: [String: Any]) throws {
        guard let hostID = record["HostID"] as? String, !hostID.isEmpty,
              let buid = record["SystemBUID"] as? String, !buid.isEmpty,
              let host = record["HostCertificate"] as? Data,
              let key = record["HostPrivateKey"] as? Data,
              let device = record["DeviceCertificate"] as? Data else { throw PhoneConnectionError.trustRequired }
        self.deviceID = deviceID; self.hostID = hostID; systemBUID = buid
        hostCertificate = host; hostPrivateKey = key; deviceCertificate = device
        wifiMAC = record["WiFiMACAddress"] as? String
    }
}
