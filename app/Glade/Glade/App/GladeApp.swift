import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let updates = UpdateController()
    private var pendingURLs: [URL] = []
    private var windowIsReady = false
    private var programmaticWindows: [NSWindow] = []

    deinit {}

    func applicationWillFinishLaunching(_ notification: Notification) {
        // Intercept Finder "open document" events BEFORE AppKit's NSDocumentController
        // routes them through CFBundleDocumentTypes (which would spawn ghost windows
        // for our SwiftUI scene).
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleOpenDocumentsEvent(_:withReplyEvent:)),
            forEventClass: AEEventClass(kCoreEventClass),
            andEventID: AEEventID(kAEOpenDocuments)
        )
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        updates.start()
        NSWindow.allowsAutomaticWindowTabbing = false
        windowIsReady = true
        let flush = pendingURLs
        pendingURLs.removeAll()
        if !flush.isEmpty {
            route(urls: flush)
        }
    }

    @objc func handleOpenDocumentsEvent(
        _ event: NSAppleEventDescriptor,
        withReplyEvent reply: NSAppleEventDescriptor
    ) {
        guard let list = event.paramDescriptor(forKeyword: AEKeyword(keyDirectObject)),
              list.numberOfItems > 0 else { return }

        var urls: [URL] = []
        for index in 1...list.numberOfItems {
            guard let item = list.atIndex(index) else { continue }
            if let url = Self.url(from: item) {
                urls.append(url)
            }
        }

        guard !urls.isEmpty else { return }

        if windowIsReady {
            route(urls: urls)
        } else {
            pendingURLs.append(contentsOf: urls)
        }
    }

    private func route(urls: [URL]) {
        if let existing = gladeWindowOnActiveSpace() {
            NotificationCenter.default.post(
                name: .openFileURL,
                object: urls,
                userInfo: ["windowNumber": existing.windowNumber]
            )
            existing.makeKeyAndOrderFront(nil)
            NSApplication.shared.activate(ignoringOtherApps: true)
        } else {
            openNewWindow(with: urls)
        }
    }

    private func gladeWindowOnActiveSpace() -> NSWindow? {
        let candidates = NSApplication.shared.windows.filter { window in
            window.isOnActiveSpace
                && window.canBecomeKey
                && !window.isMiniaturized
                && window.contentViewController is NSHostingController<TabbedRootView>
        }
        if let key = NSApp.keyWindow, candidates.contains(where: { $0 == key }) {
            return key
        }
        return candidates.first
    }

    private func openNewWindow(with urls: [URL]) {
        let hosting = NSHostingController(rootView: TabbedRootView(initialURLs: urls))
        let window = NSWindow(contentViewController: hosting)
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.title = String(localized: "Glade")
        window.setContentSize(NSSize(width: 1280, height: 780))
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        programmaticWindows.append(window)
        window.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        guard let closing = notification.object as? NSWindow else { return }
        programmaticWindows.removeAll { $0 === closing }
    }

    private static func url(from descriptor: NSAppleEventDescriptor) -> URL? {
        if descriptor.descriptorType == typeFileURL {
            if let url = URL(dataRepresentation: descriptor.data, relativeTo: nil) {
                return url
            }
        }
        if let coerced = descriptor.coerce(toDescriptorType: typeFileURL),
           let url = URL(dataRepresentation: coerced.data, relativeTo: nil) {
            return url
        }
        if let path = descriptor.stringValue {
            return URL(fileURLWithPath: path)
        }
        return nil
    }
}

@main
struct GladeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Window("Glade", id: "main") {
            TabbedRootView()
        }
        .defaultSize(width: 1280, height: 780)
        .commands {
            CommandGroup(after: .appInfo) {
                CheckForUpdatesButton(updates: appDelegate.updates)
            }
            CommandGroup(replacing: .newItem) {
                Button("Open File\u{2026}") {
                    NotificationCenter.default.post(name: .openFile, object: nil)
                }
                .keyboardShortcut("o", modifiers: .command)

                Button("Close File") {
                    NotificationCenter.default.post(name: .closeTab, object: nil)
                }
                .keyboardShortcut("w", modifiers: .command)

                Divider()

                Button("Save") {
                    NotificationCenter.default.post(name: .saveFile, object: nil)
                }
                .keyboardShortcut("s", modifiers: .command)
            }
            CommandMenu("Navigation") {
                Button("Jump to Line\u{2026}") {
                    NotificationCenter.default.post(name: .jumpToLine, object: nil)
                }
                .keyboardShortcut("g", modifiers: .command)

                Button("Next Line") {
                    NotificationCenter.default.post(name: .selectNextLine, object: nil)
                }
                .keyboardShortcut(.downArrow, modifiers: [.option])

                Button("Previous Line") {
                    NotificationCenter.default.post(name: .selectPreviousLine, object: nil)
                }
                .keyboardShortcut(.upArrow, modifiers: [.option])

                Divider()

                Button("Previous File") {
                    NotificationCenter.default.post(name: .switchToPreviousTab, object: nil)
                }
                .keyboardShortcut("[", modifiers: .command)

                Button("Next File") {
                    NotificationCenter.default.post(name: .switchToNextTab, object: nil)
                }
                .keyboardShortcut("]", modifiers: .command)
            }
            CommandGroup(after: .pasteboard) {
                Button("Copy Line as Pretty JSON") {
                    NotificationCenter.default.post(name: .exportPrettyJSON, object: nil)
                }
                .keyboardShortcut("c", modifiers: [.command, .shift])

                Button("Copy Line as Raw JSON") {
                    NotificationCenter.default.post(name: .exportRawJSON, object: nil)
                }
                .keyboardShortcut("c", modifiers: [.command, .option])
            }
        }
        Settings {
            UpdateSettingsView(updates: appDelegate.updates)
        }
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let jumpToLine = Notification.Name("net.alexbrodriguez.glade.jumpToLine")
    static let exportPrettyJSON = Notification.Name("net.alexbrodriguez.glade.exportPrettyJSON")
    static let selectNextLine = Notification.Name("net.alexbrodriguez.glade.selectNextLine")
    static let selectPreviousLine = Notification.Name("net.alexbrodriguez.glade.selectPreviousLine")
    static let switchToPreviousTab = Notification.Name("net.alexbrodriguez.glade.switchToPreviousTab")
    static let switchToNextTab = Notification.Name("net.alexbrodriguez.glade.switchToNextTab")
    static let exportRawJSON = Notification.Name("net.alexbrodriguez.glade.exportRawJSON")
    static let openFile = Notification.Name("net.alexbrodriguez.glade.openFile")
    static let closeTab = Notification.Name("net.alexbrodriguez.glade.closeTab")
    static let openFileURL = Notification.Name("net.alexbrodriguez.glade.openFileURL")
    static let saveFile = Notification.Name("net.alexbrodriguez.glade.saveFile")
}
