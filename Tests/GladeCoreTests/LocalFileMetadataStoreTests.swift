import XCTest
@testable import GladeCore

final class LocalFileMetadataStoreTests: XCTestCase {
    private let file = URL(fileURLWithPath: "/tmp/glade-annotations/first.jsonl")

    private func preferences() throws -> UserDefaults {
        let suite = "GladeFileMetadataTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        return defaults
    }

    private func document(_ content: String) -> JSONLDocument {
        JSONLDocument.parse(rawContent: content, url: file)
    }

    func testAliasPersistsForOneNormalizedFilePathAndCanBeRemoved() throws {
        let defaults = try preferences()
        let store = LocalFileMetadataStore(defaults: defaults)
        store.setAlias("  My logs  ", for: file)
        let reopened = LocalFileMetadataStore(defaults: defaults)
        XCTAssertEqual(reopened.alias(for: file), "My logs")
        XCTAssertEqual(reopened.alias(for: URL(fileURLWithPath: "/tmp/glade-annotations/folder/../first.jsonl")), "My logs")
        XCTAssertNil(reopened.alias(for: URL(fileURLWithPath: "/tmp/another/first.jsonl")))
        reopened.setAlias(" \n", for: file)
        XCTAssertNil(LocalFileMetadataStore(defaults: defaults).alias(for: file))
    }

    func testTagsPersistAcrossReparseAndUnrelatedInsertedLines() throws {
        let defaults = try preferences()
        let store = LocalFileMetadataStore(defaults: defaults)
        let original = document("{\"id\":1}\n{\"id\":2}")
        store.setTag(.purple, for: original.lines[1], in: file)
        let reopened = LocalFileMetadataStore(defaults: defaults)
        let changed = document("\n{\"id\":9}\n{\"id\":1}\n{\"id\":2}\n")
        XCTAssertEqual(reopened.rowTags(for: file, lines: changed.lines), [changed.lines[2].id: .purple])
        XCTAssertTrue(reopened.rowTags(for: URL(fileURLWithPath: "/tmp/copy.jsonl"), lines: changed.lines).isEmpty)
        XCTAssertEqual(changed.lines[2].rawJSON, "{\"id\":2}")
    }

    func testIdenticalRowsHaveIndependentTagsAndChangedContentDoesNotInheritThem() throws {
        let defaults = try preferences()
        let store = LocalFileMetadataStore(defaults: defaults)
        let original = document("{\"id\":1}\n{\"id\":1}\n{\"id\":2}")
        XCTAssertNotEqual(original.lines[0].annotationKey, original.lines[1].annotationKey)
        store.setTag(.red, for: original.lines[0], in: file)
        store.setTag(.blue, for: original.lines[1], in: file)
        let reopened = document("{\"id\":1}\n{\"id\":1}\n{\"id\":2}")
        XCTAssertEqual(store.rowTags(for: file, lines: reopened.lines), [reopened.lines[0].id: .red, reopened.lines[1].id: .blue])
        let edited = document("{\"id\":99}\n{\"id\":2}")
        XCTAssertTrue(store.rowTags(for: file, lines: edited.lines).isEmpty)
    }

    func testRetaggingAndRemovingPreserveOtherRowsAndAliases() throws {
        let defaults = try preferences()
        let store = LocalFileMetadataStore(defaults: defaults)
        let doc = document("{\"id\":1}\n{\"id\":2}")
        store.setAlias("Events", for: file)
        store.setTag(.orange, for: doc.lines[0], in: file)
        store.setTag(.green, for: doc.lines[1], in: file)
        store.setTag(.teal, for: doc.lines[0], in: file)
        XCTAssertEqual(store.rowTags(for: file, lines: doc.lines)[doc.lines[0].id], .teal)
        store.setTag(nil, for: doc.lines[0], in: file)
        let reopened = LocalFileMetadataStore(defaults: defaults)
        XCTAssertEqual(reopened.rowTags(for: file, lines: doc.lines), [doc.lines[1].id: .green])
        XCTAssertEqual(reopened.alias(for: file), "Events")
    }

    func testTaggedOnlyCombinesWithQueryAndImmediatelyExcludesAnUntaggedRow() throws {
        let store = LocalFileMetadataStore(defaults: try preferences())
        let doc = document("{\"type\":\"user\"}\n{\"type\":\"assistant\"}\n{\"type\":\"user\"}")
        store.setTag(.yellow, for: doc.lines[0], in: file)
        store.setTag(.red, for: doc.lines[1], in: file)
        let query = JSONLQuery(conditions: [.init(key: "type", operation: .equals, value: "user")], taggedOnly: true)
        let tags = store.rowTags(for: file, lines: doc.lines)
        XCTAssertEqual(doc.lines.filter { query.matches($0, isTagged: tags[$0.id] != nil) }.map(\.id), [doc.lines[0].id])
        store.setTag(nil, for: doc.lines[0], in: file)
        let changedTags = store.rowTags(for: file, lines: doc.lines)
        XCTAssertTrue(doc.lines.filter { query.matches($0, isTagged: changedTags[$0.id] != nil) }.isEmpty)
    }

    func testBatchRetaggingAndRemovalPersistOnlyForTargetedRowsAndFile() throws {
        let defaults = try preferences()
        let store = LocalFileMetadataStore(defaults: defaults)
        let content = "{\"id\":1}\n{\"id\":1}\n{\"id\":2}\n{\"id\":3}"
        let doc = document(content)
        let otherFile = URL(fileURLWithPath: "/tmp/glade-annotations/other.jsonl")
        store.setTag(.blue, for: doc.lines[0], in: file)
        store.setTag(.red, for: doc.lines[2], in: file)
        store.setTag(.orange, for: doc.lines, in: otherFile)
        store.setAlias("My selection", for: file)

        store.setTag(.purple, for: [doc.lines[0], doc.lines[1], doc.lines[3]], in: file)
        let reparsed = document(content)
        let reopened = LocalFileMetadataStore(defaults: defaults)
        XCTAssertEqual(reopened.rowTags(for: file, lines: reparsed.lines), [
            reparsed.lines[0].id: .purple, reparsed.lines[1].id: .purple,
            reparsed.lines[2].id: .red, reparsed.lines[3].id: .purple,
        ])

        reopened.setTag(nil, for: [reparsed.lines[0], reparsed.lines[3]], in: file)
        let afterRemoval = LocalFileMetadataStore(defaults: defaults)
        XCTAssertEqual(afterRemoval.rowTags(for: file, lines: reparsed.lines), [
            reparsed.lines[1].id: .purple, reparsed.lines[2].id: .red,
        ])
        XCTAssertEqual(afterRemoval.rowTags(for: otherFile, lines: reparsed.lines).count, 4)
        XCTAssertTrue(afterRemoval.rowTags(for: otherFile, lines: reparsed.lines).values.allSatisfy { $0 == .orange })
        XCTAssertEqual(afterRemoval.alias(for: file), "My selection")

        afterRemoval.setTag(nil, for: reparsed.lines, in: file)
        XCTAssertNil(defaults.dictionary(forKey: LocalFileMetadataStore.rowTagsKey)?[file.path])
        XCTAssertEqual(LocalFileMetadataStore(defaults: defaults).rowTags(for: otherFile, lines: reparsed.lines).count, 4)
    }

    func testBatchTaggingFilteredMatchesDoesNotTagHiddenRows() throws {
        let store = LocalFileMetadataStore(defaults: try preferences())
        let doc = document("{\"type\":\"user\"}\n{\"type\":\"assistant\"}\n{\"type\":\"user\"}")
        let query = JSONLQuery(conditions: [.init(key: "type", operation: .equals, value: "user")])
        store.setTag(.green, for: doc.lines.filter { query.matches($0) }, in: file)
        XCTAssertEqual(store.rowTags(for: file, lines: doc.lines), [doc.lines[0].id: .green, doc.lines[2].id: .green])
        store.setTag(.red, for: [], in: file)
        XCTAssertNil(store.rowTags(for: file, lines: doc.lines)[doc.lines[1].id])
    }

    func testCorruptAnnotationsAreIgnoredWithoutSavingDocumentContents() throws {
        let defaults = try preferences()
        let doc = document("{\"message\":\"private document content\"}")
        defaults.set([file.path: [doc.lines[0].annotationKey: "unknown-color"]], forKey: LocalFileMetadataStore.rowTagsKey)
        defaults.set([file.path: 12], forKey: LocalFileMetadataStore.aliasesKey)
        let store = LocalFileMetadataStore(defaults: defaults)
        XCTAssertNil(store.alias(for: file))
        XCTAssertTrue(store.rowTags(for: file, lines: doc.lines).isEmpty)
        store.setTag(.gray, for: doc.lines[0], in: file)
        let data = try PropertyListSerialization.data(fromPropertyList: defaults.dictionary(forKey: LocalFileMetadataStore.rowTagsKey) ?? [:], format: .xml, options: 0)
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("private document content"))
    }
}
