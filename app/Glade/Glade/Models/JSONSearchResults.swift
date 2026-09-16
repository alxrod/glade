import Foundation
import Observation

/// Keeps completed results on screen while a submitted query runs off the main thread.
@Observable
final class JSONLSearchResults {
    private(set) var rows: [JSONLLine]?
    private(set) var isSearching = false
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var documentID: UUID?
    @ObservationIgnored private var worker: Task<[JSONLLine]?, Never>?

    @MainActor
    func update(lines: [JSONLLine], query: JSONLQuery, taggedIDs: Set<UUID> = []) async {
        guard !Task.isCancelled else { return }
        worker?.cancel()
        let token = UUID()
        generation = token
        if documentID != lines.first?.id { rows = nil }
        documentID = lines.first?.id
        guard query.isActive else {
            rows = lines
            isSearching = false
            worker = nil
            return
        }
        isSearching = true
        let task = Task.detached(priority: .userInitiated) { () -> [JSONLLine]? in
            var matches: [JSONLLine] = []
            for line in lines {
                guard !Task.isCancelled else { return nil }
                if query.matches(line, isTagged: taggedIDs.contains(line.id)) { matches.append(line) }
            }
            return matches
        }
        worker = task
        let matches = await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            task.cancel()
        }
        guard generation == token else { return }
        worker = nil
        isSearching = false
        guard !Task.isCancelled, let matches else { return }
        rows = matches
    }

    deinit { worker?.cancel() }
}

@Observable
final class JSONLineSearchResults {
    private(set) var search = JSONLineSearch(value: .null, query: "")
    private(set) var lineID: UUID?
    private(set) var isSearching = false
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var worker: Task<JSONLineSearch, Never>?

    @MainActor
    func update(line: JSONLLine?, query: String) async {
        guard !Task.isCancelled else { return }
        worker?.cancel()
        let token = UUID()
        generation = token
        if lineID != line?.id { search = JSONLineSearch(value: .null, query: "") }
        lineID = line?.id
        guard let line, !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            search = JSONLineSearch(value: .null, query: "")
            isSearching = false
            worker = nil
            return
        }
        isSearching = true
        let task = Task.detached(priority: .userInitiated) { JSONLineSearch(line: line, query: query) }
        worker = task
        let result = await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            task.cancel()
        }
        guard generation == token else { return }
        worker = nil
        isSearching = false
        guard !Task.isCancelled else { return }
        search = result
    }

    deinit { worker?.cancel() }
}
