import SwiftUI

struct JSONLQueryBar: View {
    @Bindable var viewModel: GladeViewModel
    let columns: [JSONLTableColumn]
    @State private var store = JSONLSavedQueryStore.shared
    @State private var isEditing = false
    @State private var draft = JSONLQuery()
    @State private var name = ""

    var body: some View {
        let saved = store.queries(for: columns)
        HStack(spacing: 8) {
            Button {
                draft = viewModel.tableQuery
                name = saved.first(where: { $0.query.hasSameSearch(as: draft) })?.name ?? ""
                isEditing = true
            } label: {
                Label(viewModel.columnFilters.isEmpty ? String(localized: "Filters") : String(localized: "Filters (\(viewModel.columnFilters.count))"),
                      systemImage: "line.3.horizontal.decrease")
            }
            .help("Combine column conditions and save a query")
            .popover(isPresented: $isEditing, arrowEdge: .bottom) {
                editor
            }

            Toggle(isOn: $viewModel.taggedOnly) {
                Label("Tagged only", systemImage: "tag")
            }
            .toggleStyle(.button)
            .help("Show only rows with a color tag")

            ScrollView(.horizontal) {
                HStack(spacing: 6) {
                    if saved.isEmpty {
                        Text("Save a query in Filters to reuse it here")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    ForEach(saved) { item in
                        Button {
                            viewModel.tableQuery = item.query
                        } label: {
                            HStack(spacing: 4) {
                                if item.query.hasSameSearch(as: viewModel.tableQuery) {
                                    Image(systemName: "checkmark")
                                }
                                Text(verbatim: item.name).lineLimit(1)
                            }
                        }
                        .help(String(localized: "Apply saved query “\(item.name)”"))
                        .contextMenu {
                            Button("Edit Query…") {
                                draft = item.query
                                name = item.name
                                isEditing = true
                            }
                            Button("Delete Saved Query", role: .destructive) {
                                store.delete(item, for: columns)
                            }
                        }
                    }
                }
            }
            .scrollIndicators(.hidden)
            if viewModel.tableQuery.isActive {
                Button("Clear") { viewModel.tableQuery = JSONLQuery() }
                    .help("Clear text search and column filters")
            }
        }
        .controlSize(.small)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Column Filters").font(.headline)
                Spacer()
                Button("Cancel") { isEditing = false }
                Button("Apply") { applyDraft() }
                    .keyboardShortcut(.defaultAction)
            }
            Text("Match all conditions")
                .font(.subheadline).fontWeight(.medium)

            ScrollView {
                VStack(spacing: 8) {
                    if draft.conditions.isEmpty {
                        Text("Add a condition to filter a specific column.")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    ForEach($draft.conditions) { $condition in
                        HStack(spacing: 8) {
                            Picker("Column", selection: $condition.key) {
                                if !JSONLTableColumn.fieldKeys(in: columns).contains(condition.key) {
                                    Text("\(condition.key) (not in file)").tag(condition.key)
                                }
                                ForEach(JSONLTableColumn.fieldKeys(in: columns), id: \.self) { key in
                                    Text(verbatim: JSONLTableColumn.field(key).title).tag(key)
                                }
                            }
                            .labelsHidden()
                            .frame(width: 160)
                            .accessibilityLabel("Filter column")
                            Picker("Comparison", selection: $condition.operation) {
                                ForEach(JSONLColumnFilter.Operation.allCases, id: \.self) { operation in
                                    Text(verbatim: operation.title).tag(operation)
                                }
                            }
                            .labelsHidden()
                            .frame(width: 95)
                            .accessibilityLabel("Filter comparison")
                            TextField("Value", text: $condition.value)
                                .textFieldStyle(.roundedBorder)
                                .accessibilityLabel("Filter value for \(condition.key)")
                            Button {
                                draft.conditions.removeAll { $0.id == condition.id }
                            } label: {
                                Image(systemName: "minus.circle")
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Remove condition for \(condition.key)")
                        }
                    }
                }
            }
            .frame(height: min(220, CGFloat(max(1, draft.conditions.count)) * 36))
            Button("Add Condition", systemImage: "plus") {
                if let key = JSONLTableColumn.fieldKeys(in: columns).first {
                    draft.conditions.append(JSONLColumnFilter(key: key))
                }
            }
            .disabled(JSONLTableColumn.fieldKeys(in: columns).isEmpty)

            Text("Contains ignores letter case and searches full nested content. Equals matches exact text, numbers, true, false, null, or a JSON value. Missing fields do not match.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Divider()
            TextField("Search all JSON…", text: $draft.text)
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel("Query text search")
            Toggle("Tagged rows only", isOn: $draft.taggedOnly)
            HStack {
                TextField("Query name", text: $name)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Query name")
                Button(store.query(named: name, for: columns) == nil ? "Save Query" : "Update Query") {
                    if store.save(name: name, query: draft, for: columns) != nil { applyDraft() }
                }
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !draft.isActive
                          || draft.conditions.contains { !JSONLTableColumn.fieldKeys(in: columns).contains($0.key) })
            }
            Text("Saved queries are available in every file with these same column keys.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(width: 560)
        .controlSize(.regular)
    }

    private func applyDraft() {
        viewModel.tableQuery = draft
        isEditing = false
    }
}
