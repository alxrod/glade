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
