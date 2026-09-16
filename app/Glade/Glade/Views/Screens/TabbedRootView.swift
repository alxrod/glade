import AppKit
import SwiftUI
import UniformTypeIdentifiers

enum PendingDirtyAction: Identifiable {
    case exitEditing(tabID: UUID)
    case closeTab(tabID: UUID)

    var id: String {
        switch self {
        case .exitEditing(let id): return "exit-\(id)"
        case .closeTab(let id): return "close-\(id)"
        }
    }

    var tabID: UUID {
        switch self {
        case .exitEditing(let id), .closeTab(let id): return id
        }
    }
}

struct TabbedRootView: View {
    @State private var manager: TabManager
    @State private var showFileImporter = false
    @State private var importErrorMessage: String?
    @State private var windowNumber: Int?
    @State private var pendingDirtyAction: PendingDirtyAction?
    @AppStorage("detailZoomLevel") private var zoomLevel: Double = 1.0

    private let initialURLs: [URL]

    init(initialURLs: [URL] = []) {
        _manager = State(initialValue: TabManager())
        self.initialURLs = initialURLs
    }

    private var workspaceView: some View {
        NavigationSplitView {
            FileSidebarView(
                manager: manager,
                onOpen: { showFileImporter = true },
                onRequestClose: { requestCloseTab(id: $0) }
            )
            .navigationSplitViewColumnWidth(min: 190, ideal: 240, max: 360)
        } detail: {
            if let activeTab = manager.activeTab {
                activeTabView(for: activeTab)
            } else {
                emptyStateView
            }
        }
        .toolbar(removing: .sidebarToggle)
        .navigationTitle(manager.activeTab?.fileName ?? "Glade")
        .frame(minWidth: 900, minHeight: 500)
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button(action: { showFileImporter = true }) {
                    Label("Open File", systemImage: "folder")
                }
                .help("Open a file")
            }
        }
    }

    var body: some View {
        workspaceView
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [
                .jsonl,
                .json,
                .text,
                .plainText,
                UTType(filenameExtension: "jsonl") ?? .text,
                UTType(filenameExtension: "md") ?? .text,
                UTType(filenameExtension: "markdown") ?? .text,
            ],
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls):
                Task {
                    for url in urls {
                        await manager.openFile(from: url)
                    }
                }
            case .failure(let error):
                if let activeTab = manager.activeTab {
                    activeTab.errorMessage = error.localizedDescription
                } else {
                    importErrorMessage = error.localizedDescription
                }
            }
        }
        .alert("Import Error", isPresented: Binding(
            get: { importErrorMessage != nil },
            set: { if !$0 { importErrorMessage = nil } }
        )) {
            Button("OK") { importErrorMessage = nil }
        } message: {
            Text(importErrorMessage ?? "")
        }
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            handleDrop(providers: providers)
        }
        .background(WindowAccessor { window in
            windowNumber = window.windowNumber
        })
        .task {
            for url in initialURLs {
                await manager.openFile(from: url)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .openFileURL)) { notification in
            let target = notification.userInfo?["windowNumber"] as? Int
            guard target == nil || target == windowNumber else { return }
            let urls: [URL]
            if let array = notification.object as? [URL] {
                urls = array
            } else if let single = notification.object as? URL {
                urls = [single]
            } else {
                return
            }
            Task {
                for url in urls {
                    await manager.openFile(from: url)
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .switchToPreviousTab)) { _ in
            manager.switchToPreviousTab()
        }
        .onReceive(NotificationCenter.default.publisher(for: .switchToNextTab)) { _ in
            manager.switchToNextTab()
        }
        .onChange(of: manager.lastOpenError) { _, newValue in
            if let error = newValue {
                importErrorMessage = error
                manager.lastOpenError = nil
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .openFile)) { _ in
            showFileImporter = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .closeTab)) { _ in
            if let id = manager.activeTabID {
                requestCloseTab(id: id)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .saveFile)) { _ in
            guard let tab = manager.activeTab, tab.isEditing else { return }
            Task { await tab.save() }
        }
        .alert(
            dirtyAlertTitle,
            isPresented: Binding(
                get: { pendingDirtyAction != nil },
                set: { if !$0 { pendingDirtyAction = nil } }
            ),
            presenting: pendingDirtyAction
        ) { action in
            Button("Save") {
                resolveDirtyAction(action, save: true)
            }
            Button("Don't Save", role: .destructive) {
                resolveDirtyAction(action, save: false)
            }
            Button("Cancel", role: .cancel) {
                pendingDirtyAction = nil
            }
        } message: { _ in
            Text("Your changes will be lost if you don't save them.")
        }
        .onReceive(NotificationCenter.default.publisher(for: .zoomIn)) { _ in
            zoomIn()
        }
        .onReceive(NotificationCenter.default.publisher(for: .zoomOut)) { _ in
            zoomOut()
        }
        .onReceive(NotificationCenter.default.publisher(for: .zoomReset)) { _ in
            zoomLevel = 1.0
        }
    }

    @ViewBuilder
    private func activeTabView(for tab: GladeViewModel) -> some View {
        HSplitView {
            if tab.isEditing {
                zoomedContent { editorView(for: tab) }
            } else if tab.fileType == .jsonl {
                JSONLTableView(viewModel: tab, zoomLevel: zoomLevel)
                    .id(tab.id)
                    .frame(minWidth: 320, maxWidth: .infinity, maxHeight: .infinity)
                if tab.isInspectorPresented {
                    zoomedContent {
                        DetailView(
                            line: tab.selectedLine,
                            searchText: Binding(get: { tab.inspectorSearchText }, set: { tab.inspectorSearchText = $0 }),
                            onClose: { tab.isInspectorPresented = false }
                        )
                    }
                    .frame(minWidth: 320, idealWidth: 440, maxWidth: 700)
                }
            } else {
                zoomedContent { detailContent(for: tab) }
            }
        }
        .toolbar { tabToolbar(for: tab) }
        .overlay { loadingOverlay(for: tab) }
        .overlay(alignment: .bottom) { exportToast(for: tab) }
        .alert("Error", isPresented: Binding(
            get: { tab.errorMessage != nil },
            set: { if !$0 { tab.errorMessage = nil } }
        )) {
            Button("OK") { tab.errorMessage = nil }
        } message: {
            Text(tab.errorMessage ?? "")
        }
        .sheet(isPresented: Binding(
            get: { tab.showJumpToLine },
            set: { tab.showJumpToLine = $0 }
        )) {
            JumpToLineView(viewModel: tab)
        }
        .onReceive(NotificationCenter.default.publisher(for: .jumpToLine)) { _ in
            guard !tab.isEditing, !tab.lines.isEmpty else { return }
            tab.showJumpToLine = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .exportPrettyJSON)) { _ in
            guard !tab.isEditing else { return }
            tab.exportSelectedLineAsPrettyJSON()
        }
        .onReceive(NotificationCenter.default.publisher(for: .selectNextLine)) { _ in
            guard !tab.isEditing else { return }
            tab.selectNextLine()
        }
        .onReceive(NotificationCenter.default.publisher(for: .selectPreviousLine)) { _ in
            guard !tab.isEditing else { return }
            tab.selectPreviousLine()
        }
        .onReceive(NotificationCenter.default.publisher(for: .exportRawJSON)) { _ in
            guard !tab.isEditing else { return }
            tab.exportSelectedLineAsRawJSON()
        }
    }

    @ToolbarContentBuilder
    private func tabToolbar(for tab: GladeViewModel) -> some ToolbarContent {
        if tab.fileType == .jsonl && !tab.isEditing {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    tab.exportSelectedLineAsPrettyJSON()
                } label: {
                    if tab.exportCopied {
                        Label("Copied!", systemImage: "checkmark")
                    } else {
                        Label("Copy as JSON", systemImage: "doc.on.clipboard")
                    }
                }
                .help("Copy selected line as pretty-printed JSON (\u{2318}\u{21E7}C)")
                .disabled(tab.selectedLine == nil)
            }
        }
        if tab.fileType == .jsonl && !tab.isEditing {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    tab.isInspectorPresented.toggle()
                } label: {
                    Label("Line Inspector", systemImage: "sidebar.right")
                }
                .help(tab.isInspectorPresented ? "Hide line inspector" : "Show line inspector")
                .disabled(tab.selectedLine == nil && !tab.isInspectorPresented)
            }
        }
        if tab.canEdit {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    if tab.isEditing {
                        requestExitEditing(for: tab)
                    } else {
                        tab.beginEditing()
                    }
                } label: {
                    if tab.isEditing {
                        Label("Done", systemImage: "checkmark.circle")
                    } else {
                        Label("Edit", systemImage: "square.and.pencil")
                    }
                }
                .help(tab.isEditing ? "Finish editing" : "Edit this file")
            }
        }
        ToolbarItem(placement: .primaryAction) {
            HStack(spacing: 4) {
                Button { zoomOut() } label: {
                    Image(systemName: "minus.magnifyingglass")
                }
                .accessibilityLabel("Zoom out")
                .help("Zoom out (\u{2318}-)")
                .disabled(zoomLevel <= 0.5)

                Text(verbatim: "\(Int(zoomLevel * 100))%")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(width: 36)

                Button { zoomIn() } label: {
                    Image(systemName: "plus.magnifyingglass")
                }
                .accessibilityLabel("Zoom in")
                .help("Zoom in (\u{2318}+)")
                .disabled(zoomLevel >= 2.0)
            }
        }
    }

    @ViewBuilder
    private func loadingOverlay(for tab: GladeViewModel) -> some View {
        if tab.isLoading {
            ZStack {
                Color.black.opacity(0.2)
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Loading...")
                        .foregroundColor(.secondary)
                }
                .padding(24)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    @ViewBuilder
    private func exportToast(for tab: GladeViewModel) -> some View {
        Group {
            if tab.exportCopied {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("Copied as pretty JSON")
                        .font(.callout)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
                .shadow(radius: 4)
                .padding(.bottom, 20)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.3), value: tab.exportCopied)
    }

    private func zoomedContent<Content: View>(@ViewBuilder content: @escaping () -> Content) -> some View {
        GeometryReader { geo in
            content()
                .frame(
                    width: geo.size.width / zoomLevel,
                    height: geo.size.height / zoomLevel,
                    alignment: .topLeading
                )
                .scaleEffect(zoomLevel, anchor: .topLeading)
        }
    }

    @ViewBuilder
    private func detailContent(for tab: GladeViewModel) -> some View {
        if tab.isEditing {
            editorView(for: tab)
        } else {
            switch tab.fileType {
            case .jsonl:
                DetailView(line: tab.selectedLine, searchText: Binding(
                    get: { tab.inspectorSearchText }, set: { tab.inspectorSearchText = $0 }
                ))
            case .markdown:
                if let mdDoc = tab.markdownDocument {
                    MarkdownDetailView(
                        document: mdDoc,
                        scrollTarget: tab.scrollTarget,
                        headingLookup: tab.headingLineIndexToID,
                        onVisibleHeadingChanged: { headingID in
                            if tab.selectedHeadingID != headingID {
                                tab.selectedHeadingID = headingID
                            }
                        }
                    )
                } else {
                    VStack(spacing: 12) {
                        Image(systemName: "doc.text")
                            .font(.system(size: 48))
                            .foregroundColor(.secondary)
                        Text("Unable to display file")
                            .font(.title3)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
    }

    @ViewBuilder
    private func editorView(for tab: GladeViewModel) -> some View {
        TextEditor(text: Binding(
            get: { tab.draftText },
            set: { tab.draftText = $0 }
        ))
        .font(.system(.body, design: .monospaced))
        .scrollContentBackground(.hidden)
        .background(Color(nsColor: .textBackgroundColor))
        .accessibilityLabel(Text("File editor"))
    }

    private func zoomIn() {
        zoomLevel = min(2.0, zoomLevel + 0.1)
    }

    private func zoomOut() {
        zoomLevel = max(0.5, zoomLevel - 0.1)
    }

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            Text("No Files Open")
                .font(.title3)
                .foregroundColor(.secondary)
            Text("Open a file to get started.")
                .font(.callout)
                .foregroundColor(.secondary)
            Button("Open File\u{2026}") {
                showFileImporter = true
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Editing & close guards

    private var dirtyAlertTitle: String {
        if let action = pendingDirtyAction,
           let tab = manager.tabs.first(where: { $0.id == action.tabID }) {
            return String(localized: "Save changes to \(tab.displayName)?")
        }
        return String(localized: "Save changes?")
    }

    private func requestExitEditing(for tab: GladeViewModel) {
        if tab.isDirty {
            pendingDirtyAction = .exitEditing(tabID: tab.id)
        } else {
            tab.exitEditing()
        }
    }

    private func requestCloseTab(id: UUID) {
        guard let tab = manager.tabs.first(where: { $0.id == id }) else { return }
        if tab.isDirty {
            if manager.activeTabID != id {
                manager.activeTabID = id
            }
            pendingDirtyAction = .closeTab(tabID: id)
        } else {
            withAnimation(.easeOut(duration: 0.15)) {
                manager.closeTab(id)
            }
        }
    }

    private func resolveDirtyAction(_ action: PendingDirtyAction, save: Bool) {
        guard let tab = manager.tabs.first(where: { $0.id == action.tabID }) else {
            pendingDirtyAction = nil
            return
        }
        pendingDirtyAction = nil

        if save {
            Task {
                await tab.save()
                await MainActor.run {
                    guard tab.errorMessage == nil else { return }
                    completeDirtyAction(action, tab: tab)
                }
            }
        } else {
            tab.discardDraftAndExitEditing()
            completeDirtyAction(action, tab: tab)
        }
    }

    private func completeDirtyAction(_ action: PendingDirtyAction, tab: GladeViewModel) {
        switch action {
        case .exitEditing:
            tab.exitEditing()
        case .closeTab(let id):
            withAnimation(.easeOut(duration: 0.15)) {
                manager.closeTab(id)
            }
        }
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard !providers.isEmpty else { return false }
        for provider in providers {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, error in
                guard error == nil,
                      let data = item as? Data,
                      let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
                Task {
                    await manager.openFile(from: url)
                }
            }
        }
        return true
    }
}

// Captures the NSWindow hosting this SwiftUI view so file-open notifications
// can be routed to the window on the user's currently-active macOS Space.
struct WindowAccessor: NSViewRepresentable {
    let onWindowAvailable: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            if let window = view.window {
                onWindowAvailable(window)
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            if let window = nsView.window {
                onWindowAvailable(window)
            }
        }
    }
}
