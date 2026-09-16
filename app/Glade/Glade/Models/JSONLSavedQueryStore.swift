import Foundation
import Observation

struct JSONLSavedQuery: Codable, Equatable, Identifiable {
    var id = UUID()
    var name: String
    var query: JSONLQuery
}

/// Saved searches share the exact same full-document key identity as column layouts.
@Observable
final class JSONLSavedQueryStore {
    static let shared = JSONLSavedQueryStore()
    static let storageKey = "JSONSavedQueries"
    @ObservationIgnored private let defaults: UserDefaults
    private var saved: [String: [JSONLSavedQuery]]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        saved = Self.read(from: defaults)
    }

    func queries(for columns: [JSONLTableColumn]) -> [JSONLSavedQuery] {
        guard let key = JSONLTableColumn.schemaKey(for: columns) else { return [] }
        let fields = Set(JSONLTableColumn.fieldKeys(in: columns))
        return (saved[key] ?? []).filter { !$0.name.isEmpty && $0.query.isActive && $0.query.conditions.allSatisfy { fields.contains($0.key) } }
    }

    func query(named name: String, for columns: [JSONLTableColumn]) -> JSONLSavedQuery? {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return queries(for: columns).first { $0.name.caseInsensitiveCompare(name) == .orderedSame }
    }

    @discardableResult
    func save(name: String, query: JSONLQuery, for columns: [JSONLTableColumn]) -> JSONLSavedQuery? {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let fields = Set(JSONLTableColumn.fieldKeys(in: columns))
        guard !name.isEmpty, query.isActive, query.conditions.allSatisfy({ fields.contains($0.key) }),
              let key = JSONLTableColumn.schemaKey(for: columns) else { return nil }
        var updated = Self.read(from: defaults)
        var queries = updated[key] ?? []
        let existing = queries.firstIndex { $0.name.caseInsensitiveCompare(name) == .orderedSame }
        let entry = JSONLSavedQuery(id: existing.map { queries[$0].id } ?? UUID(), name: name, query: query)
        if let existing { queries[existing] = entry } else { queries.append(entry) }
        updated[key] = queries
        persist(updated)
        return entry
    }

    func delete(_ query: JSONLSavedQuery, for columns: [JSONLTableColumn]) {
        guard let key = JSONLTableColumn.schemaKey(for: columns) else { return }
        var updated = Self.read(from: defaults)
        updated[key] = (updated[key] ?? []).filter { $0.id != query.id }
        persist(updated)
    }

    private func persist(_ updated: [String: [JSONLSavedQuery]]) {
        let encoded = updated.compactMapValues { try? JSONEncoder().encode($0) }
        defaults.set(encoded, forKey: Self.storageKey)
        saved = updated
    }

    private static func read(from defaults: UserDefaults) -> [String: [JSONLSavedQuery]] {
        (defaults.dictionary(forKey: storageKey) ?? [:]).compactMapValues { value in
            guard let data = value as? Data else { return nil }
            return try? JSONDecoder().decode([JSONLSavedQuery].self, from: data)
        }
    }
}
