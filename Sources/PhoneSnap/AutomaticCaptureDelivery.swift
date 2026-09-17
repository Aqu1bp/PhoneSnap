import Foundation
import CryptoKit

/// A shared decision for USB and automatic Wi-Fi. Call only from AppDelegate's delivery queue.
/// Include capture identity so two deliberately identical screenshots are both retained.
struct AutomaticCaptureDelivery {
    private var delivered: [String: Date] = [:]

    static func fingerprint(_ deviceID: String?) -> String {
        guard let deviceID else { return "unavailable" }
        let normalized = deviceID.replacingOccurrences(of: "-", with: "").lowercased()
        return SHA256.hash(data: Data(normalized.utf8)).prefix(6).map { String(format: "%02x", $0) }.joined()
    }

    static func key(deviceID: String?, name: String, capturedAt: Date?, data: Data) -> String {
        let name = (name as NSString).lastPathComponent
        let device = (deviceID ?? "unknown").replacingOccurrences(of: "-", with: "").lowercased()
        if let capturedAt {
            // EXIF creation time is second-resolution on both import paths.
            return "\(device)|\((name as NSString).deletingPathExtension)|\(Int64(capturedAt.timeIntervalSince1970.rounded(.down)))"
        }
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        return "\(device)|\(name)|\(digest)"
    }

    mutating func contains(_ key: String, now: Date = Date()) -> Bool {
        delivered = delivered.filter { now.timeIntervalSince($0.value) < 24 * 3600 }
        return delivered[key] != nil
    }
    mutating func record(_ key: String, now: Date = Date()) { delivered[key] = now }
}
