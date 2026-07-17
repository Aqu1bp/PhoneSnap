# complete code
import Foundation

class Log {
    // MARK: - Logging

    static func log(_ message: String) {
        print(message)
    }

    static func logError(_ error: Error) {
        print("Error: \(error.localizedDescription)")
    }
}