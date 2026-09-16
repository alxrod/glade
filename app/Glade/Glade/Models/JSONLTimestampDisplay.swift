import Foundation

/// Presentation-only timestamp compression, assessed once across the whole file.
/// Original values remain authoritative for search, copying, and the inspector.
enum JSONLTimestampDisplay {
    static func compactCells(in lines: [JSONLLine]) -> [String: [UUID: String]] {
        var columns: [String: [(UUID, Timestamp)]] = [:]
        for line in lines {
            switch line.parsed {
            case .object(let fields):
                for field in fields {
                    if case .string(let text) = field.value, let timestamp = Timestamp(text) {
                        columns[JSONLTableColumn.field(field.key).identifier, default: []].append((line.id, timestamp))
                    }
                }
            case .string(let text):
                if let timestamp = Timestamp(text) {
                    columns[JSONLTableColumn.value.identifier, default: []].append((line.id, timestamp))
                }
            default: break
            }
        }

        var cells: [String: [UUID: String]] = [:]
        for (column, values) in columns {
            guard let first = values.first?.1, values.count > 1,
                  values.allSatisfy({ $0.1.zone == first.zone && $0.1.components.count == first.components.count }) else { continue }
            // Different offsets or precision require their original context. Never
            // make distinct instants look identical by hiding a differing timezone.
            var shared = 0
            while shared < first.components.count,
                  values.allSatisfy({ $0.1.components[shared] == first.components[shared] }) {
                shared += 1
            }
            guard shared > 0 else { continue }
            if shared == first.components.count {
                // Only the fraction varies: preserve its exact digits. Identical
                // timestamps still show a useful clock time instead of a blank cell.
                if first.components.count == 6,
                   values.allSatisfy({ !$0.1.fraction.isEmpty }),
                   values.contains(where: { $0.1.fraction != first.fraction }) {
                    shared = 6
                } else {
                    shared = first.components.count > 3 ? 3 : 0
                }
            }
            guard shared > 0 else { continue }
            cells[column] = Dictionary(uniqueKeysWithValues: values.map { id, timestamp in
                (id, timestamp.display(dropping: shared))
            })
        }
        return cells
    }

    private struct Timestamp {
        let components: [String] // year, month, day, hour, minute, second
        let fraction: String
        let zone: String

        init?(_ text: String) {
            // Accept complete ISO-style dates and clock timestamps, not date-like
            // IDs, paths, prose, or ambiguous numeric epochs. Preserve precision.
            guard text.utf8.count <= 128, let expression = Self.expression,
                  let match = expression.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
                  match.range.length == text.utf16.count else { return nil }
            func group(_ index: Int) -> String {
                guard let range = Range(match.range(at: index), in: text) else { return "" }
                return String(text[range])
            }
            let parts = (1...6).map(group).filter { !$0.isEmpty }
            guard let year = Int(parts[0]), year > 0,
                  let month = Int(parts[1]), (1...12).contains(month),
                  let day = Int(parts[2]) else { return nil }
            let leap = year % 4 == 0 && (year % 100 != 0 || year % 400 == 0)
            let days = [31, leap ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
            guard (1...days[month - 1]).contains(day) else { return nil }
            if parts.count > 3 {
                guard let hour = Int(parts[3]), hour < 24,
                      let minute = Int(parts[4]), minute < 60 else { return nil }
            }
            if parts.count == 6 {
                guard let second = Int(parts[5]), second <= 60 else { return nil }
            }
            let zone = group(8)
            if zone.count > 1 {
                let digits = zone.dropFirst().filter { $0 != ":" }
                guard let hours = Int(digits.prefix(2)), hours < 24,
                      let minutes = Int(digits.suffix(2)), minutes < 60 else { return nil }
            }
            self.components = parts
            self.fraction = group(7).replacingOccurrences(of: ",", with: ".")
            self.zone = zone.uppercased()
        }

        func display(dropping shared: Int) -> String {
            let time = components.dropFirst(3).joined(separator: ":") + fraction
            switch shared {
            case 1:
                return components[1...2].joined(separator: "-") + (time.isEmpty ? "" : " · " + time)
            case 2:
                return String(localized: "Day \(components[2])") + (time.isEmpty ? "" : " · " + time)
            case 3:
                return time
            case 4:
                let seconds = components.count == 6 ? " \(components[5])\(fraction)s" : ""
                return "\(components[4])m" + seconds
            case 5:
                return "\(components[5])\(fraction)s"
            case 6:
                return "\(fraction)s"
            default:
                return components.prefix(3).joined(separator: "-") + (time.isEmpty ? "" : "T" + time) + zone
            }
        }

        private static let expression = try? NSRegularExpression(pattern:
            #"^([0-9]{4})-([0-9]{2})-([0-9]{2})(?:[Tt ]([0-9]{2}):([0-9]{2})(?::([0-9]{2})([.,][0-9]+)?)?(Z|z|[+-][0-9]{2}:?[0-9]{2})?)?$"#)
    }
}
