import XCTest
@testable import GladeCore

final class JSONLTableTests: XCTestCase {
    private func parse(_ content: String) -> JSONLDocument {
        JSONLDocument.parse(rawContent: content, url: URL(fileURLWithPath: "/tmp/table-fixture.jsonl"))
    }

    func testHeterogeneousRecordsKeepFieldsFromLaterRows() {
        let document = parse("{\"name\":\"First\",\"count\":1}\n{\"active\":true,\"name\":\"Second\"}")
        XCTAssertEqual(document.tableColumns, [.lineNumber, .field("name"), .field("count"), .field("active")])
        XCTAssertEqual(JSONLTableColumn.field("count").text(for: document.lines[1]), "—")
        XCTAssertEqual(JSONLTableColumn.field("active").text(for: document.lines[1]), "true")
    }

    func testMissingValuesAreDistinctFromNullAndEmptyStrings() {
        let document = parse("{\"value\":null}\n{\"value\":\"\"}\n{}")
        let column = JSONLTableColumn.field("value")
        XCTAssertEqual(document.lines.map { column.text(for: $0) }, ["null", "", "—"])
    }

    func testNonObjectAndMalformedRecordsRemainInspectable() {
        let document = parse("{\"id\":1}\n[1,2]\ntrue\nnull\n\"hello\"\n42\nbroken json")
        XCTAssertEqual(document.lines.count, 7)
        XCTAssertEqual(document.tableColumns, [.lineNumber, .field("id"), .value])
        XCTAssertEqual(document.lines.map { JSONLTableColumn.value.text(for: $0) },
                       ["—", "[2 items]", "true", "null", "hello", "42", "broken json"])
        XCTAssertNotNil(document.lines[6].parseError)
        XCTAssertEqual(JSONLTableColumn.lineNumber.text(for: document.lines[6]), "⚠ 7")
        XCTAssertEqual(document.lines[6].rawJSON, "broken json")
    }

    func testPhysicalLineNumbersSurviveBlankLinesAndCRLF() {
        let document = parse("\r\n{\"a\":1}\r\n\r\n{\"a\":2}\r\n")
        XCTAssertEqual(document.lines.map(\.lineNumber), [2, 4])
        XCTAssertEqual(document.lines.map { JSONLTableColumn.lineNumber.text(for: $0) }, ["2", "4"])
    }

    func testColumnIdentifiersDoNotCollideWithUserFields() {
        let document = parse("{\"Line\":1,\"Value / raw content\":2,\"line-number\":3,\"\":4}\nfalse")
        XCTAssertEqual(Set(document.tableColumns.map(\.identifier)).count, document.tableColumns.count)
        XCTAssertEqual(JSONLTableColumn.field("").text(for: document.lines[0]), "4")
    }

    func testLongAndMultilineCellsDoNotChangeFullContent() {
        let long = String(repeating: "a", count: 300)
        let document = parse("{\"message\":\"first\\nsecond\",\"long\":\"\(long)\",\"nested\":{\"key\":42}}")
        let line = document.lines[0]
        XCTAssertEqual(JSONLTableColumn.field("message").text(for: line), "first ↵ second")
        XCTAssertEqual(JSONLTableColumn.field("long").text(for: line), String(repeating: "a", count: 240) + "…")
        XCTAssertEqual(JSONLTableColumn.field("nested").text(for: line), "{1 keys}")
        XCTAssertTrue(line.rawJSON.contains(long))
        guard case .object(let fields) = line.parsed else { return XCTFail("Expected full object") }
        XCTAssertEqual(fields.first { $0.key == "message" }?.value, .string("first\nsecond"))
    }
}
