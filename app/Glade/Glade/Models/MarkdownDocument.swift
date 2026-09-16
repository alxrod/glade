import Foundation

struct MarkdownDocument {
    let fileURL: URL
    let fileName: String
    let content: String
    let headings: [MarkdownHeading]

    static func parse(from url: URL) throws -> MarkdownDocument {
        let content = try String(contentsOf: url, encoding: .utf8)
        return parse(rawContent: content, url: url)
    }

    static func parse(rawContent: String, url: URL) -> MarkdownDocument {
        let headings = extractHeadingTree(from: rawContent)
        return MarkdownDocument(
            fileURL: url,
            fileName: url.lastPathComponent,
            content: rawContent,
            headings: headings
        )
    }

    /// Extracts headings from markdown and builds a nested tree.
    /// H1 is top-level, H2 nests under preceding H1, H3 under preceding H2, etc.
    private static func extractHeadingTree(from content: String) -> [MarkdownHeading] {
        let lines = content.components(separatedBy: .newlines)
        var flatHeadings: [MarkdownHeading] = []
        var activeFenceMarker: Character?

        for (index, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if let marker = trimmed.first, (marker == "`" || marker == "~") {
                let runLength = trimmed.prefix(while: { $0 == marker }).count
                if runLength >= 3 {
                    if activeFenceMarker == nil {
                        activeFenceMarker = marker
                    } else if activeFenceMarker == marker {
                        activeFenceMarker = nil
                    }
                    continue
                }
            }
            guard activeFenceMarker == nil else { continue }

            if let heading = parseHeadingLine(trimmed, lineIndex: index) {
                flatHeadings.append(heading)
            }
        }

        return buildTree(from: flatHeadings)
    }

    private static func parseHeadingLine(_ line: String, lineIndex: Int) -> MarkdownHeading? {
        var level = 0
        for char in line {
            if char == "#" {
                level += 1
            } else {
                break
            }
        }
        guard level >= 1, level <= 6 else { return nil }

        let rest = line.dropFirst(level)
        guard rest.first == " " || rest.isEmpty else { return nil }

        let title = rest.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else { return nil }

        return MarkdownHeading(level: level, title: title, lineIndex: lineIndex, children: [])
    }

    /// Builds a tree from a flat list of headings using a stack-based approach.
    private static func buildTree(from headings: [MarkdownHeading]) -> [MarkdownHeading] {
        var roots: [MarkdownHeading] = []
        // Stack of (level, index-in-parent's-children-array, reference-to-parent-array)
        // We'll use a simpler recursive insertion approach
        for heading in headings {
            insertHeading(heading, into: &roots)
        }
        return roots
    }

    private static func insertHeading(_ heading: MarkdownHeading, into roots: inout [MarkdownHeading]) {
        // If empty or heading level <= last root's level, it's a new root
        guard let lastIndex = roots.indices.last else {
            roots.append(heading)
            return
        }

        let last = roots[lastIndex]
        if heading.level <= last.level {
            roots.append(heading)
        } else {
            // It's a child of the last root — recurse into its children
            insertHeading(heading, into: &roots[lastIndex].children)
        }
    }
}
