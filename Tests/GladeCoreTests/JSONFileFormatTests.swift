import XCTest
@testable import GladeCore

final class JSONFileFormatTests: XCTestCase {
    func testOnlySupportedFileExtensionsAreAccepted() {
        for ext in ["jsonl", "ndjson", "json", "JSONL", "NDJSON", "JSON"] {
            XCTAssertNotNil(JSONFileFormat(url: URL(fileURLWithPath: "/tmp/example.\(ext)")))
        }
        for name in ["example.md", "example.markdown", "example.mdown", "example.mkd",
                     "example.txt", "example.text", "example.csv", "example", "example.json.txt"] {
            XCTAssertNil(JSONFileFormat(url: URL(fileURLWithPath: "/tmp/\(name)")))
        }
        XCTAssertNil(JSONFileFormat(url: URL(string: "https://example.com/logs.jsonl")!))
    }

    func testLoaderRejectsTextFilesEvenWhenTheyContainValidJSON() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        for ext in ["txt", "md", "csv"] {
            let url = folder.appendingPathComponent("example.\(ext)")
            try #"{"message":"valid JSON with an unsupported filename"}"#.write(to: url, atomically: true, encoding: .utf8)
            XCTAssertThrowsError(try JSONLDocument.parse(from: url)) { error in
                guard case JSONDocumentError.unsupportedFileType = error else {
                    return XCTFail("Expected the shared file-type guard, got \(error)")
                }
            }
        }
        for ext in ["jsonl", "ndjson", "JSON"] {
            let url = folder.appendingPathComponent("example.\(ext)")
            try #"{"message":"supported"}"#.write(to: url, atomically: true, encoding: .utf8)
            XCTAssertEqual(try JSONLDocument.parse(from: url).lineCount, 1)
        }
    }

    func testFormattedJSONIsOneCompleteRecordWithOriginalRawContent() throws {
        let content = "\n{\n  \"message\": \"A readable message\",\n  \"details\": {\"count\": 3}\n}\n"
        let document = JSONLDocument.parse(rawContent: content, url: URL(fileURLWithPath: "/tmp/example.json"))
        XCTAssertEqual(document.lineCount, 1)
        let line = try XCTUnwrap(document.lines.first)
        XCTAssertNil(line.parseError)
        XCTAssertEqual(line.rawJSON, content)
        XCTAssertEqual(JSONLTableColumn.field("message").text(for: line), "A readable message")
        XCTAssertEqual(Set(JSONLTableColumn.fieldKeys(in: document.tableColumns)), ["message", "details"])
    }

    func testFormattedJSONArrayPreservesTheWholeValue() throws {
        let content = "[\n  {\"message\":\"first\"},\n  {\"message\":\"second\"}\n]"
        let document = JSONLDocument.parse(rawContent: content, url: URL(fileURLWithPath: "/tmp/example.JSON"))
        XCTAssertEqual(document.lineCount, 1)
        let line = try XCTUnwrap(document.lines.first)
        guard case .array(let values) = line.parsed else { return XCTFail("Expected the full array") }
        XCTAssertEqual(values.count, 2)
        XCTAssertEqual(line.rawJSON, content)
    }

    func testJSONDoesNotSilentlyAcceptMultipleTopLevelValues() throws {
        let document = JSONLDocument.parse(rawContent: "{\"a\":1}\n{\"a\":2}", url: URL(fileURLWithPath: "/tmp/example.json"))
        XCTAssertEqual(document.lineCount, 1)
        XCTAssertNotNil(try XCTUnwrap(document.lines.first).parseError)
    }

    func testJSONLinesAndNDJSONKeepPhysicalLineNumbers() {
        for ext in ["jsonl", "ndjson"] {
            let document = JSONLDocument.parse(rawContent: "\r\n{\"a\":1}\r\n\r\n{\"a\":2}\r\n", url: URL(fileURLWithPath: "/tmp/example.\(ext)"))
            XCTAssertEqual(document.lines.map(\.lineNumber), [2, 4])
            XCTAssertTrue(document.lines.allSatisfy { $0.parseError == nil })
        }
    }

    func testEmptyJSONHasNoRows() {
        XCTAssertEqual(JSONLDocument.parse(rawContent: " \n\t", url: URL(fileURLWithPath: "/tmp/empty.json")).lineCount, 0)
    }
}
