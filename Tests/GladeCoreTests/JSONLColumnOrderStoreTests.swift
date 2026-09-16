import XCTest
@testable import GladeCore

final class JSONLColumnOrderStoreTests: XCTestCase {
    private func preferences() throws -> UserDefaults {
        let suite = "GladeColumnOrderTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        return defaults
    }

    private func columns(_ keys: [String]) -> [JSONLTableColumn] {
        [.lineNumber] + keys.map(JSONLTableColumn.field)
    }

    func testOrderPersistsAndOverridesDifferentAutomaticRankingForSameKeys() throws {
        let defaults = try preferences()
        let store = JSONLColumnOrderStore(defaults: defaults)
        let original = columns(["timestamp", "message", "type"])
        let custom = columns(["type", "message", "timestamp"])
        store.save(custom, for: original)

        let reopened = JSONLColumnOrderStore(defaults: defaults)
        XCTAssertEqual(reopened.columns(for: columns(["message", "timestamp", "type"])), custom)
        XCTAssertTrue(reopened.hasSavedOrder(for: original))
    }

    func testMatchingUsesFullDocumentKeyUnionNotFilenamesValuesOrSparseRows() throws {
        let store = JSONLColumnOrderStore(defaults: try preferences())
        let first = JSONLDocument.parse(rawContent: "{\"message\":\"First message\",\"count\":1}\n{\"enabled\":true}",
                                        url: URL(fileURLWithPath: "/tmp/first.jsonl"))
        let second = JSONLDocument.parse(rawContent: "{\"enabled\":null,\"count\":999,\"message\":\"Completely different content\"}",
                                         url: URL(fileURLWithPath: "/tmp/elsewhere/second.jsonl"))
        let custom = columns(["enabled", "count", "message"])
        store.save(custom, for: first.tableColumns)
        XCTAssertEqual(store.columns(for: second.tableColumns), custom)
    }

    func testDifferentKeySetsAndCapitalizationDoNotReuseSavedOrder() throws {
        let store = JSONLColumnOrderStore(defaults: try preferences())
        store.save(columns(["c", "b", "a"]), for: columns(["a", "b", "c"]))
        for keys in [["a", "b"], ["a", "b", "c", "d"], ["a", "b", "d"], ["A", "b", "c"]] {
            XCTAssertEqual(store.columns(for: columns(keys)), columns(keys))
            XCTAssertFalse(store.hasSavedOrder(for: columns(keys)))
        }
    }

    func testArbitraryKeyNamesCannotCollideWithSeparatorsOrSpecialColumns() throws {
        let store = JSONLColumnOrderStore(defaults: try preferences())
        let first = columns(["a,b", "c", "", "line-number", "root-value"])
        let custom = columns(["", "root-value", "line-number", "c", "a,b"])
        store.save(custom, for: first)
        XCTAssertEqual(store.columns(for: first), custom)
        let different = columns(["a", "b,c", "", "line-number", "root-value"])
        XCTAssertEqual(store.columns(for: different), different)
        let escaped = columns(["a\"b", "c\nd", "日本語"])
        let escapedOrder = columns(["日本語", "c\nd", "a\"b"])
        store.save(escapedOrder, for: escaped)
        XCTAssertEqual(store.columns(for: escaped), escapedOrder)
    }

    func testLineGutterAndIncidentalRawContentStayOutsideSchemaIdentity() throws {
        let store = JSONLColumnOrderStore(defaults: try preferences())
        let schema = columns(["a", "b"])
        store.save(columns(["b", "a"]), for: schema)
        XCTAssertEqual(store.columns(for: schema + [.value]), columns(["b", "a"]) + [.value])
        store.save(columns(["a", "b"]) + [.value], for: schema + [.value])
        XCTAssertEqual(store.columns(for: schema), schema)
    }

    func testAutomaticOrderIsNotSavedUntilTheUserRearrangesColumns() throws {
        let defaults = try preferences()
        let store = JSONLColumnOrderStore(defaults: defaults)
        XCTAssertEqual(store.columns(for: columns(["a", "b"])), columns(["a", "b"]))
        XCTAssertEqual(store.columns(for: columns(["b", "a"])), columns(["b", "a"]))
        XCTAssertNil(defaults.object(forKey: JSONLColumnOrderStore.storageKey))
    }

    func testResetRestoresCurrentHeuristicAndPreservesOtherSchemas() throws {
        let defaults = try preferences()
        let store = JSONLColumnOrderStore(defaults: defaults)
        store.save(columns(["b", "a"]), for: columns(["a", "b"]))
        store.save(columns(["y", "x"]), for: columns(["x", "y"]))
        store.reset(for: columns(["b", "a"]))
        let reopened = JSONLColumnOrderStore(defaults: defaults)
        XCTAssertFalse(reopened.hasSavedOrder(for: columns(["a", "b"])))
        XCTAssertEqual(reopened.columns(for: columns(["a", "b"])), columns(["a", "b"]))
        XCTAssertEqual(reopened.columns(for: columns(["x", "y"])), columns(["y", "x"]))
    }

    func testInvalidMovesAndCorruptPreferencesFallBackSafely() throws {
        let defaults = try preferences()
        let schema = columns(["a", "b"])
        let store = JSONLColumnOrderStore(defaults: defaults)
        for invalid in [["b"], ["b", "b"], ["b", "x"], ["b", "a", "extra"]] {
            store.save(columns(invalid), for: schema)
            XCTAssertFalse(store.hasSavedOrder(for: schema))
        }
        store.save(columns(["b", "a"]), for: schema)
        let saved = try XCTUnwrap(defaults.dictionary(forKey: JSONLColumnOrderStore.storageKey))
        let key = try XCTUnwrap(saved.keys.first)
        for invalid in [["b", "b"], ["b"], ["b", "x"]] {
            defaults.set([key: invalid], forKey: JSONLColumnOrderStore.storageKey)
            XCTAssertEqual(JSONLColumnOrderStore(defaults: defaults).columns(for: schema), schema)
        }
        defaults.set("broken", forKey: JSONLColumnOrderStore.storageKey)
        XCTAssertEqual(JSONLColumnOrderStore(defaults: defaults).columns(for: schema), schema)
    }
}
