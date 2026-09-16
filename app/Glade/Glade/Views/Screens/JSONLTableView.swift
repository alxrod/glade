import AppKit
import SwiftUI
import OSLog

struct JSONLTableView: View {
    @Bindable var viewModel: GladeViewModel
    @State private var columnLayoutStore = JSONLColumnLayoutStore.shared
    var zoomLevel: Double = 1

    var body: some View {
        let rows = viewModel.filteredLines
        let defaultColumns = viewModel.document?.tableColumns ?? [.lineNumber]
        let hiddenColumns = columnLayoutStore.hiddenColumns(for: defaultColumns)
        let tags = viewModel.rowTags
        let request = TableSearchRequest(documentID: viewModel.lines.first?.id, query: viewModel.tableQuery,
                                         taggedIDs: viewModel.taggedOnly ? Set(tags.keys) : [])
        VStack(spacing: 0) {
            JSONLQueryBar(viewModel: viewModel, columns: columnLayoutStore.columns(for: defaultColumns))
            Divider()
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                JSONSearchField(placeholder: "Search JSON…", accessibilityName: "Search JSON", clearLabel: "Clear search",
                                submittedText: $viewModel.searchText, isSearching: viewModel.searchResults.isSearching)
                    .id(viewModel.queryApplicationID)
                Menu {
                    Button("Show All Hidden Columns") { columnLayoutStore.showAll(in: defaultColumns) }
                    Divider()
                    ForEach(hiddenColumns, id: \.identifier) { column in
                        Button {
                            columnLayoutStore.show(column, in: defaultColumns)
                        } label: {
                            Text(verbatim: column.title)
                        }
                    }
                } label: {
                    Label("Show Hidden Columns (\(hiddenColumns.count))", systemImage: "eye")
                }
                .fixedSize()
                .disabled(hiddenColumns.isEmpty)
                .help("Restore individual hidden columns or show them all")
            }
            .padding(10)
            .background(Color(nsColor: .controlBackgroundColor))
            Divider()

            JSONLRecordsTable(
                rows: rows,
                columns: columnLayoutStore.columns(for: defaultColumns),
                columnWidths: columnLayoutStore.widths(for: defaultColumns),
                hiddenColumnIDs: Set(hiddenColumns.map(\.identifier)),
                rowTags: tags,
                compactTimestampCells: viewModel.document?.compactTimestampCells ?? [:],
                selectedLineID: $viewModel.selectedLineID,
                zoomLevel: zoomLevel,
                onInspect: { viewModel.inspectLine($0) },
                onCloseInspector: { viewModel.isInspectorPresented = false },
                hasSavedColumnOrder: columnLayoutStore.hasSavedOrder(for: defaultColumns),
                onReorderColumns: { columnLayoutStore.save($0, for: defaultColumns) },
                onResetColumnOrder: { columnLayoutStore.reset(for: defaultColumns) },
                onResizeColumn: { columnLayoutStore.saveWidth($1, for: $0, in: defaultColumns) },
                onHideColumn: { columnLayoutStore.hide($0, in: defaultColumns) },
                onTagRow: { viewModel.tagLine($0, color: $1) }
            )
            .overlay {
                if rows.isEmpty && !viewModel.searchResults.isSearching {
                    VStack(spacing: 8) {
                        Image(systemName: "tablecells")
                            .font(.largeTitle)
                        Text(viewModel.lines.isEmpty ? "No rows in this file" : "No matching rows")
                            .font(.headline)
                        if viewModel.tableQuery.isActive {
                            Button("Clear Search and Filters") { viewModel.tableQuery = JSONLQuery() }
                        }
                    }
                    .foregroundStyle(.secondary)
                }
            }

            Divider()
            HStack {
                Text("\(rows.count) of \(viewModel.lineCount) rows")
                if viewModel.searchResults.isSearching { Text("Searching…") }
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
        .task(id: request) {
            await viewModel.searchResults.update(lines: viewModel.lines, query: request.query, taggedIDs: request.taggedIDs)
        }
        .onChange(of: rows.map(\.id)) { _, _ in
            // Keep the inspector and copy commands tied to a visible result.
            if !viewModel.filteredLines.contains(where: { $0.id == viewModel.selectedLineID }) {
                viewModel.selectedLineID = viewModel.filteredLines.first?.id
            }
        }
    }
}

private struct TableSearchRequest: Equatable {
    let documentID: UUID?
    let query: JSONLQuery
    let taggedIDs: Set<UUID>
}

/// NSTableView supplies reusable cells, dynamic columns and native double-click
/// handling without attaching competing gestures to every spreadsheet cell.
struct JSONLRecordsTable: NSViewRepresentable {
    let rows: [JSONLLine]
    let columns: [JSONLTableColumn]
    let columnWidths: [String: Double]
    let hiddenColumnIDs: Set<String>
    let rowTags: [UUID: JSONLRowTagColor]
    let compactTimestampCells: [String: [UUID: String]]
    @Binding var selectedLineID: UUID?
    let zoomLevel: Double
    let onInspect: (JSONLLine) -> Void
    let onCloseInspector: () -> Void
    let hasSavedColumnOrder: Bool
    let onReorderColumns: ([JSONLTableColumn]) -> Void
    let onResetColumnOrder: () -> Void
    let onResizeColumn: (JSONLTableColumn, Double) -> Void
    let onHideColumn: (JSONLTableColumn) -> Void
    let onTagRow: (JSONLLine, JSONLRowTagColor?) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeNSView(context: Context) -> NSScrollView {
        let table = RecordsTableView()
        table.delegate = context.coordinator
        table.dataSource = context.coordinator
        table.target = context.coordinator
        table.doubleAction = #selector(Coordinator.inspectClickedRow(_:))
        table.allowsMultipleSelection = false
        table.allowsEmptySelection = true
        table.allowsColumnReordering = true
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
        table.cellContextMenu = { [weak coordinator = context.coordinator] rowIndex, columnIndex in
            coordinator?.menu(forRowAt: rowIndex, columnAt: columnIndex)
        }
        let header = RecordsTableHeaderView(frame: table.headerView?.frame ?? NSRect(x: 0, y: 0, width: 0, height: 24))
        header.columnContextMenu = { [weak coordinator = context.coordinator] columnIndex in
            coordinator?.menu(forHeaderAt: columnIndex)
        }
        header.toolTip = String(localized: "Drag property headers to rearrange columns. Right-click to hide a column or reset the order.")
        table.headerView = header

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
        let visibilityChanged = coordinator.parent.hiddenColumnIDs != hiddenColumnIDs
        let tagsChanged = coordinator.parent.rowTags != rowTags
        coordinator.parent = self
        coordinator.isUpdating = true
        defer { coordinator.isUpdating = false }
        coordinator.rows = rows
        coordinator.columns = columns
        table.onCloseInspector = onCloseInspector
        table.rowHeight = max(24, 28 * zoomLevel)

        if columnsChanged {
            let identifiers = Set(columns.map(\.identifier))
            for native in table.tableColumns where !identifiers.contains(native.identifier.rawValue) {
                table.removeTableColumn(native)
            }
            for column in columns where !table.tableColumns.contains(where: { $0.identifier.rawValue == column.identifier }) {
                let native = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(column.identifier))
                native.title = column == .lineNumber ? "" : column.title
                native.minWidth = column.minimumWidth
                native.maxWidth = column.maximumWidth
                native.width = columnWidths[column.identifier] ?? column.defaultWidth
                native.resizingMask = .userResizingMask
                table.addTableColumn(native)
            }
            // Reuse native columns so widths survive a saved-order update from
            // another file or window. Programmatic moves must never save defaults.
            for (index, column) in columns.enumerated() {
                let current = table.column(withIdentifier: NSUserInterfaceItemIdentifier(column.identifier))
                if current != index { table.moveColumn(current, toColumn: index) }
            }
        }
        for column in columns {
            guard let native = table.tableColumn(withIdentifier: NSUserInterfaceItemIdentifier(column.identifier)) else { continue }
            let width = columnWidths[column.identifier] ?? column.defaultWidth
            if abs(native.width - width) > 0.5 { native.width = width }
            let isHidden = hiddenColumnIDs.contains(column.identifier)
            if native.isHidden != isHidden { native.isHidden = isHidden }
        }
        // Re-parsing creates new line IDs along with the timestamp presentation.
        if columnsChanged || rowsChanged || zoomChanged || visibilityChanged || tagsChanged { table.reloadData() }

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

        func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
            guard rows.indices.contains(row) else { return nil }
            let view = TaggedRecordRowView()
            view.tagColor = parent.rowTags[rows[row].id]?.nativeColor
            return view
        }

        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            guard rows.indices.contains(row),
                  let tableColumn,
                  let column = columns.first(where: { $0.identifier == tableColumn.identifier.rawValue }) else { return nil }
            let identifier = NSUserInterfaceItemIdentifier("record-cell")
            let cell: TaggedRecordCellView
            if let reused = tableView.makeView(withIdentifier: identifier, owner: nil) as? TaggedRecordCellView {
                cell = reused
            } else {
                cell = TaggedRecordCellView()
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
            let rawText = column.text(for: line)
            let text = parent.compactTimestampCells[column.identifier]?[line.id] ?? rawText
            cell.textField?.stringValue = text
            cell.textField?.font = .monospacedSystemFont(ofSize: 12 * parent.zoomLevel, weight: .regular)
            cell.textField?.textColor = column == .lineNumber ? .secondaryLabelColor : .labelColor
            cell.textField?.alignment = column == .lineNumber ? .right : .left
            cell.textField?.setAccessibilityLabel("\(column.title): \(rawText)")
            let tag = parent.rowTags[line.id]
            cell.tagIndicator.image = column == .lineNumber ? tag?.menuImage : nil
            cell.tagIndicator.isHidden = column != .lineNumber || tag == nil
            if column == .lineNumber, let tag {
                cell.textField?.setAccessibilityLabel(String(localized: "Line \(line.lineNumber), \(tag.title) tag"))
            }
            cell.toolTip = column == .lineNumber ? line.parseError : rawText
            return cell
        }

        func tableViewSelectionDidChange(_ notification: Notification) {
            guard !isUpdating, let table = notification.object as? NSTableView else { return }
            parent.selectedLineID = rows.indices.contains(table.selectedRow) ? rows[table.selectedRow].id : nil
        }

        func tableView(_ tableView: NSTableView, shouldReorderColumn columnIndex: Int, toColumn newColumnIndex: Int) -> Bool {
            Logger(subsystem: "net.alexbrodriguez.glade", category: "ColumnOrdering").debug("Column reorder request from \(columnIndex) to \(newColumnIndex), available columns \(self.columns.count)")
            guard columns.indices.contains(columnIndex), case .field = columns[columnIndex] else { return false }
            // AppKit first asks whether a drag may start, with destination -1.
            if newColumnIndex == -1 { return true }
            guard columns.indices.contains(newColumnIndex) else { return false }
            // The line gutter and optional raw-content column are not JSON keys.
            if case .field = columns[newColumnIndex] { return true }
            return false
        }

        func tableViewColumnDidMove(_ notification: Notification) {
            Logger(subsystem: "net.alexbrodriguez.glade", category: "ColumnOrdering").debug("Column moved; applying programmatic update: \(self.isUpdating)")
            guard !isUpdating, let table = notification.object as? NSTableView else { return }
            let reordered = table.tableColumns.compactMap { native in
                columns.first { $0.identifier == native.identifier.rawValue }
            }
            guard reordered.count == columns.count, reordered != columns else { return }
            columns = reordered
            parent.onReorderColumns(reordered)
        }

        func tableViewColumnDidResize(_ notification: Notification) {
            guard !isUpdating,
                  let native = notification.userInfo?["NSTableColumn"] as? NSTableColumn,
                  let column = columns.first(where: { $0.identifier == native.identifier.rawValue }) else { return }
            parent.onResizeColumn(column, native.width)
        }

        func menu(forColumnAt index: Int) -> NSMenu? {
            guard columns.indices.contains(index), columns[index] != .lineNumber else { return nil }
            let column = columns[index]
            let menu = NSMenu()
            let item = NSMenuItem(title: String(localized: "Hide Column “\(column.title)”"),
                                  action: #selector(hideColumn(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = column.identifier
            menu.addItem(item)
            return menu
        }

        func menu(forHeaderAt index: Int) -> NSMenu {
            let menu = menu(forColumnAt: index) ?? NSMenu()
            menu.autoenablesItems = false
            if !menu.items.isEmpty { menu.addItem(.separator()) }
            let reset = NSMenuItem(title: String(localized: "Reset Column Order"),
                                   action: #selector(resetColumnOrder), keyEquivalent: "")
            reset.target = self
            reset.isEnabled = parent.hasSavedColumnOrder
            menu.addItem(reset)
            return menu
        }

        func menu(forRowAt row: Int, columnAt column: Int) -> NSMenu? {
            guard rows.indices.contains(row) else { return nil }
            let line = rows[row]
            let menu = menu(forColumnAt: column) ?? NSMenu()
            menu.autoenablesItems = false
            if !menu.items.isEmpty { menu.addItem(.separator()) }
            let title = NSMenuItem(title: String(localized: "Tag Row"), action: nil, keyEquivalent: "")
            title.isEnabled = false
            menu.addItem(title)
            for color in JSONLRowTagColor.allCases {
                let item = NSMenuItem(title: color.title, action: #selector(tagRow(_:)), keyEquivalent: "")
                item.image = color.menuImage
                item.state = parent.rowTags[line.id] == color ? .on : .off
                item.target = self
                item.representedObject = RowTagAction(lineID: line.id, color: color)
                menu.addItem(item)
            }
            let remove = NSMenuItem(title: String(localized: "Remove Tag"), action: #selector(tagRow(_:)), keyEquivalent: "")
            remove.image = NSImage(systemSymbolName: "xmark.circle", accessibilityDescription: String(localized: "Remove tag"))
            remove.target = self
            remove.representedObject = RowTagAction(lineID: line.id, color: nil)
            remove.isEnabled = parent.rowTags[line.id] != nil
            menu.addItem(remove)
            return menu
        }

        private struct RowTagAction {
            let lineID: UUID
            let color: JSONLRowTagColor?
        }

        @objc func tagRow(_ sender: NSMenuItem) {
            guard let action = sender.representedObject as? RowTagAction,
                  let line = rows.first(where: { $0.id == action.lineID }) else { return }
            parent.onTagRow(line, action.color)
        }

        @objc func hideColumn(_ sender: NSMenuItem) {
            guard let identifier = sender.representedObject as? String,
                  let column = columns.first(where: { $0.identifier == identifier }) else { return }
            parent.onHideColumn(column)
        }

        @objc func resetColumnOrder() {
            parent.onResetColumnOrder()
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
    var cellContextMenu: ((Int, Int) -> NSMenu?)?

    override func menu(for event: NSEvent) -> NSMenu? {
        let location = convert(event.locationInWindow, from: nil)
        guard row(at: location) >= 0 else { return super.menu(for: event) }
        return cellContextMenu?(row(at: location), column(at: location)) ?? super.menu(for: event)
    }

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

final class RecordsTableHeaderView: NSTableHeaderView {
    var columnContextMenu: ((Int) -> NSMenu?)?

    override func menu(for event: NSEvent) -> NSMenu? {
        columnContextMenu?(column(at: convert(event.locationInWindow, from: nil))) ?? super.menu(for: event)
    }
}

final class TaggedRecordRowView: NSTableRowView {
    var tagColor: NSColor?

    override func drawBackground(in dirtyRect: NSRect) {
        super.drawBackground(in: dirtyRect)
        if let tagColor {
            tagColor.withAlphaComponent(0.14).setFill()
            dirtyRect.fill(using: .sourceOver)
        }
    }
}

final class TaggedRecordCellView: NSTableCellView {
    let tagIndicator = NSImageView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        tagIndicator.translatesAutoresizingMaskIntoConstraints = false
        tagIndicator.isHidden = true
        addSubview(tagIndicator)
        NSLayoutConstraint.activate([
            tagIndicator.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            tagIndicator.centerYAnchor.constraint(equalTo: centerYAnchor),
            tagIndicator.widthAnchor.constraint(equalToConstant: 10),
            tagIndicator.heightAnchor.constraint(equalToConstant: 10),
        ])
    }

    required init?(coder: NSCoder) { nil }
}

extension JSONLRowTagColor {
    var nativeColor: NSColor {
        switch self {
        case .red: return .systemRed
        case .orange: return .systemOrange
        case .yellow: return .systemYellow
        case .green: return .systemGreen
        case .teal: return .systemTeal
        case .blue: return .systemBlue
        case .purple: return .systemPurple
        case .gray: return .systemGray
        }
    }

    var menuImage: NSImage {
        NSImage(size: NSSize(width: 14, height: 14), flipped: false) { rect in
            self.nativeColor.setFill()
            NSBezierPath(ovalIn: rect.insetBy(dx: 1, dy: 1)).fill()
            return true
        }
    }
}
