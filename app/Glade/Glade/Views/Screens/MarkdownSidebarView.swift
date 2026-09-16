import SwiftUI

struct MarkdownSidebarView: View {
    @Bindable var viewModel: GladeViewModel
    @State private var searchState: String = ""

    var body: some View {
        VStack(spacing: 0) {
            if !viewModel.flattenedHeadings.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                        .font(.system(size: 12))
                    TextField("Search headings\u{2026}", text: $searchState)
                        .textFieldStyle(.plain)
                        .font(.callout)
                        .onChange(of: searchState) { _, newValue in
                            viewModel.searchText = newValue
                        }
                    if !searchState.isEmpty {
                        Button {
                            searchState = ""
                            viewModel.searchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                                .font(.system(size: 12))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Text("Clear search"))
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.8))
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.primary.opacity(0.1), lineWidth: 1)
                )
                .padding(.horizontal, 10)
                .padding(.top, 8)
                .padding(.bottom, 6)
            }

            if viewModel.flattenedHeadings.isEmpty {
                emptyStateView
            } else if viewModel.filteredHeadings.isEmpty {
                noResultsView
            } else {
                headingListView
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var noResultsView: some View {
        VStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 36))
                .foregroundColor(.secondary)
            Text("No results")
                .font(.title3)
                .foregroundColor(.secondary)
            Text("No headings match \"\(viewModel.searchText)\"")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.text")
                .font(.system(size: 36))
                .foregroundColor(.secondary)
            Text("No headings found")
                .font(.title3)
                .foregroundColor(.secondary)
            Text("This file has no markdown headings.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private var headingListView: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                List(viewModel.filteredHeadings, selection: Binding(
                    get: { viewModel.selectedHeadingID },
                    set: { viewModel.selectedHeadingID = $0 }
                )) { flat in
                    HeadingRowView(
                        flat: flat,
                        isSelected: viewModel.selectedHeadingID == flat.id
                    )
                    .tag(flat.id)
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.visible)
                    .onTapGesture {
                        viewModel.selectHeading(flat.heading)
                    }
                }
                .listStyle(.sidebar)
                .id(viewModel.id)
                .onChange(of: viewModel.selectedHeadingID) { _, newID in
                    if let newID {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            proxy.scrollTo(newID, anchor: .center)
                        }
                    }
                }
            }

            Divider()
            footerView
        }
    }

    private var footerView: some View {
        let filtered = viewModel.filteredHeadingCount
        let total = viewModel.headingCount
        let isFiltering = !viewModel.searchText.trimmingCharacters(in: .whitespaces).isEmpty
        let label = isFiltering
            ? "\(filtered) of \(total) \(total == 1 ? "heading" : "headings")"
            : "\(total) \(total == 1 ? "heading" : "headings")"

        return HStack {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

struct HeadingRowView: View {
    let flat: FlatHeading
    let isSelected: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            // Indentation based on depth
            if flat.depth > 0 {
                Spacer()
                    .frame(width: CGFloat(flat.depth) * 16)
            }

            Text(flat.heading.title)
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(isSelected ? .primary : .secondary)
                .lineLimit(2)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .contentShape(Rectangle())
        .accessibilityLabel(Text("Heading: \(flat.heading.title)"))
    }
}
