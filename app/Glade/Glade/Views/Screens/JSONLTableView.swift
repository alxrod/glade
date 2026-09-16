import AppKit
import SwiftUI

struct JSONLTableView: View {
    @Bindable var viewModel: GladeViewModel
    var zoomLevel: Double = 1

    var body: some View {
        let rows = viewModel.filteredLines
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search JSON…", text: $viewModel.searchText)
                    .textFieldStyle(.plain)
                    .accessibilityLabel("Search JSON")
                if !viewModel.searchText.isEmpty {
                    Button {
                        viewModel.searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear search")
                }
            }
            .padding(10)
            .background(Color(nsColor: .controlBackgroundColor))
            Divider()

            JSONLRecordsTable(
                rows: rows,
                columns: viewModel.document?.tableColumns ?? [.lineNumber],
                selectedLineID: $viewModel.selectedLineID,
                zoomLevel: zoomLevel,
                onInspect: { viewModel.inspectLine($0) },
                onCloseInspector: { viewModel.isInspectorPresented = false }
            )
            .overlay {
                if rows.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "tablecells")
                            .font(.largeTitle)
                        Text(viewModel.lines.isEmpty ? "No rows in this file" : "No matching rows")
                            .font(.headline)
                        if !viewModel.searchText.isEmpty {
                            Button("Clear Search") { viewModel.searchText = "" }
                        }
                    }
                    .foregroundStyle(.secondary)
                }
            }

            Divider()
            HStack {
                Text("\(rows.count) of \(viewModel.lineCount) rows")
                Spacer()
                Text("Double-click a row to inspect")
                    .lineLimit(1)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .onChange(of: viewModel.searchText) { _, _ in
            // Keep the inspector and copy commands tied to a visible result.
            if !viewModel.filteredLines.contains(where: { $0.id == viewModel.selectedLineID }) {
                viewModel.selectedLineID = viewModel.filteredLines.first?.id
            }
        }
    }
}

/// NSTableView supplies reusable cells, dynamic columns and native double-click
/// handling without attaching competing gestures to every spreadsheet cell.
struct JSONLRecordsTable: NSViewRepresentable {
    let rows: [JSONLLine]
    let columns: [JSONLTableColumn]
    @Binding var selectedLineID: UUID?
    let zoomLevel: Double
    let onInspect: (JSONLLine) -> Void
    let onCloseInspector: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeNSView(context: Context) -> NSScrollView {
        let table = RecordsTableView()
        table.delegate = context.coordinator
        table.dataSource = context.coordinator
        table.target = context.coordinator
        table.doubleAction = #selector(Coordinator.inspectClickedRow(_:))
        table.allowsMultipleSelection = false
        table.allowsEmptySelection = true
        table.allowsColumnReordering = false
        table.allowsColumnResizing = true
        table.columnAutoresizingStyle = .noColumnAutoresizing
        table.usesAlternatingRowBackgroundColors = true
        table.gridStyleMask = [.solidVerticalGridLineMask, .solidHorizontalGridLineMask]
        table.style = .plain
        table.intercellSpacing = NSSize(width: 1, height: 1)
        table.setAccessibilityLabel(String(localized: "JSONL rows"))
        table.setAccessibilityHelp(String(localized: "Select a row and press Return to show its full content."))
        table.onInspectSelection = { [weak coordinator = context.coordinator, weak table] in
            guard let table else { return }
            coordinator?.inspect(row: table.selectedRow)
        }
        table.onCloseInspector = onCloseInspector

        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder
        scroll.documentView = table
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let table = scroll.documentView as? RecordsTableView else { return }
        let coordinator = context.coordinator
        let columnsChanged = coordinator.columns != columns
        let rowsChanged = coordinator.rows.map(\.id) != rows.map(\.id)
        let zoomChanged = coordinator.parent.zoomLevel != zoomLevel
        coordinator.parent = self
        coordinator.isUpdating = true
        defer { coordinator.isUpdating = false }
        coordinator.rows = rows
        coordinator.columns = columns
        table.onCloseInspector = onCloseInspector
        table.rowHeight = max(24, 28 * zoomLevel)

        if columnsChanged {
            for column in table.tableColumns { table.removeTableColumn(column) }
            for column in columns {
                let native = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(column.identifier))
                native.title = column.title
                native.minWidth = column == .lineNumber ? 56 : 90
                native.width = column == .lineNumber ? 64 : (column == .value ? 340 : 180)
                native.maxWidth = column == .lineNumber ? 120 : 1400
                native.resizingMask = .userResizingMask
                table.addTableColumn(native)
            }
        }
        if columnsChanged || rowsChanged || zoomChanged { table.reloadData() }

        let selectedRow = rows.firstIndex { $0.id == selectedLineID }
        let indexes = selectedRow.map { IndexSet(integer: $0) } ?? IndexSet()
        if table.selectedRowIndexes != indexes {
            table.selectRowIndexes(indexes, byExtendingSelection: false)
            if let selectedRow { table.scrollRowToVisible(selectedRow) }
        }
    }

    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
        var parent: JSONLRecordsTable
        var rows: [JSONLLine] = []
        var columns: [JSONLTableColumn] = []
        var isUpdating = false

        init(parent: JSONLRecordsTable) { self.parent = parent }

        func numberOfRows(in tableView: NSTableView) -> Int { rows.count }

        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            guard rows.indices.contains(row),
                  let tableColumn,
                  let column = columns.first(where: { $0.identifier == tableColumn.identifier.rawValue }) else { return nil }
            let identifier = NSUserInterfaceItemIdentifier("record-cell")
            let cell: NSTableCellView
            if let reused = tableView.makeView(withIdentifier: identifier, owner: nil) as? NSTableCellView {
                cell = reused
            } else {
                cell = NSTableCellView()
                cell.identifier = identifier
                let label = NSTextField(labelWithString: "")
                label.translatesAutoresizingMaskIntoConstraints = false
                label.maximumNumberOfLines = 1
                label.lineBreakMode = .byTruncatingTail
                cell.addSubview(label)
                cell.textField = label
                NSLayoutConstraint.activate([
                    label.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 8),
                    label.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -8),
                    label.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                ])
            }
            let line = rows[row]
            let text = column.text(for: line)
            cell.textField?.stringValue = text
            cell.textField?.font = .monospacedSystemFont(ofSize: 12 * parent.zoomLevel, weight: .regular)
            cell.textField?.textColor = column == .lineNumber ? .secondaryLabelColor : .labelColor
            cell.textField?.alignment = column == .lineNumber ? .right : .left
            cell.textField?.setAccessibilityLabel("\(column.title): \(text)")
            cell.toolTip = column == .lineNumber ? line.parseError : text
            return cell
        }

        func tableViewSelectionDidChange(_ notification: Notification) {
            guard !isUpdating, let table = notification.object as? NSTableView else { return }
            parent.selectedLineID = rows.indices.contains(table.selectedRow) ? rows[table.selectedRow].id : nil
        }

        @objc func inspectClickedRow(_ sender: NSTableView) {
            inspect(row: sender.clickedRow)
        }

        func inspect(row: Int) {
            guard rows.indices.contains(row) else { return }
            parent.onInspect(rows[row])
        }
    }
}

final class RecordsTableView: NSTableView {
    var onInspectSelection: (() -> Void)?
    var onCloseInspector: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 36, 76: // Return or numeric keypad Enter
            onInspectSelection?()
        case 53: // Escape
            onCloseInspector?()
        default:
            super.keyDown(with: event)
        }
    }
}
