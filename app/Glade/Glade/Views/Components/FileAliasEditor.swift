import SwiftUI
import AppKit

struct FileAliasEditor: ViewModifier {
    let tab: GladeViewModel
    @State private var isPresented = false
    @State private var alias = ""

    func body(content: Content) -> some View {
        content
            .contextMenu {
                Button("Assign Alias…") {
                    alias = tab.fileURL.flatMap { tab.fileMetadata.alias(for: $0) } ?? ""
                    isPresented = true
                }
                if let url = tab.fileURL, tab.fileMetadata.alias(for: url) != nil {
                    Button("Remove Alias") { tab.fileMetadata.setAlias("", for: url) }
                }
            }
            .modifier(FileAliasPrompt(tab: tab, alias: $alias, isPresented: $isPresented))
    }
}

/// A native title label consumes right-clicks before NSToolbar's customization menu.
struct FileAliasTitleView: View {
    let tab: GladeViewModel
    @State private var alias = ""
    @State private var isPresented = false

    var body: some View {
        FileTitleLabelView(
            name: tab.preferredName,
            path: tab.fileURL?.path ?? tab.fileName,
            onAssign: {
                alias = tab.fileURL.flatMap { tab.fileMetadata.alias(for: $0) } ?? ""
                isPresented = true
            },
            onRemove: tab.fileURL.flatMap { tab.fileMetadata.alias(for: $0) } == nil ? nil : {
                if let url = tab.fileURL { tab.fileMetadata.setAlias("", for: url) }
            }
        )
        .fixedSize(horizontal: true, vertical: false)
        .padding(.trailing, 12)
        .modifier(FileAliasPrompt(tab: tab, alias: $alias, isPresented: $isPresented))
    }
}

private struct FileAliasPrompt: ViewModifier {
    let tab: GladeViewModel
    @Binding var alias: String
    @Binding var isPresented: Bool

    func body(content: Content) -> some View {
        content.alert("File Alias", isPresented: $isPresented) {
            TextField("Nickname", text: $alias)
            Button("Cancel", role: .cancel) { }
            Button("Save") {
                if let url = tab.fileURL { tab.fileMetadata.setAlias(alias, for: url) }
            }
        } message: {
            Text("Nickname for \(tab.fileName). Leave it empty to use the original filename.")
        }
    }
}

private struct FileTitleLabelView: NSViewRepresentable {
    let name: String
    let path: String
    let onAssign: () -> Void
    let onRemove: (() -> Void)?

    func makeNSView(context: Context) -> FileTitleLabel {
        let label = FileTitleLabel(labelWithString: name)
        label.font = .systemFont(ofSize: NSFont.systemFontSize, weight: .semibold)
        label.lineBreakMode = .byTruncatingMiddle
        label.maximumNumberOfLines = 1
        return label
    }

    func updateNSView(_ label: FileTitleLabel, context: Context) {
        label.stringValue = name
        label.toolTip = path
        label.onAssign = onAssign
        label.onRemove = onRemove
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: FileTitleLabel, context: Context) -> CGSize? {
        let size = nsView.intrinsicContentSize
        return CGSize(width: min(proposal.width ?? 360, min(360, ceil(size.width) + 2)), height: ceil(size.height))
    }
}

private final class FileTitleLabel: NSTextField {
    var onAssign: (() -> Void)?
    var onRemove: (() -> Void)?
    private var contextMenuMonitor: Any?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let contextMenuMonitor { NSEvent.removeMonitor(contextMenuMonitor) }
        contextMenuMonitor = nil
        guard window != nil else { return }
        // NSToolbar consumes context clicks before dispatching to its child views.
        // Intercept only clicks inside this label in this app's window.
        contextMenuMonitor = NSEvent.addLocalMonitorForEvents(matching: [.rightMouseDown, .leftMouseDown]) { [weak self] event in
            guard let self, event.window === self.window, !self.isHiddenOrHasHiddenAncestor,
                  event.type == .rightMouseDown || event.modifierFlags.contains(.control),
                  self.bounds.contains(self.convert(event.locationInWindow, from: nil)),
                  let menu = self.menu(for: event) else { return event }
            NSMenu.popUpContextMenu(menu, with: event, for: self)
            return nil
        }
    }

    deinit {
        if let contextMenuMonitor { NSEvent.removeMonitor(contextMenuMonitor) }
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = NSMenu()
        let assign = NSMenuItem(title: String(localized: "Assign Alias…"), action: #selector(assignAlias), keyEquivalent: "")
        assign.target = self
        menu.addItem(assign)
        if onRemove != nil {
            let remove = NSMenuItem(title: String(localized: "Remove Alias"), action: #selector(removeAlias), keyEquivalent: "")
            remove.target = self
            menu.addItem(remove)
        }
        return menu
    }

    override func rightMouseDown(with event: NSEvent) {
        if let menu = menu(for: event) { NSMenu.popUpContextMenu(menu, with: event, for: self) }
    }

    @objc private func assignAlias() { onAssign?() }
    @objc private func removeAlias() { onRemove?() }
}
