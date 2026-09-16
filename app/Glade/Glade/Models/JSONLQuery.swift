import Foundation

struct JSONLQuery: Codable, Equatable {
    var text = ""
    var conditions: [JSONLColumnFilter] = []

    var isActive: Bool { !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !conditions.isEmpty }

    func matches(_ line: JSONLLine) -> Bool {
        let search = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard search.isEmpty || line.rawJSON.range(of: search, options: .caseInsensitive) != nil else { return false }
        return conditions.allSatisfy { $0.matches(line) }
    }

    func hasSameSearch(as other: JSONLQuery) -> Bool {
        text == other.text && conditions.count == other.conditions.count
            && zip(conditions, other.conditions).allSatisfy {
                $0.key == $1.key && $0.operation == $1.operation && $0.value == $1.value
            }
    }
}

struct JSONLColumnFilter: Codable, Equatable, Identifiable {
    enum Operation: String, Codable, CaseIterable {
        case contains
        case equals

        var title: String {
            switch self {
            case .contains: return String(localized: "contains")
            case .equals: return String(localized: "equals")
            }
        }
    }

    var id = UUID()
    var key: String
    var operation: Operation = .contains
    var value = ""

    func matches(_ line: JSONLLine) -> Bool {
        guard case .object(let pairs) = line.parsed,
              let field = pairs.first(where: { $0.key == key })?.value else { return false }
        switch operation {
        case .contains: return Self.contains(field, text: value)
        case .equals: return Self.equals(field, text: value)
        }
    }

    private static func contains(_ value: JSONValue, text: String) -> Bool {
        if text.isEmpty { return true }
        switch value {
        case .object(let pairs):
            return pairs.contains { $0.key.range(of: text, options: .caseInsensitive) != nil || contains($0.value, text: text) }
        case .array(let values): return values.contains { contains($0, text: text) }
        case .string(let string): return string.range(of: text, options: .caseInsensitive) != nil
        default: return value.displayString.range(of: text, options: .caseInsensitive) != nil
        }
    }

    private static func equals(_ value: JSONValue, text: String) -> Bool {
        let literal = text.trimmingCharacters(in: .whitespacesAndNewlines)
        switch value {
        case .string(let string): return string == text
        case .number(let number): return Double(literal) == number
        case .bool(let bool): return literal == (bool ? "true" : "false")
        case .null: return literal == "null"
        case .object, .array:
            guard let data = text.data(using: .utf8),
                  let parsed = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) else { return false }
            return structurallyEqual(value, JSONValue.from(parsed))
        }
    }

    private static func structurallyEqual(_ lhs: JSONValue, _ rhs: JSONValue) -> Bool {
        switch (lhs, rhs) {
        case (.object(let left), .object(let right)):
            return left.count == right.count && left.allSatisfy { pair in
                right.first(where: { $0.key == pair.key }).map { structurallyEqual(pair.value, $0.value) } ?? false
            }
        case (.array(let left), .array(let right)):
            return left.count == right.count && zip(left, right).allSatisfy { structurallyEqual($0, $1) }
        default: return lhs == rhs
        }
    }
}
