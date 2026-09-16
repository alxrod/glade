import XCTest
@testable import GladeCore

final class JSONLSavedQueryStoreTests: XCTestCase {
    private func preferences() throws -> UserDefaults {
        let suite = "GladeSavedQueryTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        return defaults
    }

    private func columns(_ keys: [String]) -> [JSONLTableColumn] {
        [.lineNumber] + keys.map(JSONLTableColumn.field)
    }

    func testSavedQueryPersistsAcrossFilesWithFullMatchingKeyUnion() throws {
        let defaults = try preferences()
        let first = JSONLDocument.parse(rawContent: #"{"message":"hello"}"# + "\n" + #"{"type":"user"}"#,
                                        url: URL(fileURLWithPath: "/tmp/first.jsonl"))
        let second = JSONLDocument.parse(rawContent: #"{"type":"assistant","message":"different"}"#,
                                         url: URL(fileURLWithPath: "/tmp/second.jsonl"))
        let query = JSONLQuery(text: "hello", conditions: [.init(key: "type", operation: .equals, value: "user")])
        let store = JSONLSavedQueryStore(defaults: defaults)
        let saved = try XCTUnwrap(store.save(name: "User messages", query: query, for: first.tableColumns))
        XCTAssertEqual(JSONLSavedQueryStore(defaults: defaults).queries(for: second.tableColumns), [saved])
    }

    func testQueriesDoNotLeakAcrossDifferentKeySetsOrCapitalization() throws {
        let store = JSONLSavedQueryStore(defaults: try preferences())
        store.save(name: "Hello", query: JSONLQuery(text: "hello"), for: columns(["a", "b"]))
        for keys in [["a"], ["a", "b", "c"], ["A", "b"], ["a", "c"]] {
            XCTAssertTrue(store.queries(for: columns(keys)).isEmpty)
        }
    }

    func testQueriesShareLayoutIdentityAndIgnoreOrderVisibilityAndIncidentalRawColumn() throws {
        let defaults = try preferences()
        let layout = JSONLColumnLayoutStore(defaults: defaults)
        let store = JSONLSavedQueryStore(defaults: defaults)
        let schema = columns(["a,b", "c", ""])
        layout.save(columns(["", "c", "a,b"]), for: schema)
        layout.hide(.field("c"), in: schema)
        layout.saveWidth(330, for: .field("c"), in: schema)
        let saved = store.save(name: "Hidden field", query: JSONLQuery(conditions: [.init(key: "c", value: "hello")]), for: schema)
        XCTAssertEqual(store.queries(for: layout.columns(for: schema) + [.value]).first, saved)
        XCTAssertTrue(store.queries(for: columns(["a", "b,c", ""])).isEmpty)
        XCTAssertEqual(layout.hiddenColumns(for: schema), [.field("c")])
        XCTAssertEqual(layout.widths(for: schema)["field:c"], 330)
    }

    func testUpdatingNamedQueryKeepsIdentityAndDeletingPreservesOtherQueriesAndSchemas() throws {
        let defaults = try preferences()
        let store = JSONLSavedQueryStore(defaults: defaults)
        let schema = columns(["a"])
        let first = try XCTUnwrap(store.save(name: " Hello ", query: JSONLQuery(text: "one"), for: schema))
        let second = try XCTUnwrap(store.save(name: "Second", query: JSONLQuery(text: "two"), for: schema))
        store.save(name: "Hello", query: JSONLQuery(text: "other"), for: columns(["b"]))
        let updated = try XCTUnwrap(store.save(name: "hello", query: JSONLQuery(text: "three"), for: schema))
        XCTAssertEqual(updated.id, first.id)
        XCTAssertEqual(store.query(named: "HELLO", for: schema)?.query.text, "three")
        XCTAssertEqual(store.queries(for: schema).count, 2)
        store.delete(updated, for: schema)
        let reopened = JSONLSavedQueryStore(defaults: defaults)
        XCTAssertEqual(reopened.queries(for: schema), [second])
        XCTAssertEqual(reopened.queries(for: columns(["b"])).count, 1)
    }

    func testEmptyNamesEmptyQueriesAndUnknownFieldsAreRejected() throws {
        let store = JSONLSavedQueryStore(defaults: try preferences())
        let schema = columns(["a"])
        XCTAssertNil(store.save(name: " \n", query: JSONLQuery(text: "hello"), for: schema))
        XCTAssertNil(store.save(name: "Blank", query: JSONLQuery(text: " \n"), for: schema))
        XCTAssertNil(store.save(name: "Missing", query: JSONLQuery(conditions: [.init(key: "b")]), for: schema))
        XCTAssertTrue(store.queries(for: schema).isEmpty)
    }

    func testCorruptSavedSchemaDoesNotDiscardOtherSavedQueries() throws {
        let defaults = try preferences()
        let store = JSONLSavedQueryStore(defaults: defaults)
        store.save(name: "Good", query: JSONLQuery(text: "hello"), for: columns(["a"]))
        var raw = try XCTUnwrap(defaults.dictionary(forKey: JSONLSavedQueryStore.storageKey))
        raw[try XCTUnwrap(JSONLTableColumn.schemaKey(for: columns(["b"])))] = Data("bad data".utf8)
        defaults.set(raw, forKey: JSONLSavedQueryStore.storageKey)
        let reopened = JSONLSavedQueryStore(defaults: defaults)
        XCTAssertEqual(reopened.queries(for: columns(["a"])).count, 1)
        XCTAssertTrue(reopened.queries(for: columns(["b"])).isEmpty)
    }
}
