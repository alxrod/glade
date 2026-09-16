import Foundation
import Observation
import SwiftUI
import UniformTypeIdentifiers

enum FileType {
    case jsonl
    case markdown
}

struct FlatHeading: Identifiable {
    let heading: MarkdownHeading
    let depth: Int

    var id: UUID { heading.id }
}

struct ScrollTarget: Equatable {
    let lineIndex: Int
    let trigger: UUID

    init(lineIndex: Int) {
        self.lineIndex = lineIndex
        self.trigger = UUID()
    }
}

@Observable
final class GladeViewModel: Identifiable {
    let id = UUID()
    var displayName: String = String(localized: "No file loaded")
    var fileURL: URL?
    var fileType: FileType = .jsonl
    var document: JSONLDocument?
    var markdownDocument: MarkdownDocument?
    var selectedLineID: UUID?
    var isInspectorPresented = false
    var selectedHeadingID: UUID?
    var scrollTarget: ScrollTarget?
    var isLoading = false
    var errorMessage: String?
    var showFileImporter = false
    var searchText: String = ""
    var showJumpToLine: Bool = false
    var exportCopied: Bool = false

    // MARK: - Editing

    var isEditing: Bool = false
    var draftText: String = ""
    var isSaving: Bool = false
    private var originalText: String = ""

    var isDirty: Bool {
        isEditing && draftText != originalText
    }

    var canEdit: Bool {
        fileURL != nil && isLoaded
    }

    var selectedLine: JSONLLine? {
        guard let id = selectedLineID else { return nil }
        return document?.lines.first(where: { $0.id == id })
    }

    var lines: [JSONLLine] {
        document?.lines ?? []
    }

    var filteredLines: [JSONLLine] {
        let allLines = lines
        guard !searchText.trimmingCharacters(in: .whitespaces).isEmpty else {
            return allLines
        }
        let query = searchText.lowercased()
        return allLines.filter { $0.rawJSON.lowercased().contains(query) }
    }

    var lineCount: Int {
        document?.lineCount ?? 0
    }

    var filteredLineCount: Int {
        filteredLines.count
    }

    var fileName: String {
        switch fileType {
        case .jsonl:
            return document?.fileName ?? String(localized: "No file loaded")
        case .markdown:
            return markdownDocument?.fileName ?? String(localized: "No file loaded")
        }
    }

    var isLoaded: Bool {
        switch fileType {
        case .jsonl: return document != nil
        case .markdown: return markdownDocument != nil
        }
    }

    // MARK: - Markdown Headings

    var flattenedHeadings: [FlatHeading] {
        guard let doc = markdownDocument else { return [] }
        return Self.flattenHeadings(doc.headings, depth: 0)
    }

    var filteredHeadings: [FlatHeading] {
        let all = flattenedHeadings
        guard !searchText.trimmingCharacters(in: .whitespaces).isEmpty else { return all }
        let query = searchText.lowercased()
        return all.filter { $0.heading.title.lowercased().contains(query) }
    }

    var headingCount: Int {
        flattenedHeadings.count
    }

    var filteredHeadingCount: Int {
        filteredHeadings.count
    }

    var headingLineIndexToID: [Int: UUID] {
        var map: [Int: UUID] = [:]
        for flat in flattenedHeadings {
            map[flat.heading.lineIndex] = flat.heading.id
        }
        return map
    }

    func selectHeading(_ heading: MarkdownHeading) {
        selectedHeadingID = heading.id
        scrollTarget = ScrollTarget(lineIndex: heading.lineIndex)
    }

    private static func flattenHeadings(_ headings: [MarkdownHeading], depth: Int) -> [FlatHeading] {
        var result: [FlatHeading] = []
        for heading in headings {
            result.append(FlatHeading(heading: heading, depth: depth))
            result.append(contentsOf: flattenHeadings(heading.children, depth: depth + 1))
        }
        return result
    }

    // MARK: - File Loading

    func openFileImporter() {
        showFileImporter = true
    }

    static func detectFileType(from url: URL) -> FileType {
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "md", "markdown", "mdown", "mkd":
            return .markdown
        default:
            return .jsonl
        }
    }

    func loadFile(from url: URL) async {
        let detectedType = Self.detectFileType(from: url)

        await MainActor.run {
            isLoading = true
            errorMessage = nil
            fileType = detectedType
        }

        // Security scoped resource access
        let didAccess = url.startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }

        // Read raw contents once so we can preserve the exact bytes for editing.
        let readResult: Result<String, Error> = await Task.detached(priority: .userInitiated) {
            Result { try String(contentsOf: url, encoding: .utf8) }
        }.value

        let rawContent: String
        switch readResult {
        case .success(let content):
            rawContent = content
        case .failure(let error):
            await MainActor.run {
                self.errorMessage = "Failed to load file: \(error.localizedDescription)"
                self.isLoading = false
            }
            return
        }

        switch detectedType {
        case .markdown:
            await loadMarkdownFile(rawContent: rawContent, url: url)
        case .jsonl:
            await loadJSONLFile(rawContent: rawContent, url: url)
        }
    }

    private func loadMarkdownFile(rawContent: String, url: URL) async {
        let doc = await Task.detached(priority: .userInitiated) {
            MarkdownDocument.parse(rawContent: rawContent, url: url)
        }.value

        await MainActor.run {
            if rawContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                self.displayName = url.lastPathComponent
                self.fileURL = url
                self.originalText = rawContent
                self.errorMessage = "This file is empty."
                self.markdownDocument = nil
                self.isLoading = false
            } else {
                self.markdownDocument = doc
                self.fileURL = url
                self.originalText = rawContent
                self.displayName = url.lastPathComponent
                self.isLoading = false
            }
        }
    }

    private func loadJSONLFile(rawContent: String, url: URL) async {
        let doc = await Task.detached(priority: .userInitiated) {
            JSONLDocument.parse(rawContent: rawContent, url: url)
        }.value

        let allFailed = !doc.lines.isEmpty && doc.lines.allSatisfy { $0.parseError != nil }
        let isEmpty = doc.lines.isEmpty
        await MainActor.run {
            if isEmpty {
                self.displayName = url.lastPathComponent
                self.fileURL = url
                self.originalText = rawContent
                self.errorMessage = "This file is empty. There are no lines to display."
                self.document = nil
                self.isLoading = false
            } else if allFailed {
                self.displayName = url.lastPathComponent
                self.fileURL = url
                self.originalText = rawContent
                self.errorMessage = "This file doesn't contain valid JSON. Glade can only display JSONL (JSON Lines) files where each line is a JSON object."
                self.document = nil
                self.isLoading = false
            } else {
                self.document = doc
                self.fileURL = url
                self.originalText = rawContent
                self.displayName = url.lastPathComponent
                self.selectedLineID = doc.lines.first?.id
                self.isLoading = false
            }
        }
    }

    // MARK: - Editing

    func beginEditing() {
        guard canEdit else { return }
        draftText = originalText
        isEditing = true
    }

    /// Exits edit mode, discarding any unsaved draft changes.
    func discardDraftAndExitEditing() {
        draftText = originalText
        isEditing = false
    }

    /// Exits edit mode without modifying the draft (used after a successful save).
    func exitEditing() {
        isEditing = false
    }

    func save() async {
        struct SaveSnapshot {
            let url: URL
            let text: String
            let type: FileType
            let previousLineNumber: Int?
        }

        let snapshot: SaveSnapshot? = await MainActor.run {
            guard !isSaving, let url = fileURL else { return nil }
            isSaving = true
            return SaveSnapshot(
                url: url,
                text: draftText,
                type: fileType,
                previousLineNumber: fileType == .jsonl ? selectedLine?.lineNumber : nil
            )
        }
        guard let snapshot else { return }

        let url = snapshot.url
        let textToSave = snapshot.text

        let didAccess = url.startAccessingSecurityScopedResource()
        defer {
            if didAccess { url.stopAccessingSecurityScopedResource() }
        }

        let writeResult: Result<Void, Error> = await Task.detached(priority: .userInitiated) {
            Result { try textToSave.write(to: url, atomically: true, encoding: .utf8) }
        }.value

        switch writeResult {
        case .success:
            let parsed: ParsedDocument = await Task.detached(priority: .userInitiated) {
                switch snapshot.type {
                case .jsonl:
                    return .jsonl(JSONLDocument.parse(rawContent: textToSave, url: url))
                case .markdown:
                    return .markdown(MarkdownDocument.parse(rawContent: textToSave, url: url))
                }
            }.value

            await MainActor.run {
                self.originalText = textToSave
                self.applyReparsed(parsed, previousLineNumber: snapshot.previousLineNumber)
                self.isSaving = false
            }
        case .failure(let error):
            await MainActor.run {
                self.errorMessage = "Failed to save: \(error.localizedDescription)"
                self.isSaving = false
            }
        }
    }

    private enum ParsedDocument {
        case jsonl(JSONLDocument)
        case markdown(MarkdownDocument)
    }

    private func applyReparsed(_ parsed: ParsedDocument, previousLineNumber: Int?) {
        switch parsed {
        case .jsonl(let doc):
            self.document = doc
            if let num = previousLineNumber,
               let restored = doc.lines.first(where: { $0.lineNumber == num }) {
                self.selectedLineID = restored.id
            } else {
                self.selectedLineID = doc.lines.first?.id
            }
        case .markdown(let doc):
            self.markdownDocument = doc
        }
    }

    func selectLine(_ line: JSONLLine) {
        selectedLineID = line.id
    }

    func inspectLine(_ line: JSONLLine) {
        selectedLineID = line.id
        isInspectorPresented = true
    }

    // MARK: - Jump To Line

    func jumpToLine(_ lineNumber: Int) {
        // Try filtered lines first; if not found, clear search to show all lines
        if let target = filteredLines.first(where: { $0.lineNumber == lineNumber }) {
            selectedLineID = target.id
        } else if let target = lines.first(where: { $0.lineNumber == lineNumber }) {
            searchText = ""
            selectedLineID = target.id
        }
    }

    // MARK: - Keyboard Navigation

    func selectNextLine() {
        let list = filteredLines
        guard !list.isEmpty else { return }
        if let current = selectedLineID,
           let idx = list.firstIndex(where: { $0.id == current }),
           idx + 1 < list.count {
            selectedLineID = list[idx + 1].id
        } else if selectedLineID == nil {
            selectedLineID = list.first?.id
        }
    }

    func selectPreviousLine() {
        let list = filteredLines
        guard !list.isEmpty else { return }
        if let current = selectedLineID,
           let idx = list.firstIndex(where: { $0.id == current }),
           idx > 0 {
            selectedLineID = list[idx - 1].id
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
