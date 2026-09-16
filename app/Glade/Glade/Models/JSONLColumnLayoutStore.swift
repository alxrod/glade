import Foundation
import Observation

/// One app-wide preference store, shared by every file and window. Only property
/// names, order, widths, and visibility are persisted; document contents are not.
@Observable
final class JSONLColumnLayoutStore {
    static let shared = JSONLColumnLayoutStore()
    static let storageKey = "JSONColumnOrders"
    static let widthsStorageKey = "JSONColumnWidths"
    static let hiddenStorageKey = "JSONHiddenColumns"

    @ObservationIgnored private let defaults: UserDefaults
    private var orders: [String: [String]]
    private var widths: [String: [String: Double]]
    private var hidden: [String: [String]]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.orders = Self.readOrders(from: defaults)
        self.widths = Self.readWidths(from: defaults)
        self.hidden = Self.readHidden(from: defaults)
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

    func widths(for columns: [JSONLTableColumn]) -> [String: Double] {
        guard let key = JSONLTableColumn.schemaKey(for: columns), let saved = widths[key] else { return [:] }
        return columns.reduce(into: [:]) { result, column in
            if let width = saved[column.identifier], width.isFinite, width > 0 {
                result[column.identifier] = min(column.maximumWidth, max(column.minimumWidth, width))
            }
        }
    }

    func saveWidth(_ width: Double, for column: JSONLTableColumn, in schema: [JSONLTableColumn]) {
        guard width.isFinite, width > 0, schema.contains(column),
              let key = JSONLTableColumn.schemaKey(for: schema) else { return }
        let width = min(column.maximumWidth, max(column.minimumWidth, width))
        guard widths[key]?[column.identifier] != width else { return }
        var updated = Self.readWidths(from: defaults)
        updated[key, default: [:]][column.identifier] = width
        defaults.set(updated, forKey: Self.widthsStorageKey)
        widths = updated
    }

    func hiddenColumns(for schema: [JSONLTableColumn]) -> [JSONLTableColumn] {
        guard let key = JSONLTableColumn.schemaKey(for: schema) else { return [] }
        let identifiers = Set(hidden[key] ?? [])
        return columns(for: schema).filter { $0 != .lineNumber && identifiers.contains($0.identifier) }
    }

    func hide(_ column: JSONLTableColumn, in schema: [JSONLTableColumn]) {
        guard column != .lineNumber, schema.contains(column),
              let key = JSONLTableColumn.schemaKey(for: schema) else { return }
        var updated = Self.readHidden(from: defaults)
        var identifiers = Set(updated[key] ?? [])
        guard identifiers.insert(column.identifier).inserted else { return }
        updated[key] = identifiers.sorted()
        defaults.set(updated, forKey: Self.hiddenStorageKey)
        hidden = updated
    }

    func show(_ column: JSONLTableColumn, in schema: [JSONLTableColumn]) {
        guard let key = JSONLTableColumn.schemaKey(for: schema) else { return }
        var updated = Self.readHidden(from: defaults)
        updated[key] = (updated[key] ?? []).filter { $0 != column.identifier }
        defaults.set(updated, forKey: Self.hiddenStorageKey)
        hidden = updated
    }

    func showAll(in schema: [JSONLTableColumn]) {
        guard let key = JSONLTableColumn.schemaKey(for: schema) else { return }
        var updated = Self.readHidden(from: defaults)
        updated.removeValue(forKey: key)
        defaults.set(updated, forKey: Self.hiddenStorageKey)
        hidden = updated
    }

    func save(_ reordered: [JSONLTableColumn], for schema: [JSONLTableColumn]) {
        let fields = JSONLTableColumn.fieldKeys(in: reordered)
        let expected = JSONLTableColumn.fieldKeys(in: schema)
        guard fields.count > 1, fields.count == expected.count,
              Set(fields) == Set(expected), Set(fields).count == fields.count,
              let key = JSONLTableColumn.schemaKey(for: schema) else { return }
        var updated = Self.readOrders(from: defaults)
        updated[key] = fields
        defaults.set(updated, forKey: Self.storageKey)
        orders = updated
    }

    func reset(for columns: [JSONLTableColumn]) {
        guard let key = JSONLTableColumn.schemaKey(for: columns) else { return }
        var updated = Self.readOrders(from: defaults)
        updated.removeValue(forKey: key)
        defaults.set(updated, forKey: Self.storageKey)
        orders = updated
    }

    private func savedOrder(for columns: [JSONLTableColumn]) -> [String]? {
        let fields = JSONLTableColumn.fieldKeys(in: columns)
        guard let key = JSONLTableColumn.schemaKey(for: columns), let saved = orders[key],
              saved.count == fields.count, Set(saved) == Set(fields),
              Set(saved).count == saved.count else { return nil }
        return saved
    }

    private static func readOrders(from defaults: UserDefaults) -> [String: [String]] {
        (defaults.dictionary(forKey: storageKey) ?? [:]).compactMapValues { $0 as? [String] }
    }

    private static func readWidths(from defaults: UserDefaults) -> [String: [String: Double]] {
        (defaults.dictionary(forKey: widthsStorageKey) ?? [:]).compactMapValues { $0 as? [String: Double] }
    }

    private static func readHidden(from defaults: UserDefaults) -> [String: [String]] {
        (defaults.dictionary(forKey: hiddenStorageKey) ?? [:]).compactMapValues { $0 as? [String] }
    }
}
