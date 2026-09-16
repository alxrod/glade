import XCTest
@testable import GladeCore

final class JSONLColumnLayoutStoreTests: XCTestCase {
    private func preferences() throws -> UserDefaults {
        let suite = "GladeColumnLayoutTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        return defaults
    }

    private func columns(_ keys: [String]) -> [JSONLTableColumn] {
        [.lineNumber] + keys.map(JSONLTableColumn.field)
    }

    func testOrderPersistsAndOverridesDifferentAutomaticRankingForSameKeys() throws {
        let defaults = try preferences()
        let store = JSONLColumnLayoutStore(defaults: defaults)
        let original = columns(["timestamp", "message", "type"])
        let custom = columns(["type", "message", "timestamp"])
        store.save(custom, for: original)

        let reopened = JSONLColumnLayoutStore(defaults: defaults)
        XCTAssertEqual(reopened.columns(for: columns(["message", "timestamp", "type"])), custom)
        XCTAssertTrue(reopened.hasSavedOrder(for: original))
    }

    func testMatchingUsesFullDocumentKeyUnionNotFilenamesValuesOrSparseRows() throws {
        let store = JSONLColumnLayoutStore(defaults: try preferences())
        let first = JSONLDocument.parse(rawContent: "{\"message\":\"First message\",\"count\":1}\n{\"enabled\":true}",
                                        url: URL(fileURLWithPath: "/tmp/first.jsonl"))
        let second = JSONLDocument.parse(rawContent: "{\"enabled\":null,\"count\":999,\"message\":\"Completely different content\"}",
                                         url: URL(fileURLWithPath: "/tmp/elsewhere/second.jsonl"))
        let custom = columns(["enabled", "count", "message"])
        store.save(custom, for: first.tableColumns)
        XCTAssertEqual(store.columns(for: second.tableColumns), custom)
    }

    func testDifferentKeySetsAndCapitalizationDoNotReuseSavedOrder() throws {
        let store = JSONLColumnLayoutStore(defaults: try preferences())
        store.save(columns(["c", "b", "a"]), for: columns(["a", "b", "c"]))
        for keys in [["a", "b"], ["a", "b", "c", "d"], ["a", "b", "d"], ["A", "b", "c"]] {
            XCTAssertEqual(store.columns(for: columns(keys)), columns(keys))
            XCTAssertFalse(store.hasSavedOrder(for: columns(keys)))
        }
    }

    func testArbitraryKeyNamesCannotCollideWithSeparatorsOrSpecialColumns() throws {
        let store = JSONLColumnLayoutStore(defaults: try preferences())
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
        let store = JSONLColumnLayoutStore(defaults: try preferences())
        let schema = columns(["a", "b"])
        store.save(columns(["b", "a"]), for: schema)
        XCTAssertEqual(store.columns(for: schema + [.value]), columns(["b", "a"]) + [.value])
        store.save(columns(["a", "b"]) + [.value], for: schema + [.value])
        XCTAssertEqual(store.columns(for: schema), schema)
    }

    func testAutomaticOrderIsNotSavedUntilTheUserRearrangesColumns() throws {
        let defaults = try preferences()
        let store = JSONLColumnLayoutStore(defaults: defaults)
        XCTAssertEqual(store.columns(for: columns(["a", "b"])), columns(["a", "b"]))
        XCTAssertEqual(store.columns(for: columns(["b", "a"])), columns(["b", "a"]))
        XCTAssertNil(defaults.object(forKey: JSONLColumnLayoutStore.storageKey))
    }

    func testResetRestoresCurrentHeuristicAndPreservesOtherSchemas() throws {
        let defaults = try preferences()
        let store = JSONLColumnLayoutStore(defaults: defaults)
        store.save(columns(["b", "a"]), for: columns(["a", "b"]))
        store.save(columns(["y", "x"]), for: columns(["x", "y"]))
        store.reset(for: columns(["b", "a"]))
        let reopened = JSONLColumnLayoutStore(defaults: defaults)
        XCTAssertFalse(reopened.hasSavedOrder(for: columns(["a", "b"])))
        XCTAssertEqual(reopened.columns(for: columns(["a", "b"])), columns(["a", "b"]))
        XCTAssertEqual(reopened.columns(for: columns(["x", "y"])), columns(["y", "x"]))
    }

    func testInvalidMovesAndCorruptPreferencesFallBackSafely() throws {
        let defaults = try preferences()
        let schema = columns(["a", "b"])
        let store = JSONLColumnLayoutStore(defaults: defaults)
        for invalid in [["b"], ["b", "b"], ["b", "x"], ["b", "a", "extra"]] {
            store.save(columns(invalid), for: schema)
            XCTAssertFalse(store.hasSavedOrder(for: schema))
        }
        store.save(columns(["b", "a"]), for: schema)
        let saved = try XCTUnwrap(defaults.dictionary(forKey: JSONLColumnLayoutStore.storageKey))
        let key = try XCTUnwrap(saved.keys.first)
        for invalid in [["b", "b"], ["b"], ["b", "x"]] {
            defaults.set([key: invalid], forKey: JSONLColumnLayoutStore.storageKey)
            XCTAssertEqual(JSONLColumnLayoutStore(defaults: defaults).columns(for: schema), schema)
        }
        defaults.set("broken", forKey: JSONLColumnLayoutStore.storageKey)
        XCTAssertEqual(JSONLColumnLayoutStore(defaults: defaults).columns(for: schema), schema)
    }

    func testWidthsPersistByColumnForTheExactKeySetRegardlessOfOrder() throws {
        let defaults = try preferences()
        let store = JSONLColumnLayoutStore(defaults: defaults)
        let schema = columns(["message", "count"])
        store.saveWidth(420, for: .field("message"), in: schema)
        store.saveWidth(110, for: .field("count"), in: schema)
        store.saveWidth(75, for: .lineNumber, in: schema)
        store.save(columns(["count", "message"]), for: schema)

        let reopened = JSONLColumnLayoutStore(defaults: defaults)
        XCTAssertEqual(reopened.widths(for: columns(["count", "message"])),
                       ["field:message": 420, "field:count": 110, "line-number": 75])
        for keys in [["message"], ["message", "count", "extra"], ["Message", "count"]] {
            XCTAssertTrue(reopened.widths(for: columns(keys)).isEmpty)
        }
    }

    func testInvalidWidthsAreIgnoredAndValidWidthsRespectNativeLimits() throws {
        let store = JSONLColumnLayoutStore(defaults: try preferences())
        let schema = columns(["message"])
        for invalid in [Double.nan, .infinity, -.infinity, 0, -20] {
            store.saveWidth(invalid, for: .field("message"), in: schema)
            XCTAssertTrue(store.widths(for: schema).isEmpty)
        }
        store.saveWidth(240, for: .field("absent"), in: schema)
        XCTAssertTrue(store.widths(for: schema).isEmpty)
        store.saveWidth(1, for: .field("message"), in: schema)
        XCTAssertEqual(store.widths(for: schema)["field:message"], JSONLTableColumn.field("message").minimumWidth)
        store.saveWidth(50_000, for: .field("message"), in: schema)
        XCTAssertEqual(store.widths(for: schema)["field:message"], JSONLTableColumn.field("message").maximumWidth)
    }

    func testHiddenColumnsPersistInSavedOrderAndCanBeRestoredIndividuallyOrTogether() throws {
        let defaults = try preferences()
        let store = JSONLColumnLayoutStore(defaults: defaults)
        let schema = columns(["a", "b", "c"])
        let custom = columns(["c", "b", "a"])
        store.save(custom, for: schema)
        store.saveWidth(360, for: .field("a"), in: schema)
        store.hide(.field("a"), in: schema)
        store.hide(.field("c"), in: schema)
        store.hide(.field("a"), in: schema)

        let reopened = JSONLColumnLayoutStore(defaults: defaults)
        XCTAssertEqual(reopened.hiddenColumns(for: custom), [.field("c"), .field("a")])
        XCTAssertEqual(reopened.columns(for: schema), custom)
        reopened.show(.field("c"), in: schema)
        XCTAssertEqual(reopened.hiddenColumns(for: schema), [.field("a")])
        reopened.showAll(in: schema)
        XCTAssertTrue(JSONLColumnLayoutStore(defaults: defaults).hiddenColumns(for: schema).isEmpty)
        XCTAssertEqual(reopened.widths(for: schema)["field:a"], 360)
        XCTAssertEqual(reopened.columns(for: schema), custom)
    }

    func testVisibilityIsScopedToExactKeySetAndAlwaysKeepsTheLineGutter() throws {
        let store = JSONLColumnLayoutStore(defaults: try preferences())
        let schema = columns(["a", "b"])
        for column in schema + [.field("absent")] { store.hide(column, in: schema) }
        XCTAssertEqual(store.hiddenColumns(for: schema), [.field("a"), .field("b")])
        for keys in [["a"], ["a", "b", "c"], ["A", "b"]] {
            XCTAssertTrue(store.hiddenColumns(for: columns(keys)).isEmpty)
        }
        let other = columns(["a", "c"])
        store.hide(.field("a"), in: other)
        store.showAll(in: schema)
        XCTAssertEqual(store.hiddenColumns(for: other), [.field("a")])
    }

    func testOptionalRawColumnKeepsItsWidthAndVisibilityWithoutChangingSchemaIdentity() throws {
        let defaults = try preferences()
        let store = JSONLColumnLayoutStore(defaults: defaults)
        let schema = columns(["a", "b"])
        store.saveWidth(500, for: .value, in: schema + [.value])
        store.hide(.value, in: schema + [.value])
        XCTAssertTrue(store.widths(for: schema).isEmpty)
        XCTAssertTrue(store.hiddenColumns(for: schema).isEmpty)
        let reopened = JSONLColumnLayoutStore(defaults: defaults)
        XCTAssertEqual(reopened.widths(for: schema + [.value]), ["root-value": 500])
        XCTAssertEqual(reopened.hiddenColumns(for: schema + [.value]), [.value])
        let rawOnly: [JSONLTableColumn] = [.lineNumber, .value]
        store.saveWidth(600, for: .value, in: rawOnly)
        store.hide(.value, in: rawOnly)
        XCTAssertEqual(store.widths(for: rawOnly), ["root-value": 600])
        XCTAssertEqual(store.hiddenColumns(for: rawOnly), [.value])
    }

    func testResettingOrderPreservesWidthsAndHiddenFields() throws {
        let defaults = try preferences()
        let store = JSONLColumnLayoutStore(defaults: defaults)
        let schema = columns(["a", "b"])
        store.save(columns(["b", "a"]), for: schema)
        store.saveWidth(270, for: .field("b"), in: schema)
        store.hide(.field("b"), in: schema)
        store.reset(for: schema)
        let reopened = JSONLColumnLayoutStore(defaults: defaults)
        XCTAssertEqual(reopened.columns(for: schema), schema)
        XCTAssertEqual(reopened.widths(for: schema), ["field:b": 270])
        XCTAssertEqual(reopened.hiddenColumns(for: schema), [.field("b")])
    }

    func testCorruptLayoutPreferencesCannotHideTheGutterOrApplyUnknownColumns() throws {
        let defaults = try preferences()
        let schema = columns(["a", "b"])
        let key = String(decoding: try JSONEncoder().encode(["a", "b"]), as: UTF8.self)
        defaults.set([key: ["field:a": -1.0, "field:b": 2_000.0, "field:absent": 200.0]],
                     forKey: JSONLColumnLayoutStore.widthsStorageKey)
        defaults.set([key: ["line-number", "field:a", "field:absent"]],
                     forKey: JSONLColumnLayoutStore.hiddenStorageKey)
        let store = JSONLColumnLayoutStore(defaults: defaults)
        XCTAssertEqual(store.widths(for: schema), ["field:b": JSONLTableColumn.field("b").maximumWidth])
        XCTAssertEqual(store.hiddenColumns(for: schema), [.field("a")])
        defaults.set("broken", forKey: JSONLColumnLayoutStore.widthsStorageKey)
        defaults.set([key: 12], forKey: JSONLColumnLayoutStore.hiddenStorageKey)
        let reopened = JSONLColumnLayoutStore(defaults: defaults)
        XCTAssertTrue(reopened.widths(for: schema).isEmpty)
        XCTAssertTrue(reopened.hiddenColumns(for: schema).isEmpty)
    }
}
