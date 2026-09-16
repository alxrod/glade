import SwiftUI

// MARK: - Highlighted Text Helper

/// Returns an AttributedString with all occurrences of `query` highlighted
/// using a yellow/gold background. Falls back to plain text when query is empty.
func highlightedAttributedString(_ text: String, query: String) -> AttributedString {
    var attributed = AttributedString(text)

    let trimmed = query.trimmingCharacters(in: .whitespaces)
    guard !trimmed.isEmpty else { return attributed }

    let lowerText = text.lowercased()
    let lowerQuery = trimmed.lowercased()
    var stringSearchStart = lowerText.startIndex

    while stringSearchStart < lowerText.endIndex,
          let stringRange = lowerText.range(of: lowerQuery, range: stringSearchStart..<lowerText.endIndex) {
        // Convert String.Index range to AttributedString range
        let startOffset = lowerText.distance(from: lowerText.startIndex, to: stringRange.lowerBound)
        let endOffset = lowerText.distance(from: lowerText.startIndex, to: stringRange.upperBound)

        let attrStart = attributed.index(attributed.startIndex, offsetByCharacters: startOffset)
        let attrEnd = attributed.index(attributed.startIndex, offsetByCharacters: endOffset)
        let attrRange = attrStart..<attrEnd

        attributed[attrRange].backgroundColor = .init(.yellow.opacity(0.6))
        stringSearchStart = stringRange.upperBound
    }

    return attributed
}

func highlightedText(_ text: String, query: String) -> Text {
    Text(highlightedAttributedString(text, query: query))
}

// MARK: - Clipboard Helper

private func copyToPasteboard(_ string: String) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(string, forType: .string)
}

// MARK: - Raw value (no quotes for strings)
private func rawValue(_ value: JSONValue) -> String {
    switch value {
    case .string(let str): return str
    case .number(let num):
        if num == num.rounded() && !num.isInfinite && abs(num) < 1e15 {
            return String(Int64(num))
        }
        return String(num)
    case .bool(let flag): return flag ? "true" : "false"
    case .null: return "null"
    case .object(let pairs): return "{\(pairs.count) keys}"
    case .array(let arr): return "[\(arr.count) items]"
    }
}

// MARK: - Adaptive JSON colors

/// Colors that read clearly in both light and dark mode.
extension Color {
    static var jsonNumber: Color {
        Color(light: Color(red: 0.05, green: 0.35, blue: 0.85),
              dark: Color(red: 0.45, green: 0.75, blue: 1.0))
    }
    static var jsonBool: Color {
        Color(light: Color(red: 0.75, green: 0.35, blue: 0.0),
              dark: Color(red: 1.0, green: 0.65, blue: 0.2))
    }
    static var jsonString2: Color {
        Color(light: Color(red: 0.1, green: 0.5, blue: 0.1),
              dark: Color(red: 0.4, green: 0.9, blue: 0.4))
    }

    init(light: Color, dark: Color) {
        self.init(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                ? NSColor(dark) : NSColor(light)
        })
    }
}

// MARK: - JSONValueView

// Recursive view for rendering any JSON value with syntax coloring
struct JSONValueView: View {
    let value: JSONValue
    let indentLevel: Int
    var searchText: String = ""
    var contextKey: String?
    @State private var isExpanded: Bool = true

    private let indentWidth: CGFloat = 16

    var body: some View {
        switch value {
        case .object(let pairs):
            objectView(pairs: pairs)
        case .array(let arr):
            arrayView(arr: arr)
        case .string(let str):
            highlightedText("\"\(str)\"", query: searchText)
                .foregroundColor(.jsonString2)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .contextMenu { primitiveMenu(displayValue: str) }
        case .number:
            highlightedText(value.displayString, query: searchText)
                .foregroundColor(.jsonNumber)
                .textSelection(.enabled)
                .contextMenu { primitiveMenu(displayValue: rawValue(value)) }
        case .bool(let flag):
            highlightedText(flag ? "true" : "false", query: searchText)
                .foregroundColor(.jsonBool)
                .textSelection(.enabled)
                .contextMenu { primitiveMenu(displayValue: flag ? "true" : "false") }
        case .null:
            highlightedText("null", query: searchText)
                .foregroundColor(.secondary)
                .italic()
                .contextMenu { primitiveMenu(displayValue: "null") }
        }
    }

    @ViewBuilder
    private func primitiveMenu(displayValue: String) -> some View {
        Button("Copy Value") {
            copyToPasteboard(displayValue)
        }
        if let key = contextKey {
            Button("Copy Key: Value") {
                copyToPasteboard("\(key): \(displayValue)")
            }
        }
    }

    @ViewBuilder
    private func collapseToggle(_ label: String) -> some View {
        Button {
            isExpanded.toggle()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.secondary)
                    .frame(width: 12)
                Text(verbatim: label)
                    .foregroundColor(.secondary)
                    .font(.system(.body, design: .monospaced))
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(label))
    }

    @ViewBuilder
    private func objectView(pairs: [JSONKeyValue]) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            collapseToggle("{ \(pairs.count) \(pairs.count == 1 ? "key" : "keys") }")
            if isExpanded {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(pairs.enumerated()), id: \.offset) { _, kv in
                        KeyValueRowView(
                            key: kv.key,
                            value: kv.value,
                            indentLevel: indentLevel + 1,
                            searchText: searchText
                        )
                    }
                }
                .padding(.leading, indentWidth)
            }
        }
    }

    @ViewBuilder
    private func arrayView(arr: [JSONValue]) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            collapseToggle("[ \(arr.count) \(arr.count == 1 ? "item" : "items") ]")
            if isExpanded {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(arr.enumerated()), id: \.offset) { index, item in
                        HStack(alignment: .top, spacing: 6) {
                            Text(verbatim: "[\(index)]")
                                .foregroundColor(.secondary)
                                .font(.system(.caption, design: .monospaced))
                                .frame(minWidth: 24, alignment: .trailing)
                            JSONValueView(value: item, indentLevel: indentLevel + 1, searchText: searchText)
                        }
                    }
                }
                .padding(.leading, indentWidth)
            }
        }
    }
}

// MARK: - KeyValueRowView

// A single key: value row used in object rendering
struct KeyValueRowView: View {
    let key: String
    let value: JSONValue
    let indentLevel: Int
    var searchText: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            switch value {
            case .object, .array:
                VStack(alignment: .leading, spacing: 2) {
                    highlightedText(key, query: searchText)
                        .font(.system(.body, design: .monospaced).bold())
                        .foregroundColor(.primary)
                    JSONValueView(value: value, indentLevel: indentLevel, searchText: searchText, contextKey: key)
                }
            default:
                HStack(alignment: .top, spacing: 8) {
                    highlightedText(key, query: searchText)
                        .font(.system(.body, design: .monospaced).bold())
                        .foregroundColor(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                    JSONValueView(value: value, indentLevel: indentLevel, searchText: searchText, contextKey: key)
                }
                .contextMenu {
                    Button("Copy Value") {
                        copyToPasteboard(rawValue(value))
                    }
                    Button("Copy Key: Value") {
                        copyToPasteboard("\(key): \(rawValue(value))")
                    }
                }
            }
        }
        .padding(.vertical, 2)
    }
}
