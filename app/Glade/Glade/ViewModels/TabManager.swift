import Foundation
import Observation

@Observable
final class TabManager {
    var tabs: [GladeViewModel] = []
    var activeTabID: UUID?

    var activeTab: GladeViewModel? {
        tabs.first { $0.id == activeTabID }
    }

    var hasOpenTabs: Bool {
        !tabs.isEmpty
    }

    // MARK: - Tab Operations

    var lastOpenError: String?

    func openFile(from url: URL) async {
        // If file is already open, just switch to that tab
        if let existing = tabs.first(where: { $0.fileURL == url }) {
            activeTabID = existing.id
            return
        }

        // Load into a temporary view model first
        let tab = GladeViewModel()
        await tab.loadFile(from: url)

        // Only create a tab if the file loaded successfully
        if tab.isLoaded {
            tabs.append(tab)
            activeTabID = tab.id
        } else {
            lastOpenError = tab.errorMessage
        }
    }

    func closeTab(_ id: UUID) {
        guard let idx = tabs.firstIndex(where: { $0.id == id }) else { return }
        let wasActive = activeTabID == id
        tabs.remove(at: idx)

        if wasActive {
            if tabs.isEmpty {
                activeTabID = nil
            } else {
                // Activate the tab to the left, or the first tab if closing the leftmost
                let newIdx = idx > 0 ? idx - 1 : 0
                activeTabID = tabs[newIdx].id
            }
        }
    }

    func closeActiveTab() {
        guard let id = activeTabID else { return }
        closeTab(id)
    }

    func switchToPreviousTab() {
        guard let active = activeTabID,
              let idx = tabs.firstIndex(where: { $0.id == active }),
              idx > 0 else { return }
        activeTabID = tabs[idx - 1].id
    }

    func switchToNextTab() {
        guard let active = activeTabID,
              let idx = tabs.firstIndex(where: { $0.id == active }),
              idx < tabs.count - 1 else { return }
        activeTabID = tabs[idx + 1].id
    }
}
