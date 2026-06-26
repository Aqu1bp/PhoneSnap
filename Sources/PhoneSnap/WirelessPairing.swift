import Foundation
import Security

struct WirelessPairing {
    let pairID: String
    let token: String

    private static let pairIDKey = "PhoneSnapWirelessPairID"
    private static let tokenKey = "PhoneSnapWirelessToken"

    static func load() -> WirelessPairing {
        let defaults = UserDefaults.standard
        let pairID = defaults.string(forKey: pairIDKey).flatMap(nonEmpty)
            ?? randomBase64URL(byteCount: 9)
        let token = defaults.string(forKey: tokenKey).flatMap(nonEmpty)
            ?? randomBase64URL(byteCount: 32)

        defaults.set(pairID, forKey: pairIDKey)
        defaults.set(token, forKey: tokenKey)
        defaults.synchronize()
        return WirelessPairing(pairID: pairID, token: token)
    }

    private static func nonEmpty(_ value: String) -> String? {
        value.isEmpty ? nil : value
    }

    private static func randomBase64URL(byteCount: Int) -> String {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        let status = bytes.withUnsafeMutableBytes { rawBuffer in
            SecRandomCopyBytes(kSecRandomDefault, byteCount, rawBuffer.baseAddress!)
        }
        if status != errSecSuccess {
            return fallbackRandom(byteCount: byteCount)
        }
        return Data(bytes).base64URLEncodedString()
    }

    private static func fallbackRandom(byteCount: Int) -> String {
        let chunks = max(1, Int(ceil(Double(byteCount) / 16.0)))
        let data = (0..<chunks)
            .map { _ in UUID().uuidString.replacingOccurrences(of: "-", with: "") }
            .joined()
        return String(data.prefix(byteCount * 2))
    }
}

extension Data {
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
