import Foundation

/// Assesses a document once at parse time. The line-number gutter stays fixed;
/// data columns use timestamp, content, and occupancy evidence from the file.
enum JSONLColumnOrdering {
    static func columns(for lines: [JSONLLine]) -> [JSONLTableColumn] {
        var profiles: [String: Profile] = [:]
        var objectCount = 0
        var needsValueColumn = false
        for line in lines {
            guard case .object(let fields) = line.parsed else {
                needsValueColumn = true
                continue
            }
            objectCount += 1
            for field in fields {
                var budget = 64
                let evidence = assess(field.value, remainingNodes: &budget)
                profiles[field.key, default: Profile(key: field.key)].include(evidence, value: field.value)
            }
        }
        let ordered = profiles.values.sorted { $0.precedes($1, rowCount: objectCount) }
        return [.lineNumber] + ordered.map { .field($0.key) }
            + (needsValueColumn ? [.value] : [])
    }

    private enum Kind: Int {
        case prose, technical, number, other
    }

    private struct Evidence {
        var populated = false
        var kind = Kind.other
        var languageConfidence = 0.0
        var wordCount = 0
    }

    private struct Profile {
        let key: String
        var populatedCount = 0
        var proseCount = 0
        var technicalCount = 0
        var numberCount = 0
        var timestampCount = 0
        var languageConfidence = 0.0
        var wordCount = 0

        mutating func include(_ evidence: Evidence, value: JSONValue) {
            guard evidence.populated else { return }
            populatedCount += 1
            languageConfidence += evidence.languageConfidence
            wordCount += evidence.wordCount
            switch evidence.kind {
            case .prose: proseCount += 1
            case .technical: technicalCount += 1
            case .number: numberCount += 1
            case .other: break
            }
            if isTimestamp(value) { timestampCount += 1 }
        }

        private var timestampPriority: Int {
            let name = key.lowercased().filter(\.isLetter)
            if name == "timestamp" { return 0 }
            let aliases: Set<String> = ["ts", "time", "date", "datetime", "createdat", "updatedat", "eventtime"]
            if (name.hasSuffix("timestamp") || aliases.contains(name)),
               timestampCount > 0, timestampCount * 2 >= populatedCount { return 1 }
            return 2
        }

        private var proseLikelihood: Double {
            languageConfidence / Double(max(1, populatedCount))
        }

        private var kind: Kind {
            // A stray description must not promote an otherwise numeric or opaque column.
            if proseLikelihood >= 0.5 { return .prose }
            if technicalCount > 0, technicalCount * 2 >= populatedCount { return .technical }
            if numberCount > 0, numberCount * 2 >= populatedCount { return .number }
            return .other
        }

        func precedes(_ other: Profile, rowCount: Int) -> Bool {
            if timestampPriority != other.timestampPriority { return timestampPriority < other.timestampPriority }
            // Timestamp takes precedence even when it is sparse. Otherwise fewer
            // than one populated cell per four object records puts a column last.
            let sparse = populatedCount * 4 < rowCount
            let otherSparse = other.populatedCount * 4 < rowCount
            if sparse != otherSparse { return !sparse }
            if sparse, populatedCount != other.populatedCount { return populatedCount > other.populatedCount }
            if kind != other.kind { return kind.rawValue < other.kind.rawValue }
            if kind == .prose {
                // Coarse confidence bands avoid letting tiny punctuation differences
                // outweigh the amount of readable text in two similarly fluent fields.
                let confidenceBand = Int((proseLikelihood * 10).rounded())
                let otherBand = Int((other.proseLikelihood * 10).rounded())
                if confidenceBand != otherBand { return confidenceBand > otherBand }
                let averageWords = Double(wordCount) / Double(max(1, proseCount))
                let otherWords = Double(other.wordCount) / Double(max(1, other.proseCount))
                if averageWords != otherWords { return averageWords > otherWords }
            }
            if populatedCount != other.populatedCount { return populatedCount > other.populatedCount }
            return key < other.key
        }
    }

    private static func assess(_ value: JSONValue, remainingNodes: inout Int, depth: Int = 0) -> Evidence {
        guard remainingNodes > 0, depth < 8 else { return Evidence(populated: true) }
        remainingNodes -= 1
        switch value {
        case .null: return Evidence()
        case .bool: return Evidence(populated: true)
        case .number: return Evidence(populated: true, kind: .number)
        case .string(let text): return assessText(text)
        case .array(let values):
            return assessChildren(values.prefix(64), remainingNodes: &remainingNodes, depth: depth)
        case .object(let fields):
            // Stable traversal makes capped analysis independent of JSON key order.
            return assessChildren(fields.sorted { $0.key < $1.key }.prefix(64).map(\.value),
                                  remainingNodes: &remainingNodes, depth: depth)
        }
    }

    private static func assessChildren<Values: Sequence>(_ values: Values, remainingNodes: inout Int, depth: Int) -> Evidence where Values.Element == JSONValue {
        var best = Evidence()
        for value in values {
            let candidate = assess(value, remainingNodes: &remainingNodes, depth: depth + 1)
            if candidate.populated && (!best.populated || candidate.kind.rawValue < best.kind.rawValue) {
                best = candidate
            } else if candidate.kind == .prose && best.kind == .prose {
                best.languageConfidence = max(best.languageConfidence, candidate.languageConfidence)
                best.wordCount += candidate.wordCount
            }
            if remainingNodes <= 0 { break }
        }
        return best
    }

    private static func assessText(_ original: String) -> Evidence {
        // Inspect bounded text per value; previews and original file contents are untouched.
        let text = String(original.prefix(2_048)).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return Evidence() }
        if Double(text) != nil { return Evidence(populated: true, kind: .number) }
        if UUID(uuidString: text) != nil || isHexIdentifier(text) { return Evidence(populated: true) }

        let tokens = text.split(whereSeparator: \.isWhitespace).map(String.init)
        let first = tokens.first ?? ""
        let command = looksLikeCommand(tokens, executable: first)
        if command || isPathOrURL(text) || text.hasPrefix("#!") {
            return Evidence(populated: true, kind: .technical)
        }
        let words = tokens.filter(isReadableWord)
        let confidence = Double(words.count) / Double(max(1, tokens.count))
        if !words.isEmpty, confidence >= 0.55 {
            // Count word boundaries without allocating a second array for a large
            // message. Padding and long words must not masquerade as more words.
            var totalTokens = 0
            var inToken = false
            for character in original {
                if character.isWhitespace {
                    inToken = false
                } else if !inToken {
                    totalTokens += 1
                    inToken = true
                }
            }
            let estimatedWords = Int((Double(totalTokens) * confidence).rounded())
            return Evidence(populated: true, kind: .prose, languageConfidence: confidence, wordCount: estimatedWords)
        }
        let hasLetters = text.contains(where: \.isLetter)
        return Evidence(populated: true, kind: hasLetters ? .technical : .other)
    }

    private static func isReadableWord(_ token: String) -> Bool {
        let word = token.trimmingCharacters(in: .punctuationCharacters)
        guard !word.isEmpty, !isHexIdentifier(word) else { return false }
        // Identifiers, filenames, switches, and camelCase are useful technical text,
        // but should not compete with ordinary words and sentences.
        if token.hasPrefix("-"), token.count > 1 { return false }
        if word.range(of: "[a-z][A-Z]", options: .regularExpression) != nil { return false }
        if word.count > 24 && word.unicodeScalars.allSatisfy(\.isASCII) { return false }
        return word.contains(where: \.isLetter) && word.allSatisfy {
            $0.isLetter || $0 == "'" || $0 == "’" || $0 == "-"
        }
    }

    private static func isPathOrURL(_ text: String) -> Bool {
        if text.hasPrefix("/") || text.hasPrefix("~/") || text.hasPrefix("./") || text.hasPrefix("../") || text.hasPrefix("\\\\") { return true }
        if text.range(of: "^[A-Za-z]:[\\\\/]", options: .regularExpression) != nil { return true }
        if !text.contains(where: \.isWhitespace), text.contains("/") || text.contains("://") { return true }
        return false
    }

    private static func isHexIdentifier(_ text: String) -> Bool {
        text.count >= 12 && text.allSatisfy(\.isHexDigit)
    }

    private static func looksLikeCommand(_ tokens: [String], executable: String) -> Bool {
        guard tokens.count > 1, commands.contains(executable) else { return false }
        // These command names are also common starts of ordinary sentences.
        guard ["find", "go", "make", "export"].contains(executable) else { return true }
        if tokens.dropFirst().contains(where: { $0.hasPrefix("-") || isPathOrURL($0) || $0.contains("=") || $0 == "." }) { return true }
        let argument = tokens[1]
        return (executable == "go" && ["run", "test", "build", "mod", "fmt", "vet", "get", "install"].contains(argument))
            || (executable == "make" && ["build", "test", "clean", "all", "install", "release"].contains(argument))
    }

    private static func isTimestamp(_ value: JSONValue) -> Bool {
        switch value {
        case .number(let number): return number >= 100_000_000 && number < 100_000_000_000_000_000
        case .string(let text):
            return text.prefix(40).range(of: "^[0-9]{4}-[0-9]{2}-[0-9]{2}([Tt ][0-9]{2}:[0-9]{2}|$)", options: .regularExpression) != nil
        default: return false
        }
    }

    private static let commands: Set<String> = [
        "git", "gh", "npm", "pnpm", "yarn", "bun", "node", "python", "python3", "pip", "uv",
        "cargo", "swift", "xcodebuild", "curl", "wget", "ls", "cd", "rm", "cp", "mv", "mkdir",
        "chmod", "cat", "rg", "grep", "find", "sed", "awk", "echo", "printf", "docker", "kubectl",
        "brew", "ssh", "scp", "rsync", "make", "cmake", "go", "java", "ruby", "bundle", "env",
        "export", "sudo", "bash", "zsh", "sh", "fish",
    ]
}
