import SwiftUI

struct DetailView: View {
    let line: JSONLLine?
    var searchText: String = ""
    var onClose: (() -> Void)?

    var body: some View {
        Group {
            if let line = line {
                lineDetailView(line: line)
            } else {
                VStack {
                    if let onClose {
                        HStack {
                            Spacer()
                            Button(action: onClose) {
                                Image(systemName: "xmark")
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel("Close line inspector")
                        }
                        .padding()
                    }
                    emptyView
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var emptyView: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            Text("Select a row to view details")
                .font(.title3)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func lineDetailView(line: JSONLLine) -> some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 0) {
                // Header
                HStack {
                    Label("Line \(line.lineNumber)", systemImage: "number")
                        .font(.headline)
                        .foregroundColor(.primary)
                    Spacer()
                    if let onClose {
                        Button(action: onClose) {
                            Image(systemName: "xmark")
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Close line inspector")
                        .help("Close line inspector")
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color(nsColor: .windowBackgroundColor))

                Divider()

                if let parseError = line.parseError {
                    parseErrorView(error: parseError, raw: line.rawJSON)
                } else if let parsed = line.parsed {
                    parsedContentView(parsed: parsed, searchText: searchText)
                }
            }
        }
        .id(line.id) // Reset scroll position when line changes
    }

    @ViewBuilder
    private func parsedContentView(parsed: JSONValue, searchText: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            switch parsed {
            case .object(let pairs):
                ForEach(Array(pairs.enumerated()), id: \.offset) { index, kv in
                    KeyValueRowView(key: kv.key, value: kv.value, indentLevel: 0, searchText: searchText)
                    if index < pairs.count - 1 {
                        Divider()
                            .padding(.vertical, 1)
                    }
                }
            case .array(let arr):
                ForEach(Array(arr.enumerated()), id: \.offset) { index, item in
                    HStack(alignment: .top, spacing: 8) {
                        Text("[\(index)]")
                            .font(.system(.body, design: .monospaced).bold())
                            .foregroundColor(.secondary)
                            .frame(minWidth: 40, alignment: .trailing)
                        JSONValueView(value: item, indentLevel: 0, searchText: searchText)
                    }
                    .padding(.vertical, 2)
                    if index < arr.count - 1 {
                        Divider().padding(.vertical, 1)
                    }
                }
            default:
                // Primitive at root level
                JSONValueView(value: parsed, indentLevel: 0, searchText: searchText)
                    .padding(.vertical, 4)
            }
        }
        .padding(16)
    }

    @ViewBuilder
    private func parseErrorView(error: String, raw: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Parse Error", systemImage: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
                .font(.headline)

            Text(error)
                .font(.callout)
                .foregroundColor(.secondary)

            Divider()

            Text("Raw content:")
                .font(.caption)
                .foregroundColor(.secondary)

            Text(raw)
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(.primary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
    }
}
