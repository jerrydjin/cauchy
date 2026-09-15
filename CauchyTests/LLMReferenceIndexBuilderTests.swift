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

    func testParsesCorrectedObjectAfterInvalidObject() throws {
        let raw = """
        {"references": [invalid]}
        Corrected:
        {"references": [{"kind":"lemma","number":"4.2","formatted_body":"A result with {braces}."}]}
        """

        let parsed = try LLMReferenceIndexResponseParser.parse(raw)

        XCTAssertEqual(parsed.references.count, 1)
        XCTAssertEqual(parsed.references[0].number, "4.2")
        XCTAssertEqual(parsed.references[0].formattedBody, "A result with {braces}.")
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
        // A bare SHA-256 of the file's bytes. The schema version used to be
        // glued on the end; it lives in the cache file itself now, so the
        // fingerprint stays a pure content hash.
        XCTAssertEqual(first.count, 64)
        XCTAssertTrue(first.allSatisfy(\.isHexDigit))
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
            entries: entries,
            builtWith: "on-device",
            failedPageIndices: []
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
            entries: entries,
            builtWith: "on-device",
            failedPageIndices: []
        )
        let snapshot = persisted.asSnapshot(pageCount: 10)
        let entry = snapshot.entries[ReferenceKey(kind: .theorem, number: "3.1")]

        XCTAssertEqual(entry?.formattedBody, "A theorem statement.")
        XCTAssertEqual(entry?.pageIndex, 2)
        XCTAssertEqual(snapshot.pageCount, 10)
    }
}

final class LLMReferenceIndexSupportTests: XCTestCase {
    /// A tripwire, not a fact worth asserting on its own: bumping the schema
    /// invalidates every cache on disk, so each quality-driven rebuild must be
    /// a deliberate edit here too.
    func testSchemaVersionMatchesCurrentIndexQualityContract() {
        XCTAssertEqual(PersistedReferenceIndex.schemaVersion, 5)
    }

    func testShouldUseVisionWhenCloudAndImagePresent() {
        XCTAssertTrue(
            LLMReferenceIndexSupport.shouldUseVision(cloudVisionAvailable: true, pageImagePNG: Data([0x89]))
        )
        XCTAssertFalse(
            LLMReferenceIndexSupport.shouldUseVision(cloudVisionAvailable: false, pageImagePNG: Data([0x89]))
        )
        XCTAssertFalse(
            LLMReferenceIndexSupport.shouldUseVision(cloudVisionAvailable: true, pageImagePNG: nil)
        )
    }

    func testOnDeviceIndexingUsesOneModelCallAtATime() {
        XCTAssertEqual(LLMReferenceIndexBuilder.maxConcurrentPagesOnDevice, 1)
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

    func testMergeKeepsOriginalStatementOverLongerLaterDiscussion() {
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

        XCTAssertEqual(results[key]?.formattedBody, "Short.")
        XCTAssertEqual(results[key]?.pageIndex, 0)
    }

    func testLongPageChunkingPreservesBeginningMiddleAndEnd() {
        let text = "BEGIN " + String(repeating: "a", count: 5_000)
            + "\n\nMIDDLE\n\n" + String(repeating: "b", count: 5_000) + " END"

        let chunks = ReferenceIndexPromptBuilder.pageTextChunks(text, maxCharacters: 2_000, overlapCharacters: 200)

        XCTAssertGreaterThan(chunks.count, 1)
        XCTAssertTrue(chunks.allSatisfy { $0.count <= 2_000 })
        XCTAssertTrue(chunks.contains { $0.contains("BEGIN") })
        XCTAssertTrue(chunks.contains { $0.contains("MIDDLE") })
        XCTAssertTrue(chunks.contains { $0.contains("END") })
    }

    func testGroundingRequiresMatchingKindAndNumber() {
        let page = "Definition 3.2 (Compactness). A space is compact when... Equation (4.1) follows."

        XCTAssertTrue(LLMReferenceIndexSupport.isGrounded(kind: .definition, number: "3.2", in: page))
        XCTAssertTrue(LLMReferenceIndexSupport.isGrounded(kind: .equation, number: "4.1", in: page))
        XCTAssertFalse(LLMReferenceIndexSupport.isGrounded(kind: .theorem, number: "3.2", in: page))
        XCTAssertFalse(LLMReferenceIndexSupport.isGrounded(kind: .definition, number: "9.9", in: page))
    }

    func testGroundedNameDropsInventedTitle() {
        let page = "Definition 3.2 (Compactness). A space is compact when..."

        XCTAssertEqual(LLMReferenceIndexSupport.groundedName("compactness", in: page), "compactness")
        XCTAssertNil(LLMReferenceIndexSupport.groundedName("Completeness", in: page))
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
