import Foundation
import SystemConfiguration
#if canImport(Darwin)
import Darwin
#endif

enum LANAddress {
    static func currentIPv4() -> String? {
        var ifaddrPtr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddrPtr) == 0, let first = ifaddrPtr else { return nil }
        defer { freeifaddrs(ifaddrPtr) }

        var candidate: String?
        var ptr = first
        while true {
            let interface = ptr.pointee
            if let addr = interface.ifa_addr,
               addr.pointee.sa_family == UInt8(AF_INET) {
                let name = String(cString: interface.ifa_name)
                if name != "lo0" {
                    var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    let result = getnameinfo(
                        addr,
                        socklen_t(addr.pointee.sa_len),
                        &host,
                        socklen_t(host.count),
                        nil,
                        0,
                        NI_NUMERICHOST
                    )
                    if result == 0 {
                        let address = String(cString: host)
                        if name.hasPrefix("en") {
                            return address
                        }
                        candidate = candidate ?? address
                    }
                }
            }
            guard let next = ptr.pointee.ifa_next else { break }
            ptr = next
        }
        return candidate
    }

    static func bonjourHostName() -> String {
        let raw = SCDynamicStoreCopyLocalHostName(nil)
            .map { $0 as String }
            ?? ProcessInfo.processInfo.hostName
        var host = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if host.isEmpty { host = "localhost" }
        if host.hasSuffix(".local") { return host }
        if host.contains(".") { return host }
        return "\(host.sanitizedBonjourLabel()).local"
    }
}

private extension String {
    func sanitizedBonjourLabel() -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-"))
        var result = ""
        var lastWasDash = false
        for scalar in unicodeScalars {
            if allowed.contains(scalar) {
                result.append(Character(scalar))
                lastWasDash = false
            } else if !lastWasDash {
                result.append("-")
                lastWasDash = true
            }
        }
        let trimmed = result.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return trimmed.isEmpty ? "localhost" : trimmed
    }
}
