import Foundation
import SystemConfiguration

/// Returns the Bonjour-safe local hostname for this Mac (e.g.
/// "Aquibs-MacBook-Pro" — dashes for spaces, ASCII-safe). Append `.local`
/// to get the full mDNS-resolvable URL.
///
/// `Host.current().localizedName` returns the human-readable name like
/// "Aquib's MacBook Pro" which contains spaces and a curly apostrophe —
/// not a valid hostname, and not what the iPhone uses to resolve the Mac
/// over mDNS. The system's `LocalHostName` key, surfaced via
/// `SCDynamicStoreCopyLocalHostName`, is what shows up in Bonjour as the
/// Mac's identity. Same value as `scutil --get LocalHostName`.
enum LocalHostName {
    static func current() -> String {
        if let cf = SCDynamicStoreCopyLocalHostName(nil) {
            return cf as String
        }
        // Fallback: process hostname stripped of any .local suffix.
        var raw = ProcessInfo.processInfo.hostName
        if raw.hasSuffix(".local") { raw.removeLast(".local".count) }
        return raw.isEmpty ? "mac" : raw
    }

    /// Full `<hostname>.local` form suitable for use in URLs.
    static func mdnsHostname() -> String {
        "\(current()).local"
    }
}
