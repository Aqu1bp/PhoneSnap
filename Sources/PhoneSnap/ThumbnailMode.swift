import Foundation

/// How delivered screenshots are surfaced, for every capture path.
///
/// Wired capture used to be hard-wired to `.latestOnly` and wireless to
/// `.recentStrip`. That split was an accident of the two presenters being
/// written at different times, not a decision — it is a preference now, and
/// it applies to both.
enum ThumbnailMode: String {
    /// One floating thumbnail; a new screenshot replaces the previous one.
    case latestOnly
    /// A strip of recent screenshots that stays up, newest first.
    case recentStrip

    var title: String {
        switch self {
        case .latestOnly: return "Show only the latest screenshot"
        case .recentStrip: return "Keep a strip of recent screenshots"
        }
    }
}

enum ThumbnailSettings {
    private static let modeKey = "PhoneSnapThumbnailMode"

    static func mode(defaults: KeyValueStore = AppDefaults.store) -> ThumbnailMode {
        defaults.string(forKey: modeKey).flatMap(ThumbnailMode.init(rawValue:)) ?? .recentStrip
    }

    static func setMode(_ mode: ThumbnailMode, defaults: KeyValueStore = AppDefaults.store) {
        defaults.set(mode.rawValue, forKey: modeKey)
    }
}
