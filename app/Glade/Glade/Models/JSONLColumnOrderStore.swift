import Foundation
import Observation

/// One app-wide preference store, shared by every file and window. Only property
/// names and their order are persisted; document paths and values are not stored.
@Observable
final class JSONLColumnOrderStore {
    static let shared = JSONLColumnOrderStore()
    static let storageKey = "JSONColumnOrders"

    @ObservationIgnored private let defaults: UserDefaults
    private var orders: [String: [String]]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.orders = Self.readOrders(from: defaults)
    }

    func columns(for defaults: [JSONLTableColumn]) -> [JSONLTableColumn] {
        guard let saved = savedOrder(for: defaults) else { return defaults }
        return defaults.filter { $0 == .lineNumber }
            + saved.map(JSONLTableColumn.field)
            + defaults.filter { $0 == .value }
    }

    func hasSavedOrder(for columns: [JSONLTableColumn]) -> Bool {
        savedOrder(for: columns) != nil
    }

    func save(_ reordered: [JSONLTableColumn], for schema: [JSONLTableColumn]) {
        let fields = Self.fields(in: reordered)
        let expected = Self.fields(in: schema)
        guard fields.count > 1, fields.count == expected.count,
              Set(fields) == Set(expected), Set(fields).count == fields.count,
              let key = Self.schemaKey(expected) else { return }
        var updated = Self.readOrders(from: defaults)
        updated[key] = fields
        defaults.set(updated, forKey: Self.storageKey)
        orders = updated
    }

    func reset(for columns: [JSONLTableColumn]) {
        guard let key = Self.schemaKey(Self.fields(in: columns)) else { return }
        var updated = Self.readOrders(from: defaults)
        updated.removeValue(forKey: key)
        defaults.set(updated, forKey: Self.storageKey)
        orders = updated
    }

    private func savedOrder(for columns: [JSONLTableColumn]) -> [String]? {
        let fields = Self.fields(in: columns)
        guard let key = Self.schemaKey(fields), let saved = orders[key],
              saved.count == fields.count, Set(saved) == Set(fields),
              Set(saved).count == saved.count else { return nil }
        return saved
    }

    private static func fields(in columns: [JSONLTableColumn]) -> [String] {
        columns.compactMap {
            if case .field(let key) = $0 { return key }
            return nil
        }
    }

    private static func schemaKey(_ fields: [String]) -> String? {
        // JSON encoding avoids delimiter collisions in arbitrary property names.
        // Sorted keys make file order, inferred ranking, and cell values irrelevant.
        guard let data = try? JSONEncoder().encode(fields.sorted()) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func readOrders(from defaults: UserDefaults) -> [String: [String]] {
        (defaults.dictionary(forKey: storageKey) ?? [:]).compactMapValues { $0 as? [String] }
    }
}
