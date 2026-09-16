import XCTest
@testable import GladeCore

final class JSONLColumnOrderingTests: XCTestCase {
    private func columns(_ records: [[String: Any]]) throws -> [JSONLTableColumn] {
        let text = try records.map { record in
            String(decoding: try JSONSerialization.data(withJSONObject: record, options: [.sortedKeys]), as: UTF8.self)
        }.joined(separator: "\n")
        return JSONLDocument.parse(rawContent: text, url: URL(fileURLWithPath: "/tmp/ordering.jsonl")).tableColumns
    }

    func testTimestampThenProseTechnicalNumbersAndOtherValues() throws {
        let result = try columns([[
            "timestamp": "2026-09-15T17:00:00-07:00",
            "description": "The deployment finished and all services are healthy.",
            "command": "git log --oneline --max-count=5",
            "path": "/Users/alex/git/glade/README.md",
            "duration": 42,
            "active": true,
            "id": "d63c0c22-50a9-4e57-b073-bb6b1816a721",
        ]])
        XCTAssertEqual(result, [.lineNumber, .field("timestamp"), .field("description"),
                                .field("command"), .field("path"), .field("duration"), .field("active"), .field("id")])
    }

    func testMoreWordsWinBetweenEquallyReadableFields() throws {
        let result = try columns([[
            "a_label": "Ready",
            "b_title": "The deployment finished",
            "z_body": "The deployment finished successfully and all of the services are now healthy.",
        ]])
        XCTAssertEqual(result, [.lineNumber, .field("z_body"), .field("b_title"), .field("a_label")])
    }

    func testSparseProseMovesAfterDenseBooleansButTimestampStaysFirst() throws {
        var records: [[String: Any]] = (0..<8).map { _ in ["count": 0, "enabled": false] }
        records[0]["timestamp"] = "2026-09-15T17:00:00-07:00"
        records[0]["rare_description"] = "This sentence appears in only one record in the document."
        records[1]["rare_description"] = NSNull()
        records[2]["rare_description"] = "   "
        records[3]["rare_description"] = ""
        records[4]["rare_description"] = [Any]()
        records[5]["rare_description"] = ["empty": NSNull()]
        XCTAssertEqual(try columns(records), [.lineNumber, .field("timestamp"), .field("count"),
                                             .field("enabled"), .field("rare_description")])
    }

    func testNestedMessageContentCountsAsProse() throws {
        let result = try columns([[
            "message": ["role": "assistant", "content": [["type": "text", "text": "I found the problem and updated the file to fix it."]]],
            "role": "assistant",
            "cwd": "/Users/alex/git/glade",
            "usage": ["tokens": 123, "cost": 0.01],
        ]])
        XCTAssertEqual(result, [.lineNumber, .field("message"), .field("role"), .field("cwd"), .field("usage")])
    }

    func testOneLongOutlierDoesNotPromoteAnOtherwiseNumericColumn() throws {
        var records: [[String: Any]] = (0..<10).map { ["count": $0, "path": "src/Models/Document.swift", "message": "The file was opened successfully."] }
        records[0]["count"] = String(repeating: "This is a very long sentence. ", count: 100)
        XCTAssertEqual(try columns(records), [.lineNumber, .field("message"), .field("path"), .field("count")])
    }

    func testNaturalLanguageLikelihoodPrecedesWordCount() throws {
        var records: [[String: Any]] = (0..<10).map { _ in ["reliable": "All good", "mixed": "This field has a much longer readable sentence in most rows."] }
        for index in 0..<4 { records[index]["mixed"] = "src/Models/Document.swift" }
        XCTAssertEqual(try columns(records), [.lineNumber, .field("reliable"), .field("mixed")])
    }

    func testDateAliasNeedsTimestampValuesAndRowsAreNeverReordered() throws {
        let records: [[String: Any]] = [["created_at": "2026-09-15T17:00:00-07:00", "time": "Lunch time", "duration": 100],
                                      ["created_at": "2026-09-14T17:00:00-07:00", "time": "Dinner time", "duration": 0]]
        let expected: [JSONLTableColumn] = [.lineNumber, .field("created_at"), .field("time"), .field("duration")]
        XCTAssertEqual(try columns(records), expected)
        XCTAssertEqual(try columns(Array(records.reversed())), expected)
        let document = JSONLDocument.parse(rawContent: "{\"timestamp\":2}\n{\"timestamp\":1}", url: URL(fileURLWithPath: "/tmp/rows.jsonl"))
        XCTAssertEqual(document.lines.map { JSONLTableColumn.field("timestamp").text(for: $0) }, ["2", "1"])
    }

    func testTextBeyondTheSampleStillContributesToWordCount() throws {
        let result = try columns([[
            "a_shorter": String(repeating: "A readable sentence with several words. ", count: 100),
            "z_longer": String(repeating: "A readable sentence with several words. ", count: 200),
        ]])
        XCTAssertEqual(result, [.lineNumber, .field("z_longer"), .field("a_shorter")])
    }

    func testPaddingAndCommandVerbsDoNotMisclassifyNaturalSentences() throws {
        let result = try columns([[
            "a_padded_label": "Ready" + String(repeating: " ", count: 5_000),
            "z_sentence": "make sure the document can be opened and read",
            "command": "make build",
        ]])
        XCTAssertEqual(result, [.lineNumber, .field("z_sentence"), .field("a_padded_label"), .field("command")])
    }
}
