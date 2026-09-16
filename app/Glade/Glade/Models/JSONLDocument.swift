import Foundation

struct JSONLDocument {
    let fileURL: URL
    let lines: [JSONLLine]
    let fileName: String
    let tableColumns: [JSONLTableColumn]
    let compactTimestampCells: [String: [UUID: String]]

    var lineCount: Int { lines.count }

    static func parse(from url: URL) throws -> JSONLDocument {
        let content = try String(contentsOf: url, encoding: .utf8)
        return parse(rawContent: content, url: url)
    }

    static func parse(rawContent: String, url: URL) -> JSONLDocument {
        // Split on "\n" and trim whitespace-including-newlines so CRLF (\r\n)
        // and LF files both count one physical line per iteration. Using
        // CharacterSet.newlines here would double-split on \r\n and shift
        // line numbers.
        var lines: [JSONLLine] = []
        var occurrences: [String: Int] = [:]
        var lineNumber = 1
        for raw in rawContent.components(separatedBy: "\n") {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            defer { lineNumber += 1 }
            guard !trimmed.isEmpty else { continue }
            let occurrence = occurrences[trimmed, default: 0]
            occurrences[trimmed] = occurrence + 1
            lines.append(JSONLLine(lineNumber: lineNumber, rawJSON: trimmed, occurrence: occurrence))
        }

        return JSONLDocument(
            fileURL: url,
            lines: lines,
            fileName: url.lastPathComponent,
            tableColumns: JSONLTableColumn.columns(for: lines),
            compactTimestampCells: JSONLTimestampDisplay.compactCells(in: lines)
        )
    }
}

/// The schema comes from the whole file, so filtering never shifts columns.
enum JSONLTableColumn: Equatable {
    case lineNumber
    case field(String)
    case value

    var identifier: String {
        switch self {
        case .lineNumber: return "line-number"
        case .field(let key): return "field:\(key)"
        case .value: return "root-value"
        }
    }

    var title: String {
        switch self {
        case .lineNumber: return String(localized: "Line")
        case .field(let key): return key.isEmpty ? String(localized: "(empty key)") : key
        case .value: return String(localized: "Value / raw content")
        }
    }

    var minimumWidth: Double { self == .lineNumber ? 56 : 90 }
    var defaultWidth: Double { self == .lineNumber ? 64 : (self == .value ? 340 : 180) }
    var maximumWidth: Double { self == .lineNumber ? 120 : 1400 }

    static func columns(for lines: [JSONLLine]) -> [JSONLTableColumn] {
        JSONLColumnOrdering.columns(for: lines)
    }

    static func fieldKeys(in columns: [JSONLTableColumn]) -> [String] {
        columns.compactMap {
            if case .field(let key) = $0 { return key }
            return nil
        }
    }

    static func schemaKey(for columns: [JSONLTableColumn]) -> String? {
        // JSON encoding avoids delimiter collisions; sorting ignores column order.
        guard let data = try? JSONEncoder().encode(fieldKeys(in: columns).sorted()) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func text(for line: JSONLLine) -> String {
        switch self {
        case .lineNumber:
            return line.parseError == nil ? "\(line.lineNumber)" : "⚠ \(line.lineNumber)"
        case .field(let key):
            guard case .object(let pairs) = line.parsed,
                  let value = pairs.first(where: { $0.key == key })?.value else { return "—" }
            return Self.preview(value)
        case .value:
            guard let value = line.parsed else { return Self.compact(line.rawJSON) }
            if case .object = value { return "—" }
            return Self.preview(value)
        }
    }

    private static func preview(_ value: JSONValue) -> String {
        if case .string(let string) = value { return compact(string) }
        return compact(value.displayString)
    }

    private static func compact(_ text: String) -> String {
        let prefix = text.prefix(240)
        return prefix.replacingOccurrences(of: "\n", with: " ↵ ")
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\t", with: " ")
            + (text.dropFirst(240).isEmpty ? "" : "…")
    }
}
