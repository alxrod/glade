import XCTest
@testable import GladeCore

final class JSONLineSearchTests: XCTestCase {
    func testNestedMatchesKeepAncestorsAndOriginalArrayIndices() {
        let value = JSONValue.object([
            .init(key: "irrelevant", value: .number(12)),
            .init(key: "message", value: .array([
                .string("skip"),
                .object([.init(key: "text", value: .string("Register this tool")),
                         .init(key: "other", value: .bool(false))]),
            ])),
        ])
        let search = JSONLineSearch(value: value, query: " register ")
        XCTAssertEqual(search.matchCount, 1)
        XCTAssertTrue(search.includes([]))
        XCTAssertTrue(search.includes([1]))
        XCTAssertTrue(search.includes([1, 1]))
        XCTAssertTrue(search.includes([1, 1, 0]))
        XCTAssertFalse(search.includes([0]))
        XCTAssertFalse(search.includes([1, 0]))
        XCTAssertFalse(search.includes([1, 1, 1]))
    }

    func testMatchingContainerKeyRevealsItsFullValueAndCountsDescendants() {
        let value = JSONValue.object([
            .init(key: "messages", value: .array([
                .string("message one"), .object([.init(key: "id", value: .number(42))]),
            ])),
            .init(key: "empty messages", value: .array([])),
            .init(key: "other", value: .null),
        ])
        let search = JSONLineSearch(value: value, query: "MESSAGE")
        XCTAssertEqual(search.matchCount, 3)
        XCTAssertTrue(search.includes([0, 1, 0]))
        XCTAssertTrue(search.includes([1]))
        XCTAssertFalse(search.includes([2]))
    }

    func testPrimitiveRootsAndRepeatedOccurrences() {
        XCTAssertEqual(JSONLineSearch(value: .string("hello HELLO hello"), query: "hello").matchCount, 3)
        for (value, query) in [(JSONValue.number(172), "172"), (.bool(false), "FALSE"), (.null, "null")] {
            let search = JSONLineSearch(value: value, query: query)
            XCTAssertEqual(search.matchCount, 1)
            XCTAssertTrue(search.includes([]))
        }
    }

    func testMalformedLineSearchesRawContentAndOtherLinesStayIndependent() {
        let malformed = JSONLLine(lineNumber: 2, rawJSON: "broken { register REGISTER")
        let unrelated = JSONLLine(lineNumber: 3, rawJSON: "{\"text\":\"elsewhere\"}")
        XCTAssertNotNil(malformed.parseError)
        XCTAssertEqual(JSONLineSearch(line: malformed, query: "register").matchCount, 2)
        XCTAssertEqual(JSONLineSearch(line: unrelated, query: "register").matchCount, 0)
    }

    func testEmptySearchRestoresAllPathsAndNoMatchHidesThem() {
        let value = JSONValue.array([.string("hello")])
        let empty = JSONLineSearch(value: value, query: " \n\t")
        XCTAssertFalse(empty.isActive)
        XCTAssertTrue(empty.includes([0]))
        XCTAssertEqual(empty.matchCount, 0)
        let missing = JSONLineSearch(value: value, query: "goodbye")
        XCTAssertTrue(missing.isActive)
        XCTAssertFalse(missing.includes([]))
        XCTAssertFalse(missing.includes([0]))
        XCTAssertEqual(missing.matchCount, 0)
    }

    func testUnicodeRangesReferToOriginalText() {
        let text = "👨‍👩‍👧‍👦 Straße STRASSE cafe\u{301} CAFÉ 日本語"
        let streetRanges = JSONLineSearch.ranges(in: text, query: "strasse")
        XCTAssertEqual(streetRanges.map { String(text[$0]) }, ["Straße", "STRASSE"])
        let accentRanges = JSONLineSearch.ranges(in: text, query: "café")
        XCTAssertEqual(accentRanges.map { String(text[$0]) }, ["cafe\u{301}", "CAFÉ"])
        XCTAssertEqual(JSONLineSearch.ranges(in: text, query: "日本語").map { String(text[$0]) }, ["日本語"])
    }

    func testSearchUsesDecodedContentInsteadOfJSONEscapes() {
        let line = JSONLLine(lineNumber: 1, rawJSON: #"{"text":"hello\nworld \u263a"}"#)
        XCTAssertEqual(JSONLineSearch(line: line, query: "hello\nworld").matchCount, 1)
        XCTAssertEqual(JSONLineSearch(line: line, query: "☺").matchCount, 1)
        XCTAssertEqual(JSONLineSearch(line: line, query: #"\u263a"#).matchCount, 0)
    }
}
