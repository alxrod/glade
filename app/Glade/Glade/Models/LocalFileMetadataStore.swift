import Foundation
import Observation

enum JSONLRowTagColor: String, Codable, CaseIterable {
    case red, orange, yellow, green, teal, blue, purple, gray

    var title: String {
        switch self {
        case .red: return String(localized: "Red")
        case .orange: return String(localized: "Orange")
        case .yellow: return String(localized: "Yellow")
        case .green: return String(localized: "Green")
        case .teal: return String(localized: "Teal")
        case .blue: return String(localized: "Blue")
        case .purple: return String(localized: "Purple")
        case .gray: return String(localized: "Gray")
        }
    }
}

/// Personal annotations belong to an individual file path, never its column schema.
/// Row identities contain a content digest and duplicate occurrence, not JSON contents.
@Observable
final class LocalFileMetadataStore {
    static let shared = LocalFileMetadataStore()
    static let aliasesKey = "FileAliases"
    static let rowTagsKey = "FileRowTags"
    @ObservationIgnored private let defaults: UserDefaults
    private var aliases: [String: String]
    private var tags: [String: [String: String]]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        aliases = Self.readAliases(from: defaults)
        tags = Self.readTags(from: defaults)
    }

    func alias(for url: URL) -> String? { aliases[Self.fileKey(url)] }

    func setAlias(_ alias: String, for url: URL) {
        let alias = alias.trimmingCharacters(in: .whitespacesAndNewlines)
        var updated = Self.readAliases(from: defaults)
        updated[Self.fileKey(url)] = alias.isEmpty ? nil : alias
        defaults.set(updated, forKey: Self.aliasesKey)
        aliases = updated
    }

    func rowTags(for url: URL, lines: [JSONLLine]) -> [UUID: JSONLRowTagColor] {
        guard let saved = tags[Self.fileKey(url)] else { return [:] }
        return lines.reduce(into: [:]) { result, line in
            if let value = saved[line.annotationKey], let color = JSONLRowTagColor(rawValue: value) {
                result[line.id] = color
            }
        }
    }

    func setTag(_ color: JSONLRowTagColor?, for line: JSONLLine, in url: URL) {
        setTag(color, for: [line], in: url)
    }

    func setTag(_ color: JSONLRowTagColor?, for lines: [JSONLLine], in url: URL) {
        guard !lines.isEmpty else { return }
        var updated = Self.readTags(from: defaults)
        let key = Self.fileKey(url)
        var fileTags = updated[key] ?? [:]
        for line in lines { fileTags[line.annotationKey] = color?.rawValue }
        updated[key] = fileTags.isEmpty ? nil : fileTags
        defaults.set(updated, forKey: Self.rowTagsKey)
        tags = updated
    }

    private static func fileKey(_ url: URL) -> String { url.standardizedFileURL.path }

    private static func readAliases(from defaults: UserDefaults) -> [String: String] {
        (defaults.dictionary(forKey: aliasesKey) ?? [:]).compactMapValues {
            guard let alias = $0 as? String, !alias.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            return alias
        }
    }

    private static func readTags(from defaults: UserDefaults) -> [String: [String: String]] {
        (defaults.dictionary(forKey: rowTagsKey) ?? [:]).compactMapValues { $0 as? [String: String] }
    }
}
