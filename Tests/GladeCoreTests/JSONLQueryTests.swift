import XCTest
@testable import GladeCore

final class JSONLQueryTests: XCTestCase {
    private func line(_ json: String) -> JSONLLine { JSONLLine(lineNumber: 1, rawJSON: json) }

    func testAllColumnConditionsAndGlobalSearchMustMatchTheSameRecord() {
        let query = JSONLQuery(text: " tool ", conditions: [
            JSONLColumnFilter(key: "message", value: "REGISTER"),
            JSONLColumnFilter(key: "type", operation: .equals, value: "user"),
        ])
        XCTAssertTrue(query.matches(line(#"{"message":"Register this tool","type":"user"}"#)))
        XCTAssertFalse(query.matches(line(#"{"message":"Register this tool","type":"assistant"}"#)))
        XCTAssertFalse(query.matches(line(#"{"message":"Register this","type":"user"}"#)))
        XCTAssertFalse(query.matches(line(#"{"message":"A tool","type":"user","other":"Register"}"#)))
    }

    func testContainsUsesDecodedFullNestedValuesAndTheirKeys() throws {
        let content = String(repeating: "x", count: 300) + " needle"
        let object = ["payload": [["specialKey": content]]]
        let data = try JSONSerialization.data(withJSONObject: object)
        let source = String(decoding: data, as: UTF8.self)
        XCTAssertTrue(JSONLColumnFilter(key: "payload", value: "NEEDLE").matches(line(source)))
        XCTAssertTrue(JSONLColumnFilter(key: "payload", value: "specialKey").matches(line(source)))
        XCTAssertEqual(JSONLColumnFilter(key: "payload", value: "missing").matches(line(source)), false)
        XCTAssertTrue(JSONLColumnFilter(key: "text", value: "hello\nworld").matches(line(#"{"text":"hello\nworld"}"#)))
    }

    func testEqualsRequiresWholeCaseSensitiveStringAndPreservesWhitespace() {
        let filter = JSONLColumnFilter(key: "type", operation: .equals, value: "user")
        XCTAssertTrue(filter.matches(line(#"{"type":"user"}"#)))
        for value in ["USER", "superuser", "user "] {
            XCTAssertFalse(filter.matches(line("{\"type\":\"\(value)\"}")))
        }
        XCTAssertTrue(JSONLColumnFilter(key: "text", operation: .equals, value: " ").matches(line(#"{"text":" "}"#)))
        XCTAssertTrue(JSONLColumnFilter(key: "text", operation: .equals, value: "").matches(line(#"{"text":""}"#)))
    }

    func testEqualsMatchesNumbersBooleansAndNullWithoutTreatingMissingAsNull() {
        let record = line(#"{"count":12,"enabled":false,"nothing":null,"text":"12"}"#)
        XCTAssertTrue(JSONLColumnFilter(key: "count", operation: .equals, value: "12.0").matches(record))
        XCTAssertFalse(JSONLColumnFilter(key: "count", operation: .equals, value: "1").matches(record))
        XCTAssertTrue(JSONLColumnFilter(key: "enabled", operation: .equals, value: "false").matches(record))
        XCTAssertFalse(JSONLColumnFilter(key: "enabled", operation: .equals, value: "0").matches(record))
        XCTAssertTrue(JSONLColumnFilter(key: "nothing", operation: .equals, value: "null").matches(record))
        XCTAssertFalse(JSONLColumnFilter(key: "absent", operation: .equals, value: "null").matches(record))
        XCTAssertFalse(JSONLColumnFilter(key: "text", operation: .equals, value: "12.0").matches(record))
    }

    func testStructuredEqualityIgnoresObjectKeyOrderButPreservesArrayOrderAndTypes() {
        let record = line(#"{"payload":{"b":[1,false],"a":"text"}}"#)
        XCTAssertTrue(JSONLColumnFilter(key: "payload", operation: .equals, value: #"{"a":"text","b":[1,false]}"#).matches(record))
        for invalid in [#"{"a":"text","b":[false,1]}"#, #"{"a":"text","b":[1,0]}"#, "broken"] {
            XCTAssertFalse(JSONLColumnFilter(key: "payload", operation: .equals, value: invalid).matches(record))
        }
    }

    func testEmptyQueryAndTextSearchSupportMalformedAndPrimitiveRows() {
        let malformed = line("broken sample")
        XCTAssertTrue(JSONLQuery().matches(malformed))
        XCTAssertTrue(JSONLQuery(text: "SAMPLE").matches(malformed))
        for record in [malformed, line("12"), line("null"), line("[]"), line("{}") ] {
            XCTAssertFalse(JSONLColumnFilter(key: "absent", value: "").matches(record))
        }
    }

    func testKeysAreLiteralAndUnicodeContainsIsCaseInsensitive() {
        let record = line(#"{"a.b":"CAFÉ","":"empty","field:x":"日本語"}"#)
        XCTAssertTrue(JSONLColumnFilter(key: "a.b", value: "café").matches(record))
        XCTAssertTrue(JSONLColumnFilter(key: "", value: "empty").matches(record))
        XCTAssertTrue(JSONLColumnFilter(key: "field:x", value: "日本語").matches(record))
    }

    func testEquivalentQueriesIgnoreTransientConditionIDs() {
        let first = JSONLQuery(conditions: [.init(key: "a", value: "hello")])
        let second = JSONLQuery(conditions: [.init(key: "a", value: "hello")])
        XCTAssertNotEqual(first, second)
        XCTAssertTrue(first.hasSameSearch(as: second))
        XCTAssertFalse(first.hasSameSearch(as: JSONLQuery(conditions: [.init(key: "a", operation: .equals, value: "hello")])))
    }
}
