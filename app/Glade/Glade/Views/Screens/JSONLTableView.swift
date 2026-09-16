import AppKit
import SwiftUI
import OSLog

struct JSONLTableView: View {
    @Bindable var viewModel: GladeViewModel
    @State private var columnLayoutStore = JSONLColumnLayoutStore.shared

    var body: some View {
        let rows = viewModel.filteredLines
        let rowsRevision = viewModel.tableRowsRevision
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
                rowsRevision: rowsRevision,
                columns: columnLayoutStore.columns(for: defaultColumns),
                columnWidths: columnLayoutStore.widths(for: defaultColumns),
                hiddenColumnIDs: Set(hiddenColumns.map(\.identifier)),
                rowTags: tags,
                compactTimestampCells: viewModel.document?.compactTimestampCells ?? [:],
                selectedLineIDs: viewModel.selectedLineIDs,
                onSelectionChanged: { viewModel.selectLines(withIDs: $0, primaryID: $1) },
                onInspect: { viewModel.inspectLine($0) },
                onCloseInspector: { viewModel.isInspectorPresented = false },
                hasSavedColumnOrder: columnLayoutStore.hasSavedOrder(for: defaultColumns),
                onReorderColumns: { columnLayoutStore.save($0, for: defaultColumns) },
                onResetColumnOrder: { columnLayoutStore.reset(for: defaultColumns) },
                onResizeColumn: { columnLayoutStore.saveWidth($1, for: $0, in: defaultColumns) },
                onHideColumn: { columnLayoutStore.hide($0, in: defaultColumns) },
                onTagRows: { viewModel.tagLines($0, color: $1) }
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
                if viewModel.selectedLineIDs.count > 1 {
                    Text("\(viewModel.selectedLineIDs.count) selected")
                }
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
        .onChange(of: rowsRevision) { _, _ in
            // Keep selections, the inspector and copy commands tied to visible results.
            viewModel.reconcileSelection(with: rows)
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
    let rowsRevision: UUID
    let columns: [JSONLTableColumn]
    let columnWidths: [String: Double]
    let hiddenColumnIDs: Set<String>
    let rowTags: [UUID: JSONLRowTagColor]
    let compactTimestampCells: [String: [UUID: String]]
    let selectedLineIDs: Set<UUID>
    let onSelectionChanged: (Set<UUID>, UUID?) -> Void
    let onInspect: (JSONLLine) -> Void
    let onCloseInspector: () -> Void
    let hasSavedColumnOrder: Bool
    let onReorderColumns: ([JSONLTableColumn]) -> Void
    let onResetColumnOrder: () -> Void
    let onResizeColumn: (JSONLTableColumn, Double) -> Void
    let onHideColumn: (JSONLTableColumn) -> Void
    let onTagRows: ([JSONLLine], JSONLRowTagColor?) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeNSView(context: Context) -> NSScrollView {
        let table = RecordsTableView()
        table.delegate = context.coordinator
        table.dataSource = context.coordinator
        table.target = context.coordinator
        table.doubleAction = #selector(Coordinator.inspectClickedRow(_:))
        table.allowsMultipleSelection = true
        table.allowsEmptySelection = true
        table.usesAutomaticRowHeights = false
        table.rowHeight = 28
        table.allowsColumnReordering = true
        table.allowsColumnResizing = true
        table.columnAutoresizingStyle = .noColumnAutoresizing
        table.usesAlternatingRowBackgroundColors = true
        table.gridStyleMask = [.solidVerticalGridLineMask, .solidHorizontalGridLineMask]
        table.style = .plain
        table.intercellSpacing = NSSize(width: 1, height: 1)
        table.setAccessibilityLabel(String(localized: "JSONL rows"))
        table.setAccessibilityHelp(String(localized: "Shift-click to select a range, Command-click to select individual rows, or Command-A to select all visible rows. Right-click to tag selected rows. Press Return to inspect a row."))
        table.onInspectSelection = { [weak coordinator = context.coordinator, weak table] in
            guard let table else { return }
            coordinator?.inspect(row: table.selectedRow)
        }
        table.onCloseInspector = onCloseInspector
        table.cellContextMenu = { [weak coordinator = context.coordinator, weak table] rowIndex, columnIndex in
            coordinator?.menu(forRowAt: rowIndex, columnAt: columnIndex, selection: table?.selectedRowIndexes ?? [])
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
        let rowsChanged = coordinator.rowsRevision != rowsRevision
        let visibilityChanged = coordinator.parent.hiddenColumnIDs != hiddenColumnIDs
        let tagsChanged = coordinator.parent.rowTags != rowTags
        let selectionChanged = coordinator.parent.selectedLineIDs != selectedLineIDs
        coordinator.parent = self
        coordinator.isUpdating = true
        defer { coordinator.isUpdating = false }
        if rowsChanged {
            coordinator.rows = rows
            coordinator.rowsRevision = rowsRevision
            coordinator.rowIndexes = Dictionary(uniqueKeysWithValues: rows.enumerated().map { ($0.element.id, $0.offset) })
        }
        if columnsChanged {
            coordinator.columns = columns
            coordinator.columnsByIdentifier = Dictionary(uniqueKeysWithValues: columns.map { ($0.identifier, $0) })
        }
        table.onCloseInspector = onCloseInspector

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
        let needsReload = columnsChanged || rowsChanged || visibilityChanged
        if needsReload {
            table.reloadData()
        } else if tagsChanged {
            // Tags change decoration only. Keep the native cells and scroll position.
            coordinator.refreshVisibleTags(in: table)
        }

        if needsReload || selectionChanged {
            let indexes = IndexSet(selectedLineIDs.compactMap { coordinator.rowIndexes[$0] })
            if table.selectedRowIndexes != indexes {
                table.selectRowIndexes(indexes, byExtendingSelection: false)
                if indexes.count == 1, let selectedRow = indexes.first { table.scrollRowToVisible(selectedRow) }
            }
        }
    }

    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
        var parent: JSONLRecordsTable
        var rows: [JSONLLine] = []
        var rowsRevision: UUID?
        var rowIndexes: [UUID: Int] = [:]
        var columns: [JSONLTableColumn] = []
        var columnsByIdentifier: [String: JSONLTableColumn] = [:]
        var isUpdating = false
        let font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        let textHeight: CGFloat
        private let previews = NSCache<NSUUID, PreviewBox>()

        init(parent: JSONLRecordsTable) {
            self.parent = parent
            textHeight = ceil(font.ascender - font.descender + font.leading) + 2
            previews.countLimit = 512
            previews.totalCostLimit = 4 * 1_024 * 1_024
        }

        private final class PreviewBox: NSObject {
            let value: JSONLTableRowPreview
            init(_ line: JSONLLine) { value = JSONLTableRowPreview(line: line) }
        }

        private func preview(for line: JSONLLine) -> JSONLTableRowPreview {
            if let cached = previews.object(forKey: line.id as NSUUID) { return cached.value }
            let box = PreviewBox(line)
            previews.setObject(box, forKey: line.id as NSUUID, cost: box.value.estimatedByteCount)
            return box.value
        }

        func numberOfRows(in tableView: NSTableView) -> Int { rows.count }

        func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
            guard rows.indices.contains(row) else { return nil }
            let identifier = NSUserInterfaceItemIdentifier("record-row")
            let view = tableView.makeView(withIdentifier: identifier, owner: nil) as? TaggedRecordRowView ?? TaggedRecordRowView()
            view.identifier = identifier
            view.tagColor = parent.rowTags[rows[row].id]?.nativeColor
            return view
        }

        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            guard rows.indices.contains(row),
                  let tableColumn,
                  let column = columnsByIdentifier[tableColumn.identifier.rawValue] else { return nil }
            let identifier = NSUserInterfaceItemIdentifier("record-cell")
            let cell: TaggedRecordCellView
            if let reused = tableView.makeView(withIdentifier: identifier, owner: nil) as? TaggedRecordCellView {
                cell = reused
            } else {
                cell = TaggedRecordCellView()
                cell.identifier = identifier
            }
            let line = rows[row]
            let rawText = preview(for: line).text(for: column)
            let text = parent.compactTimestampCells[column.identifier]?[line.id] ?? rawText
            cell.textField?.stringValue = text
            cell.textField?.font = font
            cell.textHeight = textHeight
            cell.textField?.textColor = column == .lineNumber ? .secondaryLabelColor : .labelColor
            cell.textField?.alignment = column == .lineNumber ? .right : .left
            cell.textField?.setAccessibilityLabel("\(column.title): \(rawText)")
            cell.tagColor = nil
            if column == .lineNumber { configureTag(in: cell, for: line) }
            cell.toolTip = column == .lineNumber ? line.parseError : rawText
            return cell
        }

        private func configureTag(in cell: TaggedRecordCellView, for line: JSONLLine) {
            let tag = parent.rowTags[line.id]
            cell.tagColor = tag?.nativeColor
            cell.textField?.setAccessibilityLabel(tag.map {
                String(localized: "Line \(line.lineNumber), \($0.title) tag")
            } ?? "\(JSONLTableColumn.lineNumber.title): \(line.lineNumber)")
        }

        func refreshVisibleTags(in table: NSTableView) {
            let gutter = table.column(withIdentifier: NSUserInterfaceItemIdentifier(JSONLTableColumn.lineNumber.identifier))
            table.enumerateAvailableRowViews { view, index in
                guard self.rows.indices.contains(index) else { return }
                let line = self.rows[index]
                (view as? TaggedRecordRowView)?.tagColor = self.parent.rowTags[line.id]?.nativeColor
                if gutter >= 0, let cell = table.view(atColumn: gutter, row: index, makeIfNecessary: false) as? TaggedRecordCellView {
                    self.configureTag(in: cell, for: line)
                }
            }
        }

        func tableViewSelectionDidChange(_ notification: Notification) {
            guard !isUpdating, let table = notification.object as? NSTableView else { return }
            let ids = Set(table.selectedRowIndexes.compactMap { rows.indices.contains($0) ? rows[$0].id : nil })
            let primaryID = rows.indices.contains(table.selectedRow) ? rows[table.selectedRow].id : nil
            parent.onSelectionChanged(ids, primaryID)
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

        func menu(forRowAt row: Int, columnAt column: Int, selection: IndexSet) -> NSMenu? {
            guard rows.indices.contains(row) else { return nil }
            let indexes = selection.contains(row) ? selection : IndexSet(integer: row)
            let lineIDs = Set(indexes.compactMap { rows.indices.contains($0) ? rows[$0].id : nil })
            let selectedTags = lineIDs.compactMap { parent.rowTags[$0] }
            let menu = menu(forColumnAt: column) ?? NSMenu()
            menu.autoenablesItems = false
            if !menu.items.isEmpty { menu.addItem(.separator()) }
            let title = NSMenuItem(title: lineIDs.count == 1 ? String(localized: "Tag Row") : String(localized: "Tag \(lineIDs.count) Rows"), action: nil, keyEquivalent: "")
            title.isEnabled = false
            menu.addItem(title)
            for color in JSONLRowTagColor.allCases {
                let item = NSMenuItem(title: color.title, action: #selector(tagRows(_:)), keyEquivalent: "")
                item.image = color.menuImage
                let matchingCount = selectedTags.filter { $0 == color }.count
                item.state = matchingCount == lineIDs.count ? .on : (matchingCount > 0 ? .mixed : .off)
                item.target = self
                item.representedObject = RowTagAction(lineIDs: lineIDs, color: color)
                menu.addItem(item)
            }
            let remove = NSMenuItem(title: lineIDs.count == 1 ? String(localized: "Remove Tag") : String(localized: "Remove Tags"), action: #selector(tagRows(_:)), keyEquivalent: "")
            remove.image = NSImage(systemSymbolName: "xmark.circle", accessibilityDescription: String(localized: "Remove tag"))
            remove.target = self
            remove.representedObject = RowTagAction(lineIDs: lineIDs, color: nil)
            remove.isEnabled = !selectedTags.isEmpty
            menu.addItem(remove)
            return menu
        }

        private struct RowTagAction {
            let lineIDs: Set<UUID>
            let color: JSONLRowTagColor?
        }

        @objc func tagRows(_ sender: NSMenuItem) {
            guard let action = sender.representedObject as? RowTagAction else { return }
            parent.onTagRows(rows.filter { action.lineIDs.contains($0.id) }, action.color)
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
        let clickedRow = row(at: location)
        guard clickedRow >= 0 else { return super.menu(for: event) }
        window?.makeFirstResponder(self)
        if !selectedRowIndexes.contains(clickedRow) {
            selectRowIndexes(IndexSet(integer: clickedRow), byExtendingSelection: false)
        }
        return cellContextMenu?(clickedRow, column(at: location)) ?? super.menu(for: event)
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
    var tagColor: NSColor? {
        didSet { if oldValue != tagColor { needsDisplay = true } }
    }

    override func drawBackground(in dirtyRect: NSRect) {
        super.drawBackground(in: dirtyRect)
        if let tagColor {
            tagColor.withAlphaComponent(0.14).setFill()
            dirtyRect.fill(using: .sourceOver)
        }
    }
}

final class TaggedRecordCellView: NSTableCellView {
    var tagColor: NSColor? {
        didSet { if oldValue != tagColor { needsDisplay = true } }
    }
    var textHeight: CGFloat = 18 {
        didSet { if oldValue != textHeight { needsLayout = true } }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        let label = NSTextField(labelWithString: "")
        label.maximumNumberOfLines = 1
        label.lineBreakMode = .byTruncatingTail
        addSubview(label)
        textField = label
    }

    required init?(coder: NSCoder) { nil }

    override func layout() {
        super.layout()
        // Fixed-height spreadsheet cells do not need a constraint solver.
        textField?.frame = NSRect(x: 8, y: floor((bounds.height - textHeight) / 2),
                                 width: max(0, bounds.width - 16), height: textHeight)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        if let tagColor {
            tagColor.setFill()
            NSBezierPath(ovalIn: NSRect(x: 6, y: (bounds.height - 10) / 2, width: 10, height: 10)).fill()
        }
    }
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
