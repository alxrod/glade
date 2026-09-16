import SwiftUI

struct DetailView: View {
    let line: JSONLLine?
    @Binding var searchText: String
    var onClose: (() -> Void)?
    @State private var searchResults = JSONLineSearchResults()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                if let line {
                    Label("Line \(line.lineNumber)", systemImage: "number")
                        .font(.headline)
                }
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

            if let line {
                let search = searchResults.lineID == line.id ? searchResults.search : JSONLineSearch(value: .null, query: "")
                searchBar(search: search)
                Divider()
                ScrollView(.vertical) {
                    if search.isActive && search.matchCount == 0 {
                        VStack(spacing: 8) {
                            Image(systemName: "magnifyingglass")
                                .font(.title2)
                            Text("No matches in this line")
                            Text("Try another search or clear it to show the full line.")
                                .font(.caption)
                        }
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(24)
                    } else if let parseError = line.parseError {
                        parseErrorView(error: parseError, raw: line.rawJSON, search: search)
                    } else if let parsed = line.parsed {
                        parsedContentView(parsed: parsed, search: search)
                    }
                }
                // Start at the top and reveal matching branches on each search.
                // Keep the header and field outside so focus survives filtering.
                .id(search.query)
                .id(line.id)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 48))
                    Text("Select a row to view details")
                        .font(.title3)
                }
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task(id: LineSearchRequest(lineID: line?.id, query: searchText)) {
            await searchResults.update(line: line, query: searchText)
        }
    }

    private func searchBar(search: JSONLineSearch) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            JSONSearchField(placeholder: "Search this line", accessibilityName: "Search this line", clearLabel: "Clear line search",
                            submittedText: $searchText, isSearching: searchResults.isSearching)
            if search.isActive {
                Group {
                    if search.matchCount == 1 {
                        Text("1 match")
                    } else {
                        Text("\(search.matchCount) matches")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize()
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 10)
    }

    @ViewBuilder
    private func parsedContentView(parsed: JSONValue, search: JSONLineSearch) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            switch parsed {
            case .object(let pairs):
                let visible = Array(pairs.enumerated()).filter { search.includes([$0.offset]) }
                ForEach(visible, id: \.offset) { index, kv in
                    KeyValueRowView(key: kv.key, value: kv.value, indentLevel: 0, search: search, path: [index])
                    if index != visible.last?.offset {
                        Divider().padding(.vertical, 1)
                    }
                }
            case .array(let arr):
                let visible = Array(arr.enumerated()).filter { search.includes([$0.offset]) }
                ForEach(visible, id: \.offset) { index, item in
                    HStack(alignment: .top, spacing: 8) {
                        Text("[\(index)]")
                            .font(.system(.body, design: .monospaced).bold())
                            .foregroundColor(.secondary)
                            .frame(minWidth: 40, alignment: .trailing)
                        JSONValueView(value: item, indentLevel: 0, search: search, path: [index])
                    }
                    .padding(.vertical, 2)
                    if index != visible.last?.offset {
                        Divider().padding(.vertical, 1)
                    }
                }
            default:
                JSONValueView(value: parsed, indentLevel: 0, search: search)
                    .padding(.vertical, 4)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func parseErrorView(error: String, raw: String, search: JSONLineSearch) -> some View {
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
            highlightedText(raw, query: search.query)
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(.primary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct LineSearchRequest: Equatable {
    let lineID: UUID?
    let query: String
}
