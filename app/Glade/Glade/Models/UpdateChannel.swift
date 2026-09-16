import Foundation

enum UpdateChannel: String, CaseIterable, Identifiable, Sendable {
    case release
    case beta
    case alpha

    static let storageKey = "UpdateChannel"
    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .release: return String(localized: "Release")
        case .beta: return String(localized: "Beta")
        case .alpha: return String(localized: "Alpha")
        }
    }

    var caption: String {
        switch self {
        case .release: return String(localized: "Stable updates only.")
        case .beta: return String(localized: "Beta and stable updates.")
        case .alpha: return String(localized: "Alpha, beta, and stable updates.")
        }
    }

    // Stable appcast items are untagged and available to every subscriber.
    var sparkleAllowedChannels: Set<String> {
        switch self {
        case .release: return []
        case .beta: return ["beta"]
        case .alpha: return ["beta", "alpha"]
        }
    }

    var stabilityRank: Int {
        switch self {
        case .release: return 2
        case .beta: return 1
        case .alpha: return 0
        }
    }

    static func current(in defaults: UserDefaults = .standard) -> UpdateChannel {
        defaults.string(forKey: storageKey).flatMap(Self.init(rawValue:)) ?? .release
    }

    static func installed(in version: String) -> UpdateChannel {
        let lowercased = version.lowercased()
        if lowercased.contains("-alpha") { return .alpha }
        if lowercased.contains("-beta") { return .beta }
        return .release
    }

    func requiresNewerBuild(than installed: UpdateChannel) -> Bool {
        installed.stabilityRank < stabilityRank
    }
}
