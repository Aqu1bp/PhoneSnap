import Foundation

/// The preferences store PhoneSnap reads and writes.
///
/// Normally `UserDefaults.standard`. Setting `PHONESNAP_DEFAULTS_SUITE`
/// redirects everything to a named suite instead, which is the only reliable
/// way to isolate a test run: `cfprefsd` resolves preferences by domain, so
/// overriding `HOME` does *not* stop a test from reading and overwriting the
/// developer's real pairing.
enum AppDefaults {
    static let store: KeyValueStore = {
        guard let suite = ProcessInfo.processInfo.environment["PHONESNAP_DEFAULTS_SUITE"]?
            .trimmingCharacters(in: .whitespaces), !suite.isEmpty,
            let isolated = UserDefaults(suiteName: suite) else {
            return UserDefaults.standard
        }
        Log.info("Using isolated defaults suite \(suite)")
        return isolated
    }()
}
