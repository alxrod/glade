import Foundation

/// Searches the displayed keys and values of one record, preserving original
/// object positions and array indices when hiding unrelated branches.
struct JSONLineSearch {
    let query: String
    private(set) var matchCount = 0
    private var visiblePaths: Set<[Int]> = []

    var isActive: Bool { !query.isEmpty }

    init(line: JSONLLine, query: String) {
        self.query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isActive else { return }
        if let value = line.parsed {
            visit(value, path: [], key: nil, includeSubtree: false)
        } else {
            matchCount = Self.ranges(in: line.rawJSON, query: self.query).count
        }
    }

    init(value: JSONValue, query: String) {
        self.query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isActive else { return }
        visit(value, path: [], key: nil, includeSubtree: false)
    }

    func includes(_ path: [Int]) -> Bool {
        !isActive || visiblePaths.contains(path)
    }

    /// Keep ranges in the original string: case folding can change Unicode
    /// length, so offsets in a lowercased copy cannot safely highlight the source.
    static func ranges(in text: String, query: String) -> [Range<String.Index>] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return [] }
        var ranges: [Range<String.Index>] = []
        var start = text.startIndex
        while start < text.endIndex,
              !Task.isCancelled,
              let range = text.range(of: query, options: .caseInsensitive, range: start..<text.endIndex) {
            guard range.upperBound > start else { break }
            ranges.append(range)
            start = range.upperBound
        }
        return ranges
    }

    @discardableResult
    private mutating func visit(_ value: JSONValue, path: [Int], key: String?, includeSubtree: Bool) -> Bool {
        guard !Task.isCancelled else { return false }
        let keyMatches = key.map { Self.ranges(in: $0, query: query).count } ?? 0
        matchCount += keyMatches
        var hasMatch = keyMatches > 0
        // A matching container key reveals its entire value, including empty
        // collections; descendant matches still contribute to the count.
        let includeChildren = includeSubtree || hasMatch
        switch value {
        case .object(let pairs):
            for (index, pair) in pairs.enumerated() {
                let childMatches = visit(pair.value, path: path + [index], key: pair.key, includeSubtree: includeChildren)
                hasMatch = hasMatch || childMatches
            }
        case .array(let items):
            for (index, item) in items.enumerated() {
                let childMatches = visit(item, path: path + [index], key: nil, includeSubtree: includeChildren)
                hasMatch = hasMatch || childMatches
            }
        default:
            let valueMatches = Self.ranges(in: value.displayString, query: query).count
            matchCount += valueMatches
            hasMatch = hasMatch || valueMatches > 0
        }
        if hasMatch || includeSubtree { visiblePaths.insert(path) }
        return hasMatch
    }
}
