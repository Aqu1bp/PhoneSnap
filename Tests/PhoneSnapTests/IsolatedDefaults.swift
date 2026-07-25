import Foundation
import XCTest

/// A throwaway `UserDefaults` suite that leaves nothing behind.
///
/// `removePersistentDomain` drops the contents but `cfprefsd` still leaves an
/// empty plist in ~/Library/Preferences, so a test run that creates a suite
/// per test litters the developer's preferences folder. Removing the file too
/// keeps repeated runs clean.
enum IsolatedDefaults {
    static func make(for testCase: XCTestCase) -> UserDefaults {
        let name = "phonesnap.tests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: name) else {
            preconditionFailure("could not create defaults suite \(name)")
        }
        testCase.addTeardownBlock {
            defaults.removePersistentDomain(forName: name)
            defaults.synchronize()
            CFPreferencesAppSynchronize(name as CFString)
            let plist = FileManager.default
                .homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Preferences/\(name).plist")
            try? FileManager.default.removeItem(at: plist)
            // Best effort, not a guarantee: cfprefsd flushes on its own
            // schedule and recreates some of these empty plists after the test
            // process has exited. Removing them here cuts the residue down but
            // does not eliminate it. The fix that would is to stop unit tests
            // touching UserDefaults at all — inject a key/value store protocol
            // with an in-memory implementation — which is a wider change than
            // this branch should carry.
        }
        return defaults
    }
}
