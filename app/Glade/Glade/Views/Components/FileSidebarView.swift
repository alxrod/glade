import SwiftUI

struct FileSidebarView: View {
    @Bindable var manager: TabManager
    let onOpen: () -> Void
    let onRequestClose: (UUID) -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Files")
                    .font(.headline)
                Spacer()
                Button(action: onOpen) {
                    Image(systemName: "plus")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Open files")
                .help("Open files (⌘O)")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            List(selection: Binding(
                get: { manager.activeTabID },
                set: { if let id = $0 { manager.activeTabID = id } }
            )) {
                ForEach(manager.tabs) { tab in
                    HStack(spacing: 8) {
                        Image(systemName: tab.fileType == .markdown ? "doc.richtext" : "tablecells")
                            .foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(verbatim: tab.preferredName)
                                .font(.callout)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            if tab.fileType == .jsonl {
                                Text("\(tab.lineCount) rows")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer(minLength: 0)
                        if tab.isDirty {
                            Circle()
                                .fill(Color.accentColor)
                                .frame(width: 6, height: 6)
                                .accessibilityLabel("Unsaved changes")
                        }
                        Button {
                            onRequestClose(tab.id)
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 10, weight: .medium))
                                .frame(width: 20, height: 24)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel(Text("Close \(tab.preferredName)"))
                    }
                    .padding(.vertical, 4)
                    .tag(tab.id)
                    .help(tab.fileURL?.path ?? tab.displayName)
                    .modifier(FileAliasEditor(tab: tab))
                }
            }
            .listStyle(.sidebar)
            .accessibilityLabel("Open files")
            .overlay {
                if manager.tabs.isEmpty {
                    Text("Open or drop files here")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }

            if let tab = manager.activeTab, tab.fileType == .markdown, !tab.isEditing {
                Divider()
                Text("Outline")
                    .font(.headline)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                MarkdownSidebarView(viewModel: tab)
                    .id(tab.id)
                    .frame(maxHeight: 320)
            }

            Divider()
            Text("\(manager.tabs.count) open files")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
        }
    }
}
