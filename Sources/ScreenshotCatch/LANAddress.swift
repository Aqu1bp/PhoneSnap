import Foundation
#if canImport(Darwin)
import Darwin
#endif

enum LANAddress {
    static func current() -> String? {
        var ifaddrPtr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddrPtr) == 0, let first = ifaddrPtr else { return nil }
        defer { freeifaddrs(ifaddrPtr) }

        var candidate: String?
        var ptr = first
        while true {
            let interface = ptr.pointee
            let family = interface.ifa_addr.pointee.sa_family
            if family == UInt8(AF_INET) {
                let name = String(cString: interface.ifa_name)
                // Prefer en0/en1 (Wi-Fi/Ethernet), fall back to anything non-loopback.
                if name == "lo0" {
                    if let next = interface.ifa_next { ptr = next; continue } else { break }
                }
                var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                let result = getnameinfo(
                    interface.ifa_addr,
                    socklen_t(interface.ifa_addr.pointee.sa_len),
                    &host, socklen_t(host.count),
                    nil, 0,
                    NI_NUMERICHOST
                )
                if result == 0 {
                    let addr = String(cString: host)
                    if name.hasPrefix("en") {
                        return addr
                    }
                    candidate = candidate ?? addr
                }
            }
            if let next = interface.ifa_next { ptr = next } else { break }
        }
        return candidate
    }
}
