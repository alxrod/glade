import XCTest
@testable import GladeCore

@MainActor
final class JSONSearchResultsTests: XCTestCase {
    private func lines() -> [JSONLLine] {
        [JSONLLine(lineNumber: 1, rawJSON: #"{"message":"hello","type":"user"}"#),
         JSONLLine(lineNumber: 2, rawJSON: #"{"message":"goodbye","type":"assistant"}"#)]
    }

    func testSubmittedTableQueryCachesRowsAndClearingRestoresTheDocument() async {
        let source = lines()
        let results = JSONLSearchResults()
        await results.update(lines: source, query: JSONLQuery(text: "hello"))
        XCTAssertEqual(results.rows?.map(\.id), [source[0].id])
        XCTAssertFalse(results.isSearching)
        await results.update(lines: source, query: JSONLQuery())
        XCTAssertEqual(results.rows?.map(\.id), source.map(\.id))
    }

    func testSubmittedQueryHonorsTagsAndDoesNotRetainRowsFromAnotherParse() async {
        let source = lines()
        let results = JSONLSearchResults()
        await results.update(lines: source, query: JSONLQuery(taggedOnly: true), taggedIDs: [source[1].id])
        XCTAssertEqual(results.rows?.map(\.id), [source[1].id])
        let reparsed = lines()
        await results.update(lines: reparsed, query: JSONLQuery(text: "hello"))
        XCTAssertEqual(results.rows?.map(\.id), [reparsed[0].id])
    }

    func testSupersededTableSearchCannotOverwriteTheNewestResult() async {
        let source = lines()
        let results = JSONLSearchResults()
        let first = Task { await results.update(lines: Array(repeating: source[0], count: 20_000), query: JSONLQuery(text: "hello")) }
        while results.rows == nil && !results.isSearching { await Task.yield() }
        await results.update(lines: source, query: JSONLQuery(text: "goodbye"))
        await first.value
        XCTAssertEqual(results.rows?.map(\.id), [source[1].id])
        XCTAssertFalse(results.isSearching)
    }

    func testInspectorSearchCachesMatchesAndResetsForAnotherLineOrClear() async {
        let source = lines()
        let results = JSONLineSearchResults()
        await results.update(line: source[0], query: "hello")
        XCTAssertEqual(results.search.matchCount, 1)
        XCTAssertEqual(results.lineID, source[0].id)
        await results.update(line: source[1], query: "hello")
        XCTAssertEqual(results.search.matchCount, 0)
        XCTAssertEqual(results.lineID, source[1].id)
        await results.update(line: source[1], query: "")
        XCTAssertFalse(results.search.isActive)
        XCTAssertFalse(results.isSearching)
    }

    func testSupersededInspectorSearchCannotOverwriteClear() async {
        let source = JSONLLine(lineNumber: 1, rawJSON: "\"" + String(repeating: "hello ", count: 10_000) + "\"")
        let results = JSONLineSearchResults()
        let first = Task { await results.update(line: source, query: "hello") }
        while results.lineID == nil { await Task.yield() }
        await results.update(line: source, query: "")
        await first.value
        XCTAssertFalse(results.search.isActive)
        XCTAssertFalse(results.isSearching)
    }
}
