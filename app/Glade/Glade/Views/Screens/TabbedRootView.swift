import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct TabbedRootView: View {
    @State private var manager: TabManager
    @State private var showFileImporter = false
    @State private var importErrorMessage: String?
    @State private var windowNumber: Int?

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
        .navigationTitle(manager.activeTab?.preferredName ?? "Glade")
        .frame(minWidth: 900, minHeight: 500)
        .toolbar {
            if #available(macOS 26.0, *) {
                ToolbarItem(placement: .navigation) {
                    if let tab = manager.activeTab {
                        FileAliasTitleView(tab: tab)
                    }
                }
                .sharedBackgroundVisibility(.hidden)
            } else {
                ToolbarItem(placement: .navigation) {
                    if let tab = manager.activeTab {
                        FileAliasTitleView(tab: tab)
                    }
                }
            }
        }
    }

    var body: some View {
        workspaceView
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [.jsonl, .json] + ["jsonl", "ndjson"].compactMap {
                UTType(filenameExtension: $0)
            },
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
            window.titleVisibility = .hidden
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
    }

    @ViewBuilder
    private func activeTabView(for tab: GladeViewModel) -> some View {
        HSplitView {
            JSONLTableView(viewModel: tab)
                .id(tab.id)
                .frame(minWidth: 320, maxWidth: .infinity, maxHeight: .infinity)
            if tab.isInspectorPresented {
                DetailView(
                    line: tab.selectedLine,
                    searchText: Binding(get: { tab.inspectorSearchText }, set: { tab.inspectorSearchText = $0 }),
                    onClose: { tab.isInspectorPresented = false }
                )
                .frame(minWidth: 320, idealWidth: 440, maxWidth: 700)
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
            guard !tab.lines.isEmpty else { return }
            tab.showJumpToLine = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .exportPrettyJSON)) { _ in
            tab.exportSelectedLineAsPrettyJSON()
        }
        .onReceive(NotificationCenter.default.publisher(for: .selectNextLine)) { _ in
            tab.selectNextLine()
        }
        .onReceive(NotificationCenter.default.publisher(for: .selectPreviousLine)) { _ in
            tab.selectPreviousLine()
        }
        .onReceive(NotificationCenter.default.publisher(for: .exportRawJSON)) { _ in
            tab.exportSelectedLineAsRawJSON()
        }
    }

    @ToolbarContentBuilder
    private func tabToolbar(for tab: GladeViewModel) -> some ToolbarContent {
        if #available(macOS 26.0, *) {
            ToolbarSpacer(.flexible, placement: .primaryAction)
        } else {
            ToolbarItem(placement: .automatic) { Spacer() }
        }
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
            .help("Copy selected line as pretty-printed JSON (⌘⇧C)")
            .disabled(tab.selectedLine == nil)
        }
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

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            Text("No Files Open")
                .font(.title3)
                .foregroundColor(.secondary)
            Text("Open a JSONL, NDJSON, or JSON file to get started.")
                .font(.callout)
                .foregroundColor(.secondary)
            Button("Open File\u{2026}") {
                showFileImporter = true
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func requestCloseTab(id: UUID) {
        withAnimation(.easeOut(duration: 0.15)) {
            manager.closeTab(id)
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
