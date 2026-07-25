import Foundation

/// Whether the wireless receiver should listen.
///
/// New installs start disabled: the receiver is a network service, and a user
/// who only ever captures over the cable should not be running one. Opening
/// the wireless setup window turns it on and the choice persists.
enum WirelessSettings {
    private static let enabledKey = "PhoneSnapWirelessEnabled"
    private static let environmentKey = "PHONESNAP_WIRELESS_ENABLED"

    /// Resolve the effective setting, persisting a value for installs that
    /// predate this preference.
    ///
    /// Must be called *before* `WirelessPairing.load()`, which creates the
    /// pairing keys the migration reads to recognise an existing install.
    static func resolveEnabled(defaults: UserDefaults = AppDefaults.store) -> Bool {
        if let override = environmentOverride() {
            Log.info("Wireless receiver \(override ? "enabled" : "disabled") by \(environmentKey)")
            return override
        }

        if let stored = defaults.object(forKey: enabledKey) as? Bool {
            return stored
        }

        // No stored preference. An existing pairing means this install was
        // already using the receiver before the setting existed — keep it on
        // so a Shortcut already added to someone's iPhone keeps working.
        let inherited = WirelessPairing.exists(defaults: defaults)
        defaults.set(inherited, forKey: enabledKey)
        Log.info("Wireless receiver preference initialised to \(inherited ? "enabled" : "disabled")")
        return inherited
    }

    static func setEnabled(_ enabled: Bool, defaults: UserDefaults = AppDefaults.store) {
        defaults.set(enabled, forKey: enabledKey)
    }

    /// Overrides the stored preference without writing to it, so tests and
    /// `scripts/smoke-test.sh` can drive the receiver directly.
    private static func environmentOverride() -> Bool? {
        guard let raw = ProcessInfo.processInfo.environment[environmentKey]?
            .trimmingCharacters(in: .whitespaces)
            .lowercased(), !raw.isEmpty else { return nil }
        switch raw {
        case "1", "true", "yes": return true
        case "0", "false", "no": return false
        default: return nil
        }
    }
}
