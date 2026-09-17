import Foundation

/// Discovery supplies addresses only. Every candidate must use DirectPhoneConnection's
/// pinned TLS and selected-device identity check; no unverified native fallback exists.
enum PhoneWiFiRoute {
    static func endpoint(phoneID: String, devices: [PhoneDevice], bonjour: DirectPhoneEndpoint?, bonjourOnly: Bool = false) -> DirectPhoneEndpoint? {
        guard !devices.contains(where: { $0.id == phoneID && $0.isUSB }) else { return nil }
        let system = bonjourOnly ? [] : devices.filter { $0.id == phoneID && !$0.isUSB }.compactMap(\.directEndpoint)
        let candidates = system + (bonjour.map { [$0] } ?? [])
        var addresses: [Data] = []
        for address in candidates.flatMap(\.addresses) where !addresses.contains(address) { addresses.append(address) }
        guard !addresses.isEmpty else { return nil }
        return DirectPhoneEndpoint(serviceName: "selected phone", addresses: addresses, txt: [:])
    }
}
