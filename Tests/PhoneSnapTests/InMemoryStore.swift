import Foundation
@testable import PhoneSnap

/// Settings storage that exists only for the lifetime of a test.
///
/// Nothing reaches ~/Library/Preferences, so tests cannot disturb the
/// developer's real pairing and leave no plists behind to clean up.
final class InMemoryStore: KeyValueStore {
    private var storage: [String: Any] = [:]

    func string(forKey defaultName: String) -> String? {
        storage[defaultName] as? String
    }

    func object(forKey defaultName: String) -> Any? {
        storage[defaultName]
    }

    func set(_ value: Any?, forKey defaultName: String) {
        if let value {
            storage[defaultName] = value
        } else {
            storage.removeValue(forKey: defaultName)
        }
    }

    func removeObject(forKey defaultName: String) {
        storage.removeValue(forKey: defaultName)
    }

    @discardableResult
    func synchronize() -> Bool { true }
}
