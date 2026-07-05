import XCTest
@testable import Cauchy

final class LLMReferenceIndexResponseParserTests: XCTestCase {
    func testParsesCleanJSON() throws {
        let raw = """
        {
          "references": [
            {
              "kind": "equation",
              "number": "1.4",
              "formatted_body": "$$x + y = z$$"
            }
          ]
        }
        """

        let parsed = try LLMReferenceIndexResponseParser.parse(raw)

        XCTAssertEqual(parsed.references.count, 1)
        XCTAssertEqual(parsed.references[0].kind, "equation")
        XCTAssertEqual(parsed.references[0].number, "1.4")
        XCTAssertEqual(parsed.references[0].formattedBody, "$$x + y = z$$")
    }

    func testParsesJSONWrappedInMarkdown() throws {
        let raw = """
        Here is the result:
        ```json
        {
          "references": [
            {
              "kind": "theorem",
              "number": "2.1",
              "formatted_body": "Every bounded sequence has a convergent subsequence."
            }
          ]
        }
        ```
        """

        let parsed = try LLMReferenceIndexResponseParser.parse(raw)

        XCTAssertEqual(parsed.references.count, 1)
        XCTAssertEqual(parsed.references[0].kind, "theorem")
        XCTAssertEqual(parsed.references[0].number, "2.1")
    }

    func testRejectsInvalidJSON() {
        XCTAssertThrowsError(try LLMReferenceIndexResponseParser.parse("not json at all"))
    }
}

final class ReferenceIndexCacheStoreTests: XCTestCase {
    func testFingerprintIsStableForSameContent() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let url = directory.appendingPathComponent("sample.pdf")
        try Data("same-content".utf8).write(to: url)

        let first = try ReferenceIndexCacheStore.fingerprint(for: url)
        let second = try ReferenceIndexCacheStore.fingerprint(for: url)

        XCTAssertEqual(first, second)
        XCTAssertTrue(first.hasSuffix("-v\(PersistedReferenceIndex.schemaVersion)"))
    }

    func testFingerprintChangesWhenContentChanges() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let url = directory.appendingPathComponent("sample.pdf")
        try Data("version-a".utf8).write(to: url)
        let first = try ReferenceIndexCacheStore.fingerprint(for: url)

        try Data("version-b".utf8).write(to: url)
        let second = try ReferenceIndexCacheStore.fingerprint(for: url)

        XCTAssertNotEqual(first, second)
    }

    func testRoundTripPersistedIndex() throws {
        let fingerprint = "abc123-v\(PersistedReferenceIndex.schemaVersion)"
        let entries: [ReferenceKey: IndexedReference] = [
            ReferenceKey(kind: .equation, number: "1.2"): IndexedReference(
                reference: DetectedReference(kind: .equation, number: "1.2"),
                formattedBody: "$$x + y = z$$",
                pageIndex: 4
            )
        ]
        let persisted = PersistedReferenceIndex(
            documentFingerprint: fingerprint,
            builtAt: Date(timeIntervalSince1970: 1_700_000_000),
            entries: entries
        )

        try ReferenceIndexCacheStore.save(persisted)
        let loaded = try ReferenceIndexCacheStore.load(fingerprint: fingerprint)
        defer { try? FileManager.default.removeItem(at: ReferenceIndexCacheStore.cacheFileURL(for: fingerprint)) }

        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.documentFingerprint, fingerprint)
        XCTAssertEqual(loaded?.entries.count, 1)
        XCTAssertEqual(loaded?.entries.first?.formattedBody, "$$x + y = z$$")
    }

    func testSnapshotLoadsEntries() {
        let entries: [ReferenceKey: IndexedReference] = [
            ReferenceKey(kind: .theorem, number: "3.1"): IndexedReference(
                reference: DetectedReference(kind: .theorem, number: "3.1"),
                formattedBody: "A theorem statement.",
                pageIndex: 2
            )
        ]

        let persisted = PersistedReferenceIndex(
            documentFingerprint: "fp",
            builtAt: Date(),
            entries: entries
        )
        let snapshot = persisted.asSnapshot(pageCount: 10)
        let entry = snapshot.entries[ReferenceKey(kind: .theorem, number: "3.1")]

        XCTAssertEqual(entry?.formattedBody, "A theorem statement.")
        XCTAssertEqual(entry?.pageIndex, 2)
        XCTAssertEqual(snapshot.pageCount, 10)
    }
}

final class LLMReferenceIndexSupportTests: XCTestCase {
    func testSchemaVersionIsV2() {
        XCTAssertEqual(PersistedReferenceIndex.schemaVersion, 2)
    }

    func testShouldUseVisionWhenGeminiAndImagePresent() {
        XCTAssertTrue(
            LLMReferenceIndexSupport.shouldUseVision(geminiVisionAvailable: true, pageImagePNG: Data([0x89]))
        )
        XCTAssertFalse(
            LLMReferenceIndexSupport.shouldUseVision(geminiVisionAvailable: false, pageImagePNG: Data([0x89]))
        )
        XCTAssertFalse(
            LLMReferenceIndexSupport.shouldUseVision(geminiVisionAvailable: true, pageImagePNG: nil)
        )
    }

    func testPreprocessPageTextConvertsUnicodeMath() {
        let raw = "Let f be continuous and x ≤ y."
        let processed = LLMReferenceIndexSupport.preprocessPageText(raw)
        XCTAssertTrue(processed.contains("$"))
        XCTAssertTrue(processed.contains("\\leq"))
    }

    func testPreprocessPageTextReturnsEmptyForBlankInput() {
        XCTAssertEqual(LLMReferenceIndexSupport.preprocessPageText("   "), "")
    }

    func testFinalizeReferenceBodyAcceptsValidLaTeX() {
        let body = "We have $$x + y = z$$"
        XCTAssertEqual(
            LLMReferenceIndexSupport.finalizeReferenceBody(normalized: body, repaired: nil),
            body
        )
    }

    func testFinalizeReferenceBodyUsesRepairedOutputWhenInitialInvalid() {
        let invalid = "Broken $$\\notacommand{x$$"
        let repaired = "$$x + y = z$$"
        XCTAssertEqual(
            LLMReferenceIndexSupport.finalizeReferenceBody(normalized: invalid, repaired: repaired),
            "$$x + y = z$$"
        )
    }

    func testFinalizeReferenceBodySkipsWhenStillInvalidAfterRepair() {
        let invalid = "Broken $$\\notacommand{x$$"
        XCTAssertNil(
            LLMReferenceIndexSupport.finalizeReferenceBody(normalized: invalid, repaired: invalid)
        )
    }

    func testMergePrefersLongerFormattedBody() {
        var results: [ReferenceKey: IndexedReference] = [:]
        let key = ReferenceKey(kind: .theorem, number: "3.1")

        LLMReferenceIndexSupport.merge(
            IndexedReference(
                reference: DetectedReference(kind: .theorem, number: "3.1"),
                formattedBody: "Short.",
                pageIndex: 0
            ),
            into: &results
        )
        LLMReferenceIndexSupport.merge(
            IndexedReference(
                reference: DetectedReference(kind: .theorem, number: "3.1"),
                formattedBody: "A much longer theorem statement.",
                pageIndex: 2
            ),
            into: &results
        )

        XCTAssertEqual(results[key]?.formattedBody, "A much longer theorem statement.")
        XCTAssertEqual(results[key]?.pageIndex, 2)
    }
}

final class DocumentBlockExtractorTests: XCTestCase {
    func testBuildsBlockFromIndexedReference() {
        let indexed = IndexedReference(
            reference: DetectedReference(kind: .equation, number: "9.9"),
            formattedBody: "$$a=b$$",
            pageIndex: 7
        )

        let block = DocumentBlockExtractor.block(from: indexed)

        XCTAssertEqual(block.reference.number, "9.9")
        XCTAssertEqual(block.formattedBody, "$$a=b$$")
        XCTAssertEqual(block.pageIndex, 7)
    }
}
