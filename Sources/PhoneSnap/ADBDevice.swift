import Foundation

struct ADBDevice: Equatable, Sendable {
    enum ConnectionState: Equatable, Sendable {
        case ready
        case unauthorized
        case offline
        case other(String)

        init(rawValue: String) {
            switch rawValue {
            case "device": self = .ready
            case "unauthorized": self = .unauthorized
            case "offline": self = .offline
            default: self = .other(rawValue)
            }
        }
    }

    let serial: String
    let connectionState: ConnectionState
    let model: String?
    let product: String?
    let device: String?
    let transportID: String?

    var displayName: String {
        if let model, !model.isEmpty {
            return model.replacingOccurrences(of: "_", with: " ")
        }
        if let device, !device.isEmpty {
            return device.replacingOccurrences(of: "_", with: " ")
        }
        return "Android device"
    }

    /// A short diagnostic suffix that is useful when two devices share a
    /// model name without exposing the full ADB serial in logs or UI.
    var serialSuffix: String {
        String(serial.suffix(4))
    }
}

enum ADBDeviceListParser {
    static func parse(_ output: String) -> [ADBDevice] {
        output
            .split(whereSeparator: \Character.isNewline)
            .compactMap(parseLine)
    }

    private static func parseLine(_ line: Substring) -> ADBDevice? {
        let fields = line.split(whereSeparator: \Character.isWhitespace)
        guard fields.count >= 2 else { return nil }

        let serial = String(fields[0])
        let rawState = String(fields[1])
        guard serial != "List", !serial.hasPrefix("*") else { return nil }

        var properties: [String: String] = [:]
        for field in fields.dropFirst(2) {
            guard let separator = field.firstIndex(of: ":") else { continue }
            let key = String(field[..<separator])
            let value = String(field[field.index(after: separator)...])
            if !key.isEmpty, !value.isEmpty {
                properties[key] = value
            }
        }

        return ADBDevice(
            serial: serial,
            connectionState: .init(rawValue: rawState),
            model: properties["model"],
            product: properties["product"],
            device: properties["device"],
            transportID: properties["transport_id"]
        )
    }
}

enum ADBExecutableResolver {
    static func resolve(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        isExecutable: (URL) -> Bool = { FileManager.default.isExecutableFile(atPath: $0.path) }
    ) -> URL? {
        var candidates: [URL] = []

        if let override = nonEmpty(environment["PHONESNAP_ADB_PATH"]) {
            candidates.append(expand(override, homeDirectory: homeDirectory))
        }

        for key in ["ANDROID_SDK_ROOT", "ANDROID_HOME"] {
            if let root = nonEmpty(environment[key]) {
                candidates.append(
                    expand(root, homeDirectory: homeDirectory)
                        .appendingPathComponent("platform-tools/adb", isDirectory: false)
                )
            }
        }

        candidates.append(
            homeDirectory.appendingPathComponent("Library/Android/sdk/platform-tools/adb", isDirectory: false)
        )

        if let path = nonEmpty(environment["PATH"]) {
            candidates.append(contentsOf: path.split(separator: ":").map {
                URL(fileURLWithPath: String($0), isDirectory: true)
                    .appendingPathComponent("adb", isDirectory: false)
            })
        }

        candidates.append(contentsOf: [
            URL(fileURLWithPath: "/opt/homebrew/bin/adb"),
            URL(fileURLWithPath: "/usr/local/bin/adb")
        ])

        var seen: Set<String> = []
        for candidate in candidates {
            let standardized = candidate.standardizedFileURL
            guard seen.insert(standardized.path).inserted else { continue }
            if isExecutable(standardized) { return standardized }
        }
        return nil
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        return value
    }

    private static func expand(_ path: String, homeDirectory: URL) -> URL {
        if path == "~" { return homeDirectory }
        if path.hasPrefix("~/") {
            return homeDirectory.appendingPathComponent(String(path.dropFirst(2)))
        }
        return URL(fileURLWithPath: path)
    }
}
