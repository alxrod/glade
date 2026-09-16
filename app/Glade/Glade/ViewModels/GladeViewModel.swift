import Foundation
import Observation
import SwiftUI

@Observable
final class GladeViewModel: Identifiable {
    let id = UUID()
    var displayName: String = String(localized: "No file loaded")
    var fileURL: URL?
    var document: JSONLDocument?
    private(set) var selectedLineID: UUID?
    private(set) var selectedLineIDs: Set<UUID> = []
    var isInspectorPresented = false
    var isLoading = false
    var errorMessage: String?
    var searchText: String = ""
    var inspectorSearchText: String = ""
    var columnFilters: [JSONLColumnFilter] = []
    var taggedOnly = false
    let fileMetadata = LocalFileMetadataStore.shared
    let searchResults = JSONLSearchResults()
    var queryApplicationID = UUID()
    var showJumpToLine: Bool = false
    var exportCopied: Bool = false

    var selectedLine: JSONLLine? {
        guard let id = selectedLineID else { return nil }
        return document?.lines.first(where: { $0.id == id })
    }

    var lines: [JSONLLine] {
        document?.lines ?? []
    }

    var filteredLines: [JSONLLine] {
        tableQuery.isActive ? (searchResults.rows ?? lines) : lines
    }

    var tableRowsRevision: UUID {
        tableQuery.isActive && searchResults.rows != nil ? searchResults.rowsRevision : (document?.id ?? id)
    }

    var preferredName: String { fileURL.flatMap { fileMetadata.alias(for: $0) } ?? displayName }

    var rowTags: [UUID: JSONLRowTagColor] {
        guard let fileURL else { return [:] }
        return fileMetadata.rowTags(for: fileURL, lines: lines)
    }

    func tagLines(_ lines: [JSONLLine], color: JSONLRowTagColor?) {
        guard let fileURL else { return }
        fileMetadata.setTag(color, for: lines, in: fileURL)
    }

    var tableQuery: JSONLQuery {
        get { JSONLQuery(text: searchText, conditions: columnFilters, taggedOnly: taggedOnly) }
        set {
            searchText = newValue.text
            columnFilters = newValue.conditions
            taggedOnly = newValue.taggedOnly
            queryApplicationID = UUID()
        }
    }

    var lineCount: Int {
        document?.lineCount ?? 0
    }

    var filteredLineCount: Int {
        filteredLines.count
    }

    var fileName: String { document?.fileName ?? String(localized: "No file loaded") }

    var isLoaded: Bool { document != nil }

    // MARK: - File Loading

    func loadFile(from url: URL) async {
        await MainActor.run {
            isLoading = true
            errorMessage = nil
        }

        let didAccess = url.startAccessingSecurityScopedResource()
        defer {
            if didAccess { url.stopAccessingSecurityScopedResource() }
        }

        // All entry points use the same extension validation and JSON parser.
        let result: Result<JSONLDocument, Error> = await Task.detached(priority: .userInitiated) {
            Result { try JSONLDocument.parse(from: url) }
        }.value

        await MainActor.run {
            defer { self.isLoading = false }
            switch result {
            case .failure(let error):
                self.errorMessage = error.localizedDescription
            case .success(let doc):
                self.displayName = url.lastPathComponent
                self.fileURL = url
                if doc.lines.isEmpty {
                    self.errorMessage = String(localized: "This file is empty. There are no records to display.")
                    self.document = nil
                } else if doc.lines.allSatisfy({ $0.parseError != nil }) {
                    self.errorMessage = String(localized: "This file doesn't contain valid JSON. Use a JSON document or a JSONL/NDJSON file with one JSON value per line.")
                    self.document = nil
                } else {
                    self.document = doc
                    self.selectLine(doc.lines.first)
                }
            }
        }
    }

    func selectLine(_ line: JSONLLine?) {
        selectLines(withIDs: line.map { [$0.id] } ?? [], primaryID: line?.id)
    }

    func selectLines(withIDs ids: Set<UUID>, primaryID: UUID?) {
        selectedLineIDs = ids
        if let primaryID, ids.contains(primaryID) {
            selectedLineID = primaryID
        } else {
            selectedLineID = lines.first(where: { ids.contains($0.id) })?.id
        }
    }

    func reconcileSelection(with visibleLines: [JSONLLine]) {
        let remaining = selectedLineIDs.intersection(visibleLines.map(\.id))
        if remaining.isEmpty {
            selectLine(visibleLines.first)
        } else {
            selectLines(withIDs: remaining, primaryID: selectedLineID)
        }
    }

    func inspectLine(_ line: JSONLLine) {
        selectLine(line)
        isInspectorPresented = true
    }

    // MARK: - Jump To Line

    func jumpToLine(_ lineNumber: Int) {
        // Try filtered lines first; if not found, clear search to show all lines
        if let target = filteredLines.first(where: { $0.lineNumber == lineNumber }) {
            selectLine(target)
        } else if let target = lines.first(where: { $0.lineNumber == lineNumber }) {
            searchText = ""
            selectLine(target)
        }
    }

    // MARK: - Keyboard Navigation

    func selectNextLine() {
        let list = filteredLines
        guard !list.isEmpty else { return }
        if let current = selectedLineID,
           let idx = list.firstIndex(where: { $0.id == current }),
           idx + 1 < list.count {
            selectLine(list[idx + 1])
        } else if selectedLineID == nil {
            selectLine(list.first)
        }
    }

    func selectPreviousLine() {
        let list = filteredLines
        guard !list.isEmpty else { return }
        if let current = selectedLineID,
           let idx = list.firstIndex(where: { $0.id == current }),
           idx > 0 {
            selectLine(list[idx - 1])
        }
    }

    // MARK: - Export

    func exportSelectedLineAsRawJSON() {
        guard let line = selectedLine else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(line.rawJSON, forType: .string)
        exportCopied = true
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            await MainActor.run { exportCopied = false }
        }
    }

    func exportSelectedLineAsPrettyJSON() {
        guard let line = selectedLine else { return }
        let output: String
        if let parsed = line.parsed,
           let data = try? JSONSerialization.data(
               withJSONObject: jsonValueToAny(parsed),
               options: [.prettyPrinted, .sortedKeys, .fragmentsAllowed]
           ),
           let pretty = String(data: data, encoding: .utf8) {
            output = pretty
        } else {
            output = line.rawJSON
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(output, forType: .string)
        exportCopied = true
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            await MainActor.run { exportCopied = false }
        }
    }

    private func jsonValueToAny(_ value: JSONValue) -> Any {
        switch value {
        case .object(let pairs):
            var dict: [String: Any] = [:]
            for kv in pairs {
                dict[kv.key] = jsonValueToAny(kv.value)
            }
            return dict
        case .array(let arr):
            return arr.map { jsonValueToAny($0) }
        case .string(let str):
            return str
        case .number(let num):
            return num
        case .bool(let flag):
            return flag
        case .null:
            return NSNull()
        }
    }
}
