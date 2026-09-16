import SwiftUI

// MARK: - Heading Position Tracking

struct HeadingPosition: Equatable {
    let lineIndex: Int
    let headingID: UUID
    let minY: CGFloat
}

struct HeadingPositionKey: PreferenceKey {
    static var defaultValue: [HeadingPosition] = []
    static func reduce(value: inout [HeadingPosition], nextValue: () -> [HeadingPosition]) {
        value.append(contentsOf: nextValue())
    }
}

struct MarkdownDetailView: View {
    let document: MarkdownDocument
    let scrollTarget: ScrollTarget?
    let headingLookup: [Int: UUID]
    var onVisibleHeadingChanged: ((UUID) -> Void)?

    private var anchorMap: [String: Int] {
        var map: [String: Int] = [:]
        for block in document.blocks {
            if case .heading(_, let text, let lineIndex) = block {
                var slug = slugify(text)
                if map[slug] != nil {
                    var suffix = 1
                    while map["\(slug)-\(suffix)"] != nil { suffix += 1 }
                    slug = "\(slug)-\(suffix)"
                }
                map[slug] = lineIndex
            }
        }
        return map
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(document.blocks.enumerated()), id: \.offset) { _, block in
                        MarkdownBlockView(block: block, headingLookup: headingLookup)
                    }
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .coordinateSpace(name: "markdownScroll")
            .onPreferenceChange(HeadingPositionKey.self) { positions in
                // Find the heading closest to (but not far below) the top of the scroll view
                let visible = positions
                    .filter { $0.minY <= 80 }
                    .max(by: { $0.minY < $1.minY })
                if let visible {
                    onVisibleHeadingChanged?(visible.headingID)
                }
            }
            .environment(\.openURL, OpenURLAction { url in
                let isFragmentOnly = url.scheme == nil && url.host == nil
                    && url.query == nil && (url.path.isEmpty || url.path == "/")
                guard isFragmentOnly, let fragment = url.fragment else {
                    return .systemAction
                }
                if let lineIndex = anchorMap[fragment] {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        proxy.scrollTo("heading-\(lineIndex)", anchor: .top)
                    }
                    return .handled
                }
                let lower = fragment.lowercased()
                if let lineIndex = anchorMap[lower] {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        proxy.scrollTo("heading-\(lineIndex)", anchor: .top)
                    }
                    return .handled
                }
                return .systemAction
            })
            .onChange(of: scrollTarget) { _, newTarget in
                guard let target = newTarget else { return }
                withAnimation(.easeInOut(duration: 0.3)) {
                    proxy.scrollTo("heading-\(target.lineIndex)", anchor: .top)
                }
            }
        }
    }
}

/// Converts heading text to a GitHub-style anchor slug.
private func slugify(_ text: String) -> String {
    // Strip inline markdown formatting
    var slug = text
        .replacingOccurrences(of: "\\*\\*(.+?)\\*\\*", with: "$1", options: .regularExpression)
        .replacingOccurrences(of: "\\*(.+?)\\*", with: "$1", options: .regularExpression)
        .replacingOccurrences(of: "`(.+?)`", with: "$1", options: .regularExpression)
        .replacingOccurrences(of: "\\[(.+?)\\]\\(.+?\\)", with: "$1", options: .regularExpression)

    slug = slug.lowercased()
    // Replace spaces with hyphens, strip non-alphanumeric (except hyphens)
    slug = slug.replacingOccurrences(of: " ", with: "-")
    slug = slug.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) || $0 == "-" }
        .map { String($0) }.joined()
    slug = slug.replacingOccurrences(of: "-{2,}", with: "-", options: .regularExpression)
    return slug
}

// MARK: - Block Parser

enum MarkdownBlock {
    case heading(level: Int, text: String, lineIndex: Int)
    case paragraph(text: String)
    case codeBlock(language: String?, code: String)
    case unorderedList(items: [ListItem])
    case orderedList(items: [ListItem])
    case blockquote(text: String)
    case table(headers: [String], rows: [[String]])
    case horizontalRule
    case blankLine

    struct ListItem {
        let text: String
        let children: [ListItem]
    }
}

extension MarkdownDocument {
    var blocks: [MarkdownBlock] {
        Self.parseBlocks(from: content)
    }

    static func parseBlocks(from content: String) -> [MarkdownBlock] {
        let lines = content.components(separatedBy: "\n")
        var blocks: [MarkdownBlock] = []
        var index = 0

        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Blank line
            if trimmed.isEmpty {
                index += 1
                continue
            }

            // Code block (backtick ``` or tilde ~~~)
            if let fence = detectFence(trimmed) {
                let language = String(trimmed.dropFirst(fence.length)).trimmingCharacters(in: .whitespaces)
                let closer = String(repeating: String(fence.marker), count: fence.length)
                var codeLines: [String] = []
                index += 1
                while index < lines.count {
                    let closeTrimmed = lines[index].trimmingCharacters(in: .whitespaces)
                    if closeTrimmed.hasPrefix(closer) && closeTrimmed.drop(while: { $0 == fence.marker }).trimmingCharacters(in: .whitespaces).isEmpty {
                        index += 1
                        break
                    }
                    codeLines.append(lines[index])
                    index += 1
                }
                blocks.append(.codeBlock(
                    language: language.isEmpty ? nil : language,
                    code: codeLines.joined(separator: "\n")
                ))
                continue
            }

            // Heading
            if let heading = parseHeading(trimmed, lineIndex: index) {
                blocks.append(heading)
                index += 1
                continue
            }

            // Horizontal rule
            if isHorizontalRule(trimmed) {
                blocks.append(.horizontalRule)
                index += 1
                continue
            }

            // Blockquote
            if trimmed.hasPrefix(">") {
                var quoteLines: [String] = []
                while index < lines.count {
                    let currentTrimmed = lines[index].trimmingCharacters(in: .whitespaces)
                    if currentTrimmed.hasPrefix(">") {
                        let content = String(currentTrimmed.dropFirst()).trimmingCharacters(in: .whitespaces)
                        quoteLines.append(content)
                    } else if currentTrimmed.isEmpty {
                        break
                    } else {
                        break
                    }
                    index += 1
                }
                blocks.append(.blockquote(text: quoteLines.joined(separator: "\n")))
                continue
            }

            // Unordered list
            if isUnorderedListItem(trimmed) {
                var items: [MarkdownBlock.ListItem] = []
                while index < lines.count {
                    let currentTrimmed = lines[index].trimmingCharacters(in: .whitespaces)
                    if isUnorderedListItem(currentTrimmed) {
                        let text = stripListMarker(currentTrimmed)
                        items.append(MarkdownBlock.ListItem(text: text, children: []))
                    } else if currentTrimmed.isEmpty {
                        break
                    } else {
                        // Continuation line — append to last item
                        if var lastItem = items.last {
                            items.removeLast()
                            let combined = lastItem.text + " " + currentTrimmed
                            lastItem = MarkdownBlock.ListItem(text: combined, children: lastItem.children)
                            items.append(lastItem)
                        } else {
                            break
                        }
                    }
                    index += 1
                }
                blocks.append(.unorderedList(items: items))
                continue
            }

            // Ordered list
            if isOrderedListItem(trimmed) {
                var items: [MarkdownBlock.ListItem] = []
                while index < lines.count {
                    let currentTrimmed = lines[index].trimmingCharacters(in: .whitespaces)
                    if isOrderedListItem(currentTrimmed) {
                        let text = stripOrderedListMarker(currentTrimmed)
                        items.append(MarkdownBlock.ListItem(text: text, children: []))
                    } else if currentTrimmed.isEmpty {
                        break
                    } else {
                        if var lastItem = items.last {
                            items.removeLast()
                            let combined = lastItem.text + " " + currentTrimmed
                            lastItem = MarkdownBlock.ListItem(text: combined, children: lastItem.children)
                            items.append(lastItem)
                        } else {
                            break
                        }
                    }
                    index += 1
                }
                blocks.append(.orderedList(items: items))
                continue
            }

            // Table — header row starts with |, followed by separator row with |---|
            if isTableRow(trimmed), index + 1 < lines.count,
               isTableSeparator(lines[index + 1].trimmingCharacters(in: .whitespaces)) {
                let headers = parseTableCells(trimmed)
                index += 2 // skip header + separator
                var rows: [[String]] = []
                while index < lines.count {
                    let currentTrimmed = lines[index].trimmingCharacters(in: .whitespaces)
                    guard isTableRow(currentTrimmed) else { break }
                    rows.append(parseTableCells(currentTrimmed))
                    index += 1
                }
                blocks.append(.table(headers: headers, rows: rows))
                continue
            }

            // Paragraph — collect consecutive non-blank, non-special lines
            var paraLines: [String] = []
            while index < lines.count {
                let currentTrimmed = lines[index].trimmingCharacters(in: .whitespaces)
                if currentTrimmed.isEmpty
                    || currentTrimmed.hasPrefix("#")
                    || detectFence(currentTrimmed) != nil
                    || currentTrimmed.hasPrefix(">")
                    || isHorizontalRule(currentTrimmed)
                    || isUnorderedListItem(currentTrimmed)
                    || isOrderedListItem(currentTrimmed)
                    || isTableRow(currentTrimmed) {
                    break
                }
                paraLines.append(currentTrimmed)
                index += 1
            }
            if !paraLines.isEmpty {
                blocks.append(.paragraph(text: paraLines.joined(separator: " ")))
            }
        }

        return blocks
    }

    private static func parseHeading(_ line: String, lineIndex: Int) -> MarkdownBlock? {
        var level = 0
        for char in line {
            if char == "#" { level += 1 } else { break }
        }
        guard level >= 1, level <= 6 else { return nil }
        let rest = line.dropFirst(level)
        guard rest.first == " " || rest.isEmpty else { return nil }
        let title = rest.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else { return nil }
        return .heading(level: level, text: title, lineIndex: lineIndex)
    }

    private static func isHorizontalRule(_ line: String) -> Bool {
        let stripped = line.replacingOccurrences(of: " ", with: "")
        return (stripped.allSatisfy { $0 == "-" } && stripped.count >= 3)
            || (stripped.allSatisfy { $0 == "*" } && stripped.count >= 3)
            || (stripped.allSatisfy { $0 == "_" } && stripped.count >= 3)
    }

    private static func isUnorderedListItem(_ line: String) -> Bool {
        line.hasPrefix("- ") || line.hasPrefix("* ") || line.hasPrefix("+ ")
    }

    private static func isOrderedListItem(_ line: String) -> Bool {
        guard let dotIndex = line.firstIndex(of: ".") else { return false }
        let prefix = line[line.startIndex..<dotIndex]
        guard !prefix.isEmpty, prefix.allSatisfy(\.isNumber) else { return false }
        let afterDot = line.index(after: dotIndex)
        return afterDot < line.endIndex && line[afterDot] == " "
    }

    private static func stripListMarker(_ line: String) -> String {
        String(line.dropFirst(2))
    }

    private static func stripOrderedListMarker(_ line: String) -> String {
        guard let dotIndex = line.firstIndex(of: ".") else { return line }
        let afterDot = line.index(after: dotIndex)
        guard afterDot < line.endIndex else { return "" }
        return String(line[line.index(after: afterDot)...]).trimmingCharacters(in: .whitespaces)
    }

    private static func detectFence(_ line: String) -> (marker: Character, length: Int)? {
        guard let marker = line.first, (marker == "`" || marker == "~") else { return nil }
        let runLength = line.prefix(while: { $0 == marker }).count
        guard runLength >= 3 else { return nil }
        return (marker, runLength)
    }

    private static func isTableRow(_ line: String) -> Bool {
        line.hasPrefix("|") && line.hasSuffix("|") && line.count > 1
    }

    private static func isTableSeparator(_ line: String) -> Bool {
        guard isTableRow(line) else { return false }
        let inner = line.dropFirst().dropLast()
        return inner.allSatisfy { $0 == "-" || $0 == "|" || $0 == ":" || $0 == " " }
            && inner.contains("-")
    }

    private static func parseTableCells(_ line: String) -> [String] {
        let inner = line.dropFirst().dropLast() // strip leading/trailing |
        return inner.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
    }
}

// MARK: - Block Renderer

struct MarkdownBlockView: View {
    let block: MarkdownBlock
    var headingLookup: [Int: UUID] = [:]

    var body: some View {
        switch block {
        case .heading(let level, let text, let lineIndex):
            headingView(level: level, text: text, lineIndex: lineIndex)
        case .paragraph(let text):
            inlineMarkdownText(text)
                .font(.body)
                .foregroundColor(.primary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 10)
                .textSelection(.enabled)
        case .codeBlock(_, let code):
            codeBlockView(code: code)
        case .unorderedList(let items):
            unorderedListView(items: items)
                .padding(.bottom, 10)
        case .orderedList(let items):
            orderedListView(items: items)
                .padding(.bottom, 10)
        case .blockquote(let text):
            blockquoteView(text: text)
        case .table(let headers, let rows):
            ResizableTableView(headers: headers, rows: rows)
                .padding(.bottom, 10)
        case .horizontalRule:
            Divider()
                .padding(.vertical, 12)
        case .blankLine:
            Spacer()
                .frame(height: 8)
        }
    }

    @ViewBuilder
    private func headingView(level: Int, text: String, lineIndex: Int) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer().frame(height: topSpacingForLevel(level))

            inlineMarkdownText(text)
                .font(fontForHeadingLevel(level))
                .foregroundColor(.primary)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
                .id("heading-\(lineIndex)")
                .background(
                    GeometryReader { geo in
                        if let headingID = headingLookup[lineIndex] {
                            Color.clear.preference(
                                key: HeadingPositionKey.self,
                                value: [HeadingPosition(
                                    lineIndex: lineIndex,
                                    headingID: headingID,
                                    minY: geo.frame(in: .named("markdownScroll")).minY
                                )]
                            )
                        }
                    }
                )

            if level <= 2 {
                Divider()
                    .padding(.top, 6)
            }
        }
        .padding(.bottom, level <= 2 ? 10 : 6)
        .accessibilityAddTraits(.isHeader)
    }

    private func topSpacingForLevel(_ level: Int) -> CGFloat {
        switch level {
        case 1: return 0
        case 2: return 30
        case 3: return 20
        default: return 15
        }
    }

    private func fontForHeadingLevel(_ level: Int) -> Font {
        switch level {
        case 1: return .system(size: 28, weight: .bold)
        case 2: return .system(size: 22, weight: .bold)
        case 3: return .system(size: 18, weight: .semibold)
        case 4: return .system(size: 16, weight: .semibold)
        case 5: return .system(size: 14, weight: .semibold)
        default: return .system(size: 13, weight: .semibold)
        }
    }

    @ViewBuilder
    private func codeBlockView(code: String) -> some View {
        ScrollView(.horizontal, showsIndicators: true) {
            Text(code)
                .font(.system(.body, design: .monospaced))
                .foregroundColor(.primary)
                .textSelection(.enabled)
                .padding(12)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.mdCodeBackground)
        .cornerRadius(6)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.primary.opacity(0.1), lineWidth: 1)
        )
        .padding(.bottom, 10)
    }

    @ViewBuilder
    private func unorderedListView(items: [MarkdownBlock.ListItem]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                HStack(alignment: .top, spacing: 8) {
                    Text("\u{2022}")
                        .foregroundColor(.secondary)
                        .frame(width: 12, alignment: .center)
                    inlineMarkdownText(item.text)
                        .font(.body)
                        .foregroundColor(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
            }
        }
        .padding(.leading, 4)
    }

    @ViewBuilder
    private func orderedListView(items: [MarkdownBlock.ListItem]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                HStack(alignment: .top, spacing: 8) {
                    Text(verbatim: "\(index + 1).")
                        .foregroundColor(.secondary)
                        .font(.body)
                        .frame(minWidth: 20, alignment: .trailing)
                    inlineMarkdownText(item.text)
                        .font(.body)
                        .foregroundColor(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
            }
        }
        .padding(.leading, 4)
    }

    @ViewBuilder
    private func blockquoteView(text: String) -> some View {
        HStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(Color.accentColor.opacity(0.5))
                .frame(width: 3)
            inlineMarkdownText(text)
                .font(.body)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
                .padding(.leading, 12)
        }
        .padding(.vertical, 4)
        .padding(.bottom, 10)
    }

}

// MARK: - Resizable Table

struct ResizableTableView: View {
    let headers: [String]
    let rows: [[String]]
    @State private var tableWidth: CGFloat?
    @State private var measuredWidth: CGFloat?
    @State private var dragStartWidth: CGFloat?
    @State private var isDragging = false
    @State private var isCursorPushed = false

    var body: some View {
        let columnCount = headers.count

        Grid(alignment: .leading, horizontalSpacing: 0, verticalSpacing: 0) {
            GridRow {
                ForEach(Array(headers.enumerated()), id: \.offset) { _, header in
                    inlineMarkdownText(header)
                        .font(.system(.callout, weight: .semibold))
                        .foregroundColor(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .background(Color.primary.opacity(0.08))

            Divider()
                .gridCellUnsizedAxes(.horizontal)

            ForEach(Array(rows.enumerated()), id: \.offset) { rowIndex, row in
                GridRow {
                    ForEach(0..<columnCount, id: \.self) { colIndex in
                        let cell = colIndex < row.count ? row[colIndex] : ""
                        inlineMarkdownText(cell)
                            .font(.system(.callout))
                            .foregroundColor(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .background(rowIndex.isMultiple(of: 2)
                    ? Color.clear
                    : Color.primary.opacity(0.03))

                if rowIndex < rows.count - 1 {
                    Divider()
                        .gridCellUnsizedAxes(.horizontal)
                }
            }
        }
        .frame(maxWidth: tableWidth ?? .infinity, alignment: .leading)
        .background(
            GeometryReader { geo in
                Color.mdCodeBackground.onAppear { measuredWidth = geo.size.width }
            }
        )
        .cornerRadius(6)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.primary.opacity(0.1), lineWidth: 1)
        )
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(isDragging ? Color.accentColor.opacity(0.6) : Color.clear)
                .frame(width: 6)
                .contentShape(Rectangle().inset(by: -6))
                .gesture(
                    DragGesture(coordinateSpace: .global)
                        .onChanged { value in
                            if dragStartWidth == nil {
                                dragStartWidth = tableWidth ?? measuredWidth
                            }
                            isDragging = true
                            let delta = value.translation.width
                            let base = dragStartWidth ?? measuredWidth ?? 400
                            tableWidth = max(200, base + delta)
                        }
                        .onEnded { _ in
                            isDragging = false
                            dragStartWidth = nil
                        }
                )
                .onHover { hovering in
                    isCursorPushed = hovering
                    if hovering {
                        NSCursor.resizeLeftRight.push()
                    } else {
                        NSCursor.pop()
                    }
                }
                .onDisappear {
                    if isCursorPushed {
                        NSCursor.pop()
                        isCursorPushed = false
                    }
                }
                .accessibilityLabel(Text("Resize table"))
        }
    }
}

// MARK: - Inline Markdown Rendering

/// Renders inline markdown (bold, italic, code, links) using AttributedString.
private func inlineMarkdownText(_ text: String) -> Text {
    if let attributed = try? AttributedString(markdown: text, options: .init(
        interpretedSyntax: .inlineOnlyPreservingWhitespace
    )) {
        return Text(attributed)
    }
    return Text(text)
}

// MARK: - Markdown-specific adaptive colors

extension Color {
    static var mdCodeBackground: Color {
        Color(light: Color(red: 0.95, green: 0.95, blue: 0.97),
              dark: Color(red: 0.15, green: 0.15, blue: 0.17))
    }
}
