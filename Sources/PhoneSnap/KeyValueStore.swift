import Foundation

/// The slice of `UserDefaults` PhoneSnap's settings actually use.
///
/// Depending on this rather than on `UserDefaults` directly lets tests supply
/// an in-memory store. Tests that touch real preferences either overwrite the
/// developer's own settings, or — once pointed at a throwaway suite — leave a
/// trail of empty plists in ~/Library/Preferences, because cfprefsd recreates
/// the file asynchronously after the domain is removed.
protocol KeyValueStore: AnyObject {
    func string(forKey defaultName: String) -> String?
    func object(forKey defaultName: String) -> Any?
    func set(_ value: Any?, forKey defaultName: String)
    func removeObject(forKey defaultName: String)
    @discardableResult
    func synchronize() -> Bool
}

extension UserDefaults: KeyValueStore {}
