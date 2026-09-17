import Foundation

/// A baseline is taken before reporting Ready. Reconnects reuse it, including unfinished reads.
struct AutomaticCaptureCatalog {
    private(set) var known: Set<String>?
    private(set) var pending: [String: Date] = [:]
    private var attempts: [String: Int] = [:]

    mutating func observe(_ paths: Set<String>, now: Date = Date()) -> Bool {
        guard let previous = known else { known = paths; return true }
        for path in paths.subtracting(previous) { pending[path] = now }
        pending = pending.filter { paths.contains($0.key) }
        attempts = attempts.filter { pending[$0.key] != nil }
        known = paths
        return false
    }
    mutating func completed(_ path: String) { pending.removeValue(forKey: path); attempts.removeValue(forKey: path) }
    mutating func retry(_ path: String, after date: Date) { if pending[path] != nil { pending[path] = date } }
    mutating func backOff(_ path: String, now: Date = Date()) {
        let attempt = min((attempts[path] ?? 0) + 1, 5)
        attempts[path] = attempt
        retry(path, after: now.addingTimeInterval(min(60, pow(2, Double(attempt)))))
    }
    func due(at date: Date) -> [String] {
        pending.filter { $0.value <= date }.keys.sorted()
    }
}

/// Opt-in is independent from the legacy Shortcut HTTP receiver.
enum AutomaticWirelessSettings {
    static var enabled: Bool { AppDefaults.store.object(forKey: "PhoneSnapAutomaticWirelessEnabled") as? Bool ?? false }
    static var phoneID: String? { AppDefaults.store.string(forKey: "PhoneSnapAutomaticWirelessPhoneID") }
    static func setEnabled(_ enabled: Bool) { AppDefaults.store.set(enabled, forKey: "PhoneSnapAutomaticWirelessEnabled") }
    static func select(_ phone: PhoneDevice) {
        AppDefaults.store.set(phone.id, forKey: "PhoneSnapAutomaticWirelessPhoneID")
        AppDefaults.store.set(phone.name, forKey: "PhoneSnapAutomaticWirelessPhoneName")
    }
}
