import Foundation

enum Log {
    static func info(_ message: String) {
        FileHandle.standardError.write(Data("[PhoneSnap] \(message)\n".utf8))
    }
    static func error(_ message: String) {
        FileHandle.standardError.write(Data("[PhoneSnap] ERROR: \(message)\n".utf8))
    }
}
