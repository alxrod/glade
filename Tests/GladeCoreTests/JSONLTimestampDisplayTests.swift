import XCTest
@testable import GladeCore

final class JSONLTimestampDisplayTests: XCTestCase {
    private func document(_ timestamps: [String]) throws -> JSONLDocument {
        let raw = try timestamps.map {
            String(decoding: try JSONSerialization.data(withJSONObject: ["timestamp": $0]), as: UTF8.self)
        }.joined(separator: "\n")
        return JSONLDocument.parse(rawContent: raw, url: URL(fileURLWithPath: "/tmp/timestamps.jsonl"))
    }

    private func displayed(_ document: JSONLDocument, column: JSONLTableColumn = .field("timestamp")) -> [String] {
        document.lines.map { document.compactTimestampCells[column.identifier]?[$0.id] ?? column.text(for: $0) }
    }

    func testSharedDateHourMinuteAndSecondAreRemovedAsWholeComponents() throws {
        XCTAssertEqual(displayed(try document(["2026-09-15T17:55:54.699Z", "2026-09-15T18:56:55.827Z"])),
                       ["17:55:54.699", "18:56:55.827"])
        XCTAssertEqual(displayed(try document(["2026-09-15T17:55:54.699Z", "2026-09-15T17:56:55.827Z"])),
                       ["55m 54.699s", "56m 55.827s"])
        XCTAssertEqual(displayed(try document(["2026-09-15T17:55:54.699Z", "2026-09-15T17:55:55.827Z"])),
                       ["54.699s", "55.827s"])
        XCTAssertEqual(displayed(try document(["2026-09-15T17:55:54.699Z", "2026-09-15T17:55:54.827Z"])),
                       [".699s", ".827s"])
    }

    func testCalendarBoundariesKeepTheFirstVaryingComponentAndEverythingAfterIt() throws {
        XCTAssertEqual(displayed(try document(["2026-09-15T23:59:59Z", "2026-09-16T00:00:00Z"])),
                       ["Day 15 · 23:59:59", "Day 16 · 00:00:00"])
        XCTAssertEqual(displayed(try document(["2026-09-30T23:59:59Z", "2026-10-01T00:00:00Z"])),
                       ["09-30 · 23:59:59", "10-01 · 00:00:00"])
        let differentYears = ["2025-12-31T23:59:59Z", "2026-01-01T00:00:00Z"]
        XCTAssertEqual(displayed(try document(differentYears)), differentYears)
    }

    func testDifferentOffsetsRetainFullTimestampsIncludingRepeatedDSTClockTimes() throws {
        let timestamps = ["2026-11-01T01:30:00-07:00", "2026-11-01T01:30:00-08:00"]
        XCTAssertEqual(displayed(try document(timestamps)), timestamps)
        let unzoned = ["2026-09-15T17:55:54Z", "2026-09-15T17:55:54"]
        XCTAssertEqual(displayed(try document(unzoned)), unzoned)
    }

    func testFractionalPrecisionIsPreservedWithoutFloatingPointRounding() throws {
        XCTAssertEqual(displayed(try document(["2026-09-15T17:55:54.000001Z", "2026-09-15T17:55:54.000001234Z"])),
                       [".000001s", ".000001234s"])
        XCTAssertEqual(displayed(try document(["2026-09-15T17:55:54Z", "2026-09-15T17:55:54.123Z"])),
                       ["17:55:54", "17:55:54.123"])
    }

    func testSingleAndIdenticalTimestampsNeverProduceEmptyCells() throws {
        let timestamp = "2026-09-15T17:55:54.699Z"
        XCTAssertEqual(displayed(try document([timestamp])), [timestamp])
        XCTAssertEqual(displayed(try document([timestamp, timestamp])), ["17:55:54.699", "17:55:54.699"])
        XCTAssertEqual(displayed(try document(["2026-09-15", "2026-09-15"])), ["2026-09-15", "2026-09-15"])
    }

    func testDateOnlyAndMinutePrecisionAreSupportedButMixedPrecisionStaysRaw() throws {
        XCTAssertEqual(displayed(try document(["2026-09-15", "2026-09-16"])), ["Day 15", "Day 16"])
        XCTAssertEqual(displayed(try document(["2026-09-15 17:55", "2026-09-15 17:56"])), ["55m", "56m"])
        let mixed = ["2026-09-15", "2026-09-15T17:55:54Z"]
        XCTAssertEqual(displayed(try document(mixed)), mixed)
    }

    func testMissingMalformedAndNonTimestampValuesStayUntouched() throws {
        let invalid = ["2026-02-30T17:55:54Z", "2026-09-15T25:55:54Z", "2026-09-15T17:55:54+25:00",
                       "2026-09-15-not-a-date", "2026-09-15T17:55:54Z\n", "not a timestamp"]
        let doc = try document(["2026-09-15T17:55:54Z", "2026-09-15T17:55:55Z"] + invalid)
        XCTAssertEqual(Array(displayed(doc).prefix(2)), ["54s", "55s"])
        for line in doc.lines.dropFirst(2) {
            XCTAssertNil(doc.compactTimestampCells[JSONLTableColumn.field("timestamp").identifier]?[line.id])
        }
        let sparse = JSONLDocument.parse(rawContent: "{\"timestamp\":\"2026-09-15T17:55:54Z\"}\n{}\n{\"timestamp\":null}\n{\"timestamp\":172}\n{\"timestamp\":\"2026-09-15T17:55:55Z\"}",
                                         url: URL(fileURLWithPath: "/tmp/sparse.jsonl"))
        XCTAssertEqual(displayed(sparse), ["54s", "—", "null", "172", "55s"])
    }

    func testFormattingUsesTheFullDocumentAndKeepsInspectorAndSearchSourcesRaw() throws {
        let timestamps = ["2026-09-15T17:55:54.699Z", "2026-09-16T17:55:55.827Z"]
        let doc = try document(timestamps)
        let filtered = doc.lines.filter { $0.rawJSON.contains("2026-09-15") }
        let line = try XCTUnwrap(filtered.first)
        XCTAssertEqual(doc.compactTimestampCells[JSONLTableColumn.field("timestamp").identifier]?[line.id], "Day 15 · 17:55:54.699")
        XCTAssertEqual(JSONLTableColumn.field("timestamp").text(for: line), timestamps[0])
        guard case .object(let fields) = line.parsed else { return XCTFail("Expected inspector object") }
        XCTAssertEqual(fields.first { $0.key == "timestamp" }?.value, .string(timestamps[0]))
        XCTAssertTrue(line.rawJSON.contains(timestamps[0]))
    }

    func testColumnsAreIndependentAndRootTimestampsAlsoCompact() throws {
        let doc = JSONLDocument.parse(rawContent: "{\"timestamp\":\"2026-09-15T17:55:54Z\",\"created_at\":\"2025-08-02T10:00:00Z\"}\n{\"timestamp\":\"2026-09-15T17:55:55Z\",\"created_at\":\"2025-08-02T11:00:00Z\"}",
                                      url: URL(fileURLWithPath: "/tmp/columns.jsonl"))
        XCTAssertEqual(displayed(doc), ["54s", "55s"])
        XCTAssertEqual(displayed(doc, column: .field("created_at")), ["10:00:00", "11:00:00"])
        let roots = JSONLDocument.parse(rawContent: "\"2026-09-15T17:55:54Z\"\n\"2026-09-15T17:55:55Z\"", url: doc.fileURL)
        XCTAssertEqual(displayed(roots, column: .value), ["54s", "55s"])
    }
}
