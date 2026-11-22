import AppKit
import PDFKit
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

    /// The model writes one backslash. The parser doubles a known command
    /// before `JSONDecoder`, and leaves a paragraph `\n` as a newline.
    func testModelJSONKeepsLaTeXCommandsAndParagraphBreaks() throws {
        let raw = #"{"references":[{"kind":"theorem","number":"3.5.21","formatted_body":"$z_0 \notin U$, $f : U \backslash \{z_0\} \rightarrow \mathbb{C}$, $\neq$, $\to$, $\frac{1}{2}$\nMoreover, $z_0$ is removable."}]}"#
        let parsed = try LLMReferenceIndexResponseParser.parse(raw)
        let body = parsed.references[0].formattedBody
        XCTAssertTrue(body.contains("\\notin"), body)
        XCTAssertTrue(body.contains("\\backslash"), body)
        XCTAssertTrue(body.contains("\\{"), body)
        XCTAssertTrue(body.contains("\\rightarrow"), body)
        XCTAssertTrue(body.contains("\\mathbb"), body)
        XCTAssertTrue(body.contains("\\neq"), body)
        XCTAssertTrue(body.contains("\\to"), body)
        XCTAssertTrue(body.contains("\\frac"), body)
        XCTAssertTrue(body.contains("\nMoreover"), body)
        XCTAssertFalse(body.contains("\u{8}"), body)
        XCTAssertFalse(body.contains("\u{c}"), body)
        XCTAssertFalse(body.contains("\t"), body)

        let alreadyEscaped = #"{"references":[{"kind":"lemma","number":"1","formatted_body":"$\\gamma$ and $\\to$"}]}"#
        let kept = try LLMReferenceIndexResponseParser.parse(alreadyEscaped)
        XCTAssertEqual(kept.references[0].formattedBody, "$\\gamma$ and $\\to$")
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
                pageIndex: 4,
                evidence: ReferenceEvidence(
                    status: .supported,
                    sourceExcerpt: "x + y = z (1.2)",
                    matchedText: "(1.2)",
                    occurrenceCount: 1,
                    startOffset: 10,
                    endOffset: 25
                )
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
        XCTAssertEqual(loaded?.entries.first?.evidence?.sourceExcerpt, "x + y = z (1.2)")
    }

    func testRoundTripPreservesOCRCandidateEvidenceAndRegion() throws {
        let fingerprint = "ocr-candidate-\(UUID().uuidString)"
        let region = NormalizedRect(x: 0.67, y: 0.41, width: 0.24, height: 0.04)
        let candidate = OCRReferenceCandidate(
            kind: ReferenceKind.theorem.rawValue,
            number: "2.3",
            rawLine: "Theorem 2.3. OCR source",
            normalizedLine: "Theorem 2.3. OCR source",
            confidence: 0.92,
            region: region
        )
        let indexed = try XCTUnwrap(candidate.indexedReference(pageIndex: 7))
        let persisted = PersistedReferenceIndex(
            documentFingerprint: fingerprint,
            builtAt: Date(timeIntervalSince1970: 1_700_000_000),
            entries: [indexed.reference.key: indexed],
            builtWith: "Vision OCR candidates",
            failedPageIndices: []
        )

        try ReferenceIndexCacheStore.save(persisted)
        defer { try? FileManager.default.removeItem(at: ReferenceIndexCacheStore.cacheFileURL(for: fingerprint)) }
        let loaded = try XCTUnwrap(ReferenceIndexCacheStore.load(fingerprint: fingerprint))
        let entry = try XCTUnwrap(loaded.entries.first)

        XCTAssertEqual(entry.contentOrigin, .ocrCandidate)
        XCTAssertEqual(entry.evidence?.effectiveSource, .visionOCR)
        XCTAssertEqual(entry.evidence?.matchedRegion, region)
        XCTAssertEqual(loaded.asSnapshot(pageCount: 8).entries[indexed.reference.key]?.groundingBody, "")
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
    func testImageOnlyDocumentErrorExplainsIndexingBoundary() {
        XCTAssertTrue(
            ReferenceIndexBuildError.noExtractableText.localizedDescription.contains("local OCR")
        )
    }

    /// A tripwire, not a fact worth asserting on its own: bumping the schema
    /// invalidates every cache on disk, so each quality-driven rebuild must be
    /// a deliberate edit here too.
    func testSchemaVersionMatchesCurrentIndexQualityContract() {
        XCTAssertEqual(PersistedReferenceIndex.schemaVersion, 11)
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

    func testOCRFallbackTreatsPageNumberOnlyTextLayerAsImageOnly() {
        XCTAssertTrue(LLMReferenceIndexSupport.shouldUseOCRFallback(sourceText: "12"))
        XCTAssertTrue(LLMReferenceIndexSupport.shouldUseOCRFallback(sourceText: "Scanned by Library · 12"))
    }

    func testOCRFallbackDoesNotOverrideShortGroundedDeclaration() {
        XCTAssertFalse(LLMReferenceIndexSupport.shouldUseOCRFallback(
            sourceText: "Theorem 1.1. A short exact statement."
        ))
    }

    func testOCRFallbackDoesNotRunOnSubstantiveSearchableText() {
        let prose = String(repeating: "This is searchable technical prose. ", count: 4)
        XCTAssertFalse(LLMReferenceIndexSupport.shouldUseOCRFallback(sourceText: prose))
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

    func testTableOfContentsDetectionSeparatesSectionListingsFromStatements() {
        let contents = """
        CONTENTS
        6.1 Interiors and closures 39
        6.2 Limit points 40
        7.1 Basic definitions 43
        7.2 Complete metric spaces 44
        8.1 Connectedness 49
        """

        XCTAssertTrue(LLMReferenceIndexSupport.isLikelyTableOfContents(contents))
        XCTAssertFalse(
            LLMReferenceIndexSupport.isLikelyTableOfContents(
                "Definition 3.1.1 (Limit). A sequence converges when..."
            )
        )
    }

    func testContentsHeadingDoesNotHideTheArticleThatStartsOnTheSamePage() {
        let shared = """
        Contents
        1
        Introduction
        2
        2
        Estimates
        4
        Let M be a complete manifold of infinite volume with a smooth metric.
        The integral of the kernel over the sphere grows as the radius grows.
        Theorem 2. Let f be harmonic. Then the integral diverges.
        """
        let listing = """
        Contents
        6.1 Interiors and closures 39
        6.2 Limit points 40
        7.1 Basic definitions 43
        7.2 Complete metric spaces 44
        8.1 Connectedness 49
        """
        XCTAssertTrue(LLMReferenceIndexSupport.isLikelyTableOfContents(listing))
        XCTAssertFalse(LLMReferenceIndexSupport.shouldIndexStatements(in: listing))
        XCTAssertTrue(LLMReferenceIndexSupport.isLikelyTableOfContents(shared))
        XCTAssertTrue(LLMReferenceIndexSupport.shouldIndexStatements(in: shared))
        let indexed = LLMReferenceIndexSupport.declarationMatches(in: shared).map(\.reference.displayName)
        XCTAssertTrue(indexed.contains("Theorem 2"))
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

    func testEvidenceRetainsVerbatimSourceAndOffsets() {
        let page = "Introduction\n\nDefinition 3.2 (Compactness). A space is compact when every open cover has a finite subcover.\n\nProof."
        let reference = DetectedReference(kind: .definition, number: "3.2")

        let evidence = LLMReferenceIndexSupport.evidence(for: reference, in: page)

        XCTAssertEqual(evidence?.status, .supported)
        XCTAssertEqual(evidence?.matchedText, "Definition 3.2")
        XCTAssertEqual(evidence?.occurrenceCount, 1)
        XCTAssertTrue(evidence?.sourceExcerpt.contains("every open cover") == true)
        if let evidence {
            let start = String.Index(utf16Offset: evidence.startOffset, in: page)
            let end = String.Index(utf16Offset: evidence.endOffset, in: page)
            XCTAssertEqual(String(page[start..<end]), evidence.sourceExcerpt)
        }
    }

    func testEvidenceMarksRepeatedReferenceAsUncertainAndPrefersDeclaration() {
        let page = "By Theorem 2.1 we get the result.\n\nTheorem 2.1. Every bounded sequence has a convergent subsequence."
        let reference = DetectedReference(kind: .theorem, number: "2.1")

        let evidence = LLMReferenceIndexSupport.evidence(for: reference, in: page)

        XCTAssertEqual(evidence?.status, .uncertain)
        XCTAssertEqual(evidence?.occurrenceCount, 2)
        XCTAssertTrue(evidence?.sourceExcerpt.contains("Every bounded sequence") == true)
        let declaration = page.range(of: "Theorem 2.1", options: .backwards)!
        XCTAssertEqual(evidence?.matchStartOffset, declaration.lowerBound.utf16Offset(in: page))
        XCTAssertEqual(evidence?.matchEndOffset, declaration.upperBound.utf16Offset(in: page))
    }

    func testPageRegionContextStaysWithinPage() {
        let nearTop = NormalizedRect(x: 0.2, y: 0.96, width: 0.1, height: 0.02)
        let context = ReferenceEvidenceRegionResolver.contextRegion(for: nearTop)

        XCTAssertEqual(context.x, 0)
        XCTAssertEqual(context.width, 1)
        XCTAssertGreaterThanOrEqual(context.y, 0)
        XCTAssertLessThanOrEqual(context.y + context.height, 1)
        XCTAssertTrue(context.y <= nearTop.y && context.y + context.height >= nearTop.y + nearTop.height)
    }

    func testFigureCropSitsAboveACaptionLowerOnThePage() {
        let caption = NormalizedRect(x: 0.12, y: 0.30, width: 0.4, height: 0.02)
        let crop = ReferenceEvidenceRegionResolver.figureRegion(forCaption: caption)

        XCTAssertEqual(crop.x, 0)
        XCTAssertEqual(crop.width, 1)
        XCTAssertGreaterThanOrEqual(crop.y, caption.y + caption.height)
        XCTAssertEqual(crop.height, 0.55, accuracy: 0.000_001)
        XCTAssertLessThanOrEqual(crop.y + crop.height, 1)
    }

    func testFigureCropDropsBelowACaptionAtTheTopOfThePage() {
        let caption = NormalizedRect(x: 0.1, y: 0.94, width: 0.5, height: 0.03)
        let crop = ReferenceEvidenceRegionResolver.figureRegion(forCaption: caption)

        XCTAssertLessThanOrEqual(crop.y + crop.height, caption.y)
        XCTAssertEqual(crop.height, 0.55, accuracy: 0.000_001)
        XCTAssertGreaterThanOrEqual(crop.y, 0)
        XCTAssertEqual(crop.width, 1)
    }

    func testFigureCropUsesTheWholePageWhenTheLabelFillsIt() {
        let caption = NormalizedRect(x: 0, y: 0.10, width: 1, height: 0.80)
        let crop = ReferenceEvidenceRegionResolver.figureRegion(forCaption: caption)

        XCTAssertEqual(crop, NormalizedRect(x: 0, y: 0, width: 1, height: 1))
    }

    func testEvidenceRejectsUnsupportedModelReference() {
        XCTAssertNil(
            LLMReferenceIndexSupport.evidence(
                for: DetectedReference(kind: .lemma, number: "9.9"),
                in: "Theorem 1.1. A real statement."
            )
        )
    }

    func testIncompleteEquationTranscriptionFallsBackToSource() {
        XCTAssertNil(
            LLMReferenceIndexSupport.finalizeReferenceBody(
                normalized: "|x| ≤ r ⇒ |ψ(x)| ≤ 2|x| ≤",
                repaired: nil
            )
        )
        XCTAssertEqual(
            LLMReferenceIndexSupport.finalizeReferenceBody(
                normalized: "|x| ≤ r ⇒ |ψ(x)| ≤ r/2.",
                repaired: nil
            ),
            "|x| ≤ r ⇒ |ψ(x)| ≤ r/2."
        )
    }

    func testEvidenceCoversHardWrappedStatementBeforeNextDeclaration() {
        let page = "Example 1.4.1. Let f be continuous.\nIts derivative exists on the interior.\nThe boundary is excluded.\nExample 1.4.2. A different example follows."
        let evidence = LLMReferenceIndexSupport.evidence(
            for: DetectedReference(kind: .example, number: "1.4.1"),
            in: page
        )

        XCTAssertTrue(evidence?.sourceExcerpt.contains("The boundary is excluded") == true)
        XCTAssertFalse(evidence?.sourceExcerpt.contains("A different example") == true)
    }

    func testSourceFallbackStopsAtNextNumberedSection() {
        let page = "Example 1.4.2. A statement with an answer.\nThe last line of the example.\n1.5. Continuity and the chain rule\nUnrelated section prose."
        let match = LLMReferenceIndexSupport.declarationMatches(in: page).first!

        let body = LLMReferenceIndexSupport.fallbackBody(for: match, in: page)
        let evidence = LLMReferenceIndexSupport.evidence(for: match.reference, in: page)

        XCTAssertTrue(body?.contains("The last line") == true)
        XCTAssertFalse(body?.contains("Continuity and the chain rule") == true)
        XCTAssertFalse(evidence?.sourceExcerpt.contains("Unrelated section prose") == true)
    }

    func testStatementThatEndsThePageContinuesOnTheNext() {
        let page = "The two maps agree on the dense subset.\nTheorem 4.\n"
        let following = """
        A RUNNING HEADER
        2
        (1) The assignment is a continuous surjection.
        Proof. The kernel is prime.
        """
        let theorem = DetectedReference(kind: .theorem, number: "4")
        let entry = LLMReferenceIndexSupport.sourceDeclarationFallbacks(
            sourceText: page,
            pageIndex: 3,
            followingPageText: following
        )[theorem.key]

        XCTAssertTrue(entry?.formattedBody.contains("continuous surjection") == true)
        XCTAssertFalse(entry?.formattedBody.contains("RUNNING HEADER") == true)
        XCTAssertFalse(entry?.formattedBody.contains("Proof") == true)
        XCTAssertEqual(entry?.pageIndex, 3)

        let lemma = LLMReferenceIndexSupport.sourceDeclarationFallbacks(
            sourceText: "Agreed.\nLemma 4.\n",
            pageIndex: 1,
            followingPageText: "Let G be finite.\nThe order divides n.\n"
        )[DetectedReference(kind: .lemma, number: "4").key]
        XCTAssertTrue(lemma?.formattedBody.contains("finite") == true)
    }

    func testWrappedMentionAtTheEndOfAPageIsNotTheNextPage() {
        let wrapped = LLMReferenceIndexSupport.sourceDeclarationFallbacks(
            sourceText: "which proves\nTheorem 4.\n",
            pageIndex: 0,
            followingPageText: "(1) A different statement starts here.\n"
        )
        XCTAssertNil(wrapped[DetectedReference(kind: .theorem, number: "4").key])

        let section = LLMReferenceIndexSupport.sourceDeclarationFallbacks(
            sourceText: "This completes the argument.\nTheorem 4.\n",
            pageIndex: 0,
            followingPageText: "6.1. Lifting the cycle discriminant.\nThe proof begins.\n"
        )
        XCTAssertNil(section[DetectedReference(kind: .theorem, number: "4").key])

        let followed = LLMReferenceIndexSupport.sourceDeclarationFallbacks(
            sourceText: "This completes the argument.\nTheorem 4.\nCorollary 5. Let n be large.\n",
            pageIndex: 0,
            followingPageText: "(1) A different statement starts here.\n"
        )
        XCTAssertNil(followed[DetectedReference(kind: .theorem, number: "4").key])
        let corollary = followed[DetectedReference(kind: .corollary, number: "5").key]
        XCTAssertTrue(corollary?.formattedBody.contains("large") == true)
        XCTAssertFalse(corollary?.formattedBody.contains("different statement") == true)
    }

    func testDeclarationGuardSeparatesHeadingsFromCitations() {
        let page = "By Theorem 1.1 we know this.\n\nTheorem 2.1. Every bounded sequence has a convergent subsequence."
        let declarations = LLMReferenceIndexSupport.declarationMatches(in: page).map(\.reference)

        XCTAssertFalse(declarations.contains(DetectedReference(kind: .theorem, number: "1.1")))
        XCTAssertTrue(declarations.contains(DetectedReference(kind: .theorem, number: "2.1")))
    }

    func testFigureCaptionIsSourceOnlyAndPanelCitationsAreNotDeclarations() {
        let page = """
        Figure 3a shows an earlier result.
        Fig. 3 | Scaling learned interatomic potentials. a, Classification error.
        We compare this with Fig. 3d and Figure 3.
        """
        let figure = DetectedReference(kind: .figure, number: "3")
        let declarations = LLMReferenceIndexSupport.declarationMatches(in: page)
        XCTAssertEqual(declarations.filter { $0.reference == figure }.count, 1)

        let entries = LLMReferenceIndexSupport.sourceDeclarationFallbacks(
            sourceText: page, pageIndex: 4
        )
        let indexed = entries[figure.key]
        XCTAssertEqual(indexed?.formattedBody, "Scaling learned interatomic potentials")
        XCTAssertEqual(indexed?.contentOrigin, .sourceFallback)
        XCTAssertEqual(indexed?.evidence?.sourceExcerpt,
                       "Fig. 3 | Scaling learned interatomic potentials. a, Classification error.")
        XCTAssertEqual(indexed?.evidence?.matchedText, "Fig. 3")
        XCTAssertEqual(indexed?.evidence?.status, .supported)
        XCTAssertEqual(indexed?.evidence?.occurrenceCount, 4)
    }

    func testFigureCaptionTitleContinuesOnlyThroughLowercaseWrappedLine() {
        let page = """
        Figure 2.5: A contour inside a horseshoe domain can be contracted to a
        point along the dotted lines.
        Example 2.4.5. An annulus is not simply connected.
        """
        let figure = DetectedReference(kind: .figure, number: "2.5")
        let entry = LLMReferenceIndexSupport.sourceDeclarationFallbacks(
            sourceText: page, pageIndex: 54
        )[figure.key]

        XCTAssertEqual(entry?.formattedBody,
                       "A contour inside a horseshoe domain can be contracted to a point along the dotted lines")
        XCTAssertEqual(entry?.evidence?.sourceExcerpt,
                       "Figure 2.5: A contour inside a horseshoe domain can be contracted to a\npoint along the dotted lines.")
        XCTAssertFalse(entry?.evidence?.sourceExcerpt.contains("Example") == true)
    }

    func testAppendixDeclarationRetainedButCitationExcluded() {
        let page = "By Theorem A.0.1, the extension exists.\n\nRemark A.0.5. The two forms are independent."
        let declarations = LLMReferenceIndexSupport.declarationMatches(in: page).map(\.reference)

        XCTAssertFalse(declarations.contains(DetectedReference(kind: .theorem, number: "A.0.1")))
        XCTAssertTrue(declarations.contains(DetectedReference(kind: .remark, number: "A.0.5")))
    }

    func testLineStartStatementIsADeclarationAndAMentionIsNot() {
        let page = """
        Theorem 1.1.1
        Suppose the sequence of steps is elementary.
        Theorem 1.2 shows that the same bound is sharp.
        Lemma 2.2, so the order divides the exponent.
        Theorem 3.4 The probabilities assigned to the events sum to one.
        Theorem 4.1 .... 12
        """
        let declarations = LLMReferenceIndexSupport.declarationMatches(in: page).map(\.reference)

        XCTAssertTrue(declarations.contains(DetectedReference(kind: .theorem, number: "1.1.1")))
        XCTAssertTrue(declarations.contains(DetectedReference(kind: .theorem, number: "3.4")))
        XCTAssertFalse(declarations.contains(DetectedReference(kind: .theorem, number: "1.2")))
        XCTAssertFalse(declarations.contains(DetectedReference(kind: .lemma, number: "2.2")))
        XCTAssertFalse(declarations.contains(DetectedReference(kind: .theorem, number: "4.1")))
    }

    func testDottedEquationTagOnItsOwnLineIsADeclaration() {
        let page = """
        n D q times d plus r AND 0
        (1.2)
        This paragraph explains why the bound in the display is strict and cannot be improved further.
        (1.3)
        See below
        (1.4)
        """
        let numbers = LLMReferenceIndexSupport.declarationMatches(in: page).map(\.reference.number)

        XCTAssertTrue(numbers.contains("1.2"))
        XCTAssertTrue(numbers.contains("1.3"))
        XCTAssertTrue(numbers.contains("1.4"))
    }

    func testNumberFirstHeadingIsADeclaration() {
        let page = """
        6.1 Definition. A permutation of a set is a bijection onto itself.
        Later, 6.1 Definition appears inside a sentence and is not a second heading.
        6.13 Theorem (properties of multiplication). Let alpha be a permutation.
        8.2 Definition shows the same idea in prose.
        """
        let declarations = LLMReferenceIndexSupport.declarationMatches(in: page).map(\.reference)

        XCTAssertTrue(declarations.contains(DetectedReference(kind: .definition, number: "6.1")))
        XCTAssertEqual(declarations.filter { $0 == DetectedReference(kind: .definition, number: "6.1") }.count, 1)
        XCTAssertTrue(declarations.contains(DetectedReference(kind: .theorem, number: "6.13")))
        XCTAssertFalse(declarations.contains(DetectedReference(kind: .definition, number: "8.2")))
    }

    func testLigatureDefinitionHeadingIsIndexedAndAMentionIsNot() {
        let page = """
        De\u{FB01}nition 2.1. A widget is a finite set.
        By De\u{FB01}nition 2.1 every widget is nonempty.
        6.1 De\u{FB01}nition. A gadget is a widget with a name.
        """
        let declarations = LLMReferenceIndexSupport.declarationMatches(in: page).map(\.reference)

        XCTAssertEqual(
            declarations.filter { $0 == DetectedReference(kind: .definition, number: "2.1") }.count,
            1
        )
        XCTAssertTrue(declarations.contains(DetectedReference(kind: .definition, number: "6.1")))
    }

    func testParenthesizedStatementNumberIsADeclarationNotAnEquation() {
        let page = """
        Lemma (4). Suppose the group is finite.
        Apply Lemma (4) in the estimate (5).
        A = B + C (7)
        """
        let declarations = LLMReferenceIndexSupport.declarationMatches(in: page).map(\.reference)

        XCTAssertEqual(declarations.filter { $0 == DetectedReference(kind: .lemma, number: "4") }.count, 1)
        XCTAssertTrue(declarations.contains(DetectedReference(kind: .equation, number: "7")))
        XCTAssertFalse(declarations.contains(DetectedReference(kind: .equation, number: "4")))
        XCTAssertFalse(declarations.contains(DetectedReference(kind: .equation, number: "5")))
    }

    func testProseSentenceDoesNotDeclareABareEquation() {
        let page = """
        Proof. By construction f = g, so the equivalence between (1) follows at once.
        λ = 1 ⇒ (1) and (3)
        x = y + z (7)
        We minimize the joint loss
        L = λ ∑ x
        (5)
        where the two terms measure energy and force error.
        """
        let nsPage = page as NSString
        let positions = [
            nsPage.range(of: "(1)").location: 0.86,
        ]
        let declarations = LLMReferenceIndexSupport.declarationMatches(
            in: page, equationLabelX: positions
        ).map(\.reference)

        XCTAssertFalse(declarations.contains(DetectedReference(kind: .equation, number: "1")))
        XCTAssertFalse(declarations.contains(DetectedReference(kind: .equation, number: "3")))
        XCTAssertTrue(declarations.contains(DetectedReference(kind: .equation, number: "7")))
        XCTAssertTrue(declarations.contains(DetectedReference(kind: .equation, number: "5")))
    }

    func testDeclarationGuardAcceptsEquationNumberOnOwnLine() {
        let page = """
        We minimize the joint loss
        L = λE ∑ LHuber(δE, Ê, E) + λF ∑ LHuber(δF, −∂Ê/∂r, F)
        (1)
        where the two terms measure energy and force error.
        """

        let declarations = LLMReferenceIndexSupport.declarationMatches(in: page).map(\.reference)

        XCTAssertTrue(declarations.contains(DetectedReference(kind: .equation, number: "1")))
    }

    func testDottedEquationNumberAloneOnALineIsADeclaration() {
        let page = """
        The estimate is recorded below.
        (2.4)
        where the symbol denotes the usual pairing in the module.
        (3)
        where the reader may consult the appendix.
        """

        let declarations = LLMReferenceIndexSupport.declarationMatches(in: page).map(\.reference)

        XCTAssertTrue(declarations.contains(DetectedReference(kind: .equation, number: "2.4")))
        XCTAssertFalse(declarations.contains(DetectedReference(kind: .equation, number: "3")))
    }

    func testAppendixEquationTagAloneOnALineIsADeclaration() {
        let page = """
        The bound is recorded in the appendix.
        (A.1)
        where the constant is positive.
        (B.10)
        The hypotheses (H.1) and (H.2) stay inline.
        A bare (A) is not an equation.
        """

        let declarations = LLMReferenceIndexSupport.declarationMatches(in: page).map(\.reference)

        XCTAssertTrue(declarations.contains(DetectedReference(kind: .equation, number: "A.1")))
        XCTAssertTrue(declarations.contains(DetectedReference(kind: .equation, number: "B.10")))
        XCTAssertFalse(declarations.contains(DetectedReference(kind: .equation, number: "H.1")))
        XCTAssertFalse(declarations.contains(DetectedReference(kind: .equation, number: "H.2")))
        XCTAssertFalse(declarations.contains { $0.number == "A" })
    }

    func testDottedTagEndingAFormulaFragmentIsTheEquation() {
        // Synthetic. The tag ends the line. A comma, "0.", or a formula with
        // no equals sign is the equation. A sentence, a citation, and a table
        // cell are not.
        let page = """
        The display continues on the next line.
        , (2.18)
        where the remainder is positive.
        f(x, y) - g(x, y). (3.8)
        0. (5.9)
        \u{00B4}1qp0q (3.6)
        we conclude from (4.9)
        cf. (1.2)
        25 (9.6)
        27 (10.3) 26 (11.2)
        The estimate (2.2) follows from the bound.
        """
        let declarations = LLMReferenceIndexSupport.declarationMatches(in: page).map(\.reference)

        XCTAssertTrue(declarations.contains(DetectedReference(kind: .equation, number: "2.18")))
        XCTAssertTrue(declarations.contains(DetectedReference(kind: .equation, number: "3.8")))
        XCTAssertTrue(declarations.contains(DetectedReference(kind: .equation, number: "5.9")))
        XCTAssertTrue(declarations.contains(DetectedReference(kind: .equation, number: "3.6")))
        XCTAssertFalse(declarations.contains(DetectedReference(kind: .equation, number: "4.9")))
        XCTAssertFalse(declarations.contains(DetectedReference(kind: .equation, number: "1.2")))
        XCTAssertFalse(declarations.contains(DetectedReference(kind: .equation, number: "9.6")))
        XCTAssertFalse(declarations.contains(DetectedReference(kind: .equation, number: "10.3")))
        XCTAssertFalse(declarations.contains(DetectedReference(kind: .equation, number: "11.2")))
        XCTAssertFalse(declarations.contains(DetectedReference(kind: .equation, number: "2.2")))
    }

    func testDottedSubequationPartOnItsOwnLineIsTheBaseEquation() {
        let page = """
        The two parts of the display are tagged separately.
        (4.2a)
        (4.2b)
        A bare letter on an integer is a label, not an equation.
        (1a)
        """
        let declarations = LLMReferenceIndexSupport.declarationMatches(in: page).map(\.reference)

        XCTAssertEqual(
            declarations.filter { $0 == DetectedReference(kind: .equation, number: "4.2") }.count,
            2
        )
        XCTAssertFalse(declarations.contains(DetectedReference(kind: .equation, number: "1")))
        XCTAssertFalse(declarations.contains { $0.number.contains("a") || $0.number.contains("b") })
    }

    func testBareSubequationFamilyOnItsOwnLineIsTheBaseEquation() {
        let page = """
        Constraints of the model.
        (7a)
        (7b)
        Both tags are the same equation.
        A lone label (1a) is not an equation.
        """
        let declarations = LLMReferenceIndexSupport.declarationMatches(in: page).map(\.reference)

        XCTAssertEqual(
            declarations.filter { $0 == DetectedReference(kind: .equation, number: "7") }.count,
            2
        )
        XCTAssertFalse(declarations.contains(DetectedReference(kind: .equation, number: "1")))
        let solo = """
        Only one part is printed.
        (7a)
        See (7a) again.
        """
        XCTAssertFalse(
            LLMReferenceIndexSupport.declarationMatches(in: solo).map(\.reference).contains(
                DetectedReference(kind: .equation, number: "7")
            )
        )
    }

    func testOwnLineEquationKeepsTheFormulaOnTheNextLine() {
        let page = """
        (2)
        Then f = 0 whenever the hypothesis holds.
        We first consider recurrences of the form
        (1)
        xn+mxn = P(xn+1, . . . , xn+m−1) =
        for n ≥ 0.
        """

        let declarations = LLMReferenceIndexSupport.declarationMatches(in: page).map(\.reference)

        XCTAssertTrue(declarations.contains(DetectedReference(kind: .equation, number: "1")))
        XCTAssertFalse(declarations.contains(DetectedReference(kind: .equation, number: "2")))
    }

    func testOwnLineEquationIgnoresAFormulaMoreThanFourLinesLater() {
        let page = "(4)\n\n\n\n\nxn = yn + 1\n"

        let declarations = LLMReferenceIndexSupport.declarationMatches(in: page).map(\.reference)

        XCTAssertFalse(declarations.contains(DetectedReference(kind: .equation, number: "4")))
    }

    func testDeclarationGuardAcceptsEquationLabelAtBeginningOfLine() {
        let page = """
        By the mean value theorem we have
        (1.10) |x| ≤ r ⇒ |ψ(x)| ≤ r/2.
        Then by (1.10) the map has a fixed point.
        """

        let declarations = LLMReferenceIndexSupport.declarationMatches(in: page).map(\.reference)

        XCTAssertEqual(
            declarations.filter { $0 == DetectedReference(kind: .equation, number: "1.10") }.count,
            1
        )
    }

    func testPageGeometryAcceptsRightMarginEquationDespiteTextOrder() {
        let page = """
        A long displayed conditional-probability identity satisfies A = B = C = D = E = F. (5.1)
        To be precise, (5.1) assumes positive probability.
        Lemma 1.2. Let f : R→R be a solution of the IVP (1.1)
        with x = y on the following line.
        Theorem 6.13. Detailed balance holds iff
        (6.8)
        π_i p_ij = π_j p_ji.
        The relations (6.8) are known as detailed balance.
        """
        let nsPage = page as NSString
        let positions = [
            nsPage.range(of: "(5.1)").location: 0.788,
            nsPage.range(of: "(1.1)").location: 0.816,
            nsPage.range(of: "(6.8)").location: 0.788,
        ]

        let declarations = LLMReferenceIndexSupport.declarationMatches(
            in: page, equationLabelX: positions
        ).map(\.reference)

        XCTAssertEqual(declarations.filter { $0 == DetectedReference(kind: .equation, number: "5.1") }.count, 1)
        XCTAssertEqual(declarations.filter { $0 == DetectedReference(kind: .equation, number: "6.8") }.count, 1)
        XCTAssertFalse(declarations.contains(DetectedReference(kind: .equation, number: "1.1")))
    }

    func testPageGeometryRejectsEnumeratedProofStepsButKeepsLeftEquationLabel() {
        let page = """
        Proof.
        (1) f ∈ W ⇒ f = 0
        (2) f ∈ U ⇒ f = 0
        (3) f ∈ V ⇒ f = 0
        (1.10) |x| ≤ r ⇒ |ψ(x)| ≤ r/2.
        """
        let nsPage = page as NSString
        let positions = [
            nsPage.range(of: "(1)").location: 0.315,
            nsPage.range(of: "(2)").location: 0.269,
            nsPage.range(of: "(3)").location: 0.275,
            nsPage.range(of: "(1.10)").location: 0.118,
        ]
        let declarations = LLMReferenceIndexSupport.declarationMatches(
            in: page, equationLabelX: positions
        ).map(\.reference)

        for step in ["1", "2", "3"] {
            XCTAssertFalse(declarations.contains(DetectedReference(kind: .equation, number: step)))
        }
        XCTAssertTrue(declarations.contains(DetectedReference(kind: .equation, number: "1.10")))
    }

    func testLeftMarginEnumeratedStepsAreNotEquations() {
        let page = """
        Proof.
        (1) f ∈ W ⇒ f = 0
        (2) f ∈ U ⇒ f = 0
        (1.10) |x| ≤ r ⇒ |ψ(x)| ≤ r/2.
        A = B + C (4) for the constant term.
        """
        let nsPage = page as NSString
        let positions = [
            nsPage.range(of: "(1)").location: 0.129,
            nsPage.range(of: "(2)").location: 0.148,
            nsPage.range(of: "(1.10)").location: 0.118,
            nsPage.range(of: "(4)").location: 0.82,
        ]
        let declarations = LLMReferenceIndexSupport.declarationMatches(
            in: page, equationLabelX: positions
        ).map(\.reference)

        XCTAssertFalse(declarations.contains(DetectedReference(kind: .equation, number: "1")))
        XCTAssertFalse(declarations.contains(DetectedReference(kind: .equation, number: "2")))
        XCTAssertTrue(declarations.contains(DetectedReference(kind: .equation, number: "1.10")))
        XCTAssertTrue(declarations.contains(DetectedReference(kind: .equation, number: "4")))
    }

    func testOwnLineTagAfterStrictInequalityIsAnEquation() {
        // Synthetic. "≥" already counts as a display. A strict inequality is
        // the same relation when the text layer prints ">" or "<". A sentence
        // that only mentions the number is still a cross reference.
        let page = """
        The bound is strict.
        x_n > 0.
        (30)
        The argument continues in the next paragraph.
        0 < y < 1
        (12)
        A sentence that merely says n > 1 points at (8) for the bound.
        """
        let nsPage = page as NSString
        let positions = [
            nsPage.range(of: "(30)").location: 0.83,
            nsPage.range(of: "(12)").location: 0.83,
            nsPage.range(of: "(8)").location: 0.90,
        ]
        let declarations = LLMReferenceIndexSupport.declarationMatches(
            in: page, equationLabelX: positions
        ).map(\.reference)

        XCTAssertTrue(declarations.contains(DetectedReference(kind: .equation, number: "30")))
        XCTAssertTrue(declarations.contains(DetectedReference(kind: .equation, number: "12")))
        XCTAssertFalse(declarations.contains(DetectedReference(kind: .equation, number: "8")))

        let withoutGeometry = LLMReferenceIndexSupport.declarationMatches(in: page).map(\.reference)
        XCTAssertTrue(withoutGeometry.contains(DetectedReference(kind: .equation, number: "30")))
        XCTAssertTrue(withoutGeometry.contains(DetectedReference(kind: .equation, number: "12")))
        XCTAssertFalse(withoutGeometry.contains(DetectedReference(kind: .equation, number: "8")))
    }

    func testOwnLineTagBeforeASplitIntegralIsAnEquation() {
        // Synthetic. The integral sign and the domain extract as their own
        // lines, and the relation is still this tag's formula. A relation
        // five lines down belongs to a later display. A superscript "(1)"
        // above "i, B" is not a tag. Each page is separate so an earlier
        // relation cannot license a later number.
        let split = """
        By the definition of the kernel, we have
        (45)
        Z
        R
        H(t)
        2 d(t) =
        the sum of the traces.
        """
        let tooFar = """
        The bound is introduced as follows
        (7)
        Z
        R
        H(t)
        K(t)
        2 d(t) =
        which is too far below the number.
        """
        let superscript = """
        The indices are B
        (1)
        i , B
        (2)
        i , Ji
        i=1
        which stays a superscript.
        """
        let splitNumbers = LLMReferenceIndexSupport.indexableDeclarationMatches(in: split).map(\.reference)
        XCTAssertTrue(splitNumbers.contains(DetectedReference(kind: .equation, number: "45")))
        let tooFarNumbers = LLMReferenceIndexSupport.indexableDeclarationMatches(in: tooFar).map(\.reference)
        XCTAssertFalse(tooFarNumbers.contains(DetectedReference(kind: .equation, number: "7")))
        let superscriptNumbers = LLMReferenceIndexSupport.indexableDeclarationMatches(in: superscript).map(\.reference)
        XCTAssertFalse(superscriptNumbers.contains(DetectedReference(kind: .equation, number: "1")))
        XCTAssertFalse(superscriptNumbers.contains(DetectedReference(kind: .equation, number: "2")))
    }

    func testBareOwnLineFragmentsAreNotEquations() {
        // Synthetic. A split subscript, "(0)" under a one-digit line, and a
        // left-margin wrapped item are not tags. A formula on the next line,
        // a dotted tag, and "(14)" under a one-digit limit stay.
        let page = """
        Set f = g before the split.
        The expectation of the kernel E[R
        (1)
        x is at most one, which the hypothesis requires.
        L = a + b
        (2)
        where both terms are positive.
        The map sends each point to E
        0
        (0)
        decreases with the energy, as required.
        (3)
        xn = yn + 1
        An ideal containing I.
        (4)
        Q + 1
        The integral equals f = g.
        1
        (14)
        the bound continues below.
        The kernel E[R
        (8)
        x = y + z
        (1.4)
        """
        let nsPage = page as NSString
        let positions = [
            nsPage.range(of: "(4)").location: 0.16,
        ]

        let withGeometry = LLMReferenceIndexSupport.declarationMatches(
            in: page, equationLabelX: positions
        ).map(\.reference)
        XCTAssertFalse(withGeometry.contains(DetectedReference(kind: .equation, number: "1")))
        XCTAssertFalse(withGeometry.contains(DetectedReference(kind: .equation, number: "0")))
        XCTAssertFalse(withGeometry.contains(DetectedReference(kind: .equation, number: "4")))
        XCTAssertTrue(withGeometry.contains(DetectedReference(kind: .equation, number: "2")))
        XCTAssertTrue(withGeometry.contains(DetectedReference(kind: .equation, number: "3")))
        XCTAssertTrue(withGeometry.contains(DetectedReference(kind: .equation, number: "8")))
        XCTAssertTrue(withGeometry.contains(DetectedReference(kind: .equation, number: "14")))
        XCTAssertTrue(withGeometry.contains(DetectedReference(kind: .equation, number: "1.4")))

        let withoutGeometry = LLMReferenceIndexSupport.declarationMatches(in: page).map(\.reference)
        XCTAssertFalse(withoutGeometry.contains(DetectedReference(kind: .equation, number: "1")))
        XCTAssertFalse(withoutGeometry.contains(DetectedReference(kind: .equation, number: "0")))
        XCTAssertTrue(withoutGeometry.contains(DetectedReference(kind: .equation, number: "4")))
    }

    func testTheoremEvidenceKeepsEquationWithinItsStatement() {
        let page = """
        Theorem 6.13. Detailed balance holds iff
        (6.8)
        π_i p_ij = π_j p_ji.
        Theorem 6.14. Another result.
        """
        let evidence = LLMReferenceIndexSupport.evidence(
            for: DetectedReference(kind: .theorem, number: "6.13"), in: page
        )

        XCTAssertTrue(evidence?.sourceExcerpt.contains("(6.8)") == true)
        XCTAssertTrue(evidence?.sourceExcerpt.contains("π_i p_ij = π_j p_ji") == true)
        XCTAssertFalse(evidence?.sourceExcerpt.contains("Theorem 6.14") == true)
    }

    func testStandaloneEquationLabelKeepsPrecedingFormulaWhenPageEnds() {
        let page = """
        Proof. The estimate follows by integration.
        |f(t,y(t))| ds ≤ M|x−a|
        < M h ≤ k
        (1.17)
        15
        """
        let evidence = LLMReferenceIndexSupport.evidence(
            for: DetectedReference(kind: .equation, number: "1.17"),
            in: page
        )

        XCTAssertNotNil(evidence)
        XCTAssertTrue(evidence?.sourceExcerpt.contains("M h ≤ k") == true)
        XCTAssertTrue(evidence?.sourceExcerpt.contains("(1.17)") == true)
    }

    func testDeclarationGuardRejectsCitationYearsAndEquationCitations() {
        let page = """
        The method was introduced by Smith (2019) and refined later.
        See equation (3) for the corresponding objective.
        If z₀ = γ₁(0) = γ₂(0) then the two paths share a point.
        """

        XCTAssertTrue(LLMReferenceIndexSupport.declarationMatches(in: page).isEmpty)
    }

    func testDeclarationGuardRejectsEquationCitationAtEndOfLemmaLine() {
        let page = """
        Lemma 1.2. Let f : R → R be so that P(i) holds and let y(x) be any solution of the IVP (1.1)
        which is defined on an interval. Then |y(x)−b| ≤ k.
        """

        let declarations = LLMReferenceIndexSupport.declarationMatches(in: page).map(\.reference)

        XCTAssertTrue(declarations.contains(DetectedReference(kind: .lemma, number: "1.2")))
        XCTAssertFalse(declarations.contains(DetectedReference(kind: .equation, number: "1.1")))
    }

    func testNamedFallbackRetainsVerbatimStatementWhenModelMissesIt() {
        let page = "Example 2.3.8 (Hamming distance). Let X = {0, 1}ⁿ. Define d(x, y) to be the number of differing coordinates.\n\nRemark. More follows."
        var results: [ReferenceKey: IndexedReference] = [:]

        LLMReferenceIndexSupport.addNamedDeclarationFallbacks(
            sourceText: page,
            pageIndex: 4,
            to: &results
        )

        let entry = results[ReferenceKey(kind: .example, number: "2.3.8")]
        XCTAssertNotNil(entry)
        XCTAssertEqual(entry?.name, "Hamming distance")
        XCTAssertTrue(entry?.formattedBody.contains("Hamming distance") == true)
        XCTAssertTrue(entry?.formattedBody.contains("differing coordinates") == true)
        XCTAssertEqual(entry?.evidence?.sourceExcerpt, page)
    }

    func testFragmentOfThePreviousLineIsNotIndexed() {
        let page = """
        A = B + C
        (9)
        where the sum is taken.
        Finally, the argument was required to prove step 2 of
        Lemma 7. Since an alternative proof is given, Lemma 8 is not adapted.
        Lemma 4.2. Let G be a finite group.
        The matrix rows are
        0
        (1)
        \u{13}
        happens when B
        (2)
        n+1 = 1 and Yn+1 = 0, hence
        We first consider recurrences of the form
        (3)
        xn+mxn = P(xn+1) =
        The kernel E[R
        (8)
        x = y + z
        1
        (14)
        the bound continues below.
        Our first significant result is
        Theorem 1. Let X be a finite set.
        This completes the proof of the claim.

        Theorem 5. Let G be a finite group.
        """
        let detected = LLMReferenceIndexSupport.declarationMatches(in: page).map(\.reference)
        XCTAssertTrue(detected.contains(DetectedReference(kind: .lemma, number: "7")))
        XCTAssertTrue(detected.contains(DetectedReference(kind: .equation, number: "1")))
        XCTAssertTrue(detected.contains(DetectedReference(kind: .equation, number: "2")))
        let entries = LLMReferenceIndexSupport.sourceDeclarationFallbacks(
            sourceText: page, pageIndex: 0
        )
        XCTAssertNil(entries[ReferenceKey(kind: .lemma, number: "7")])
        XCTAssertNil(entries[ReferenceKey(kind: .equation, number: "1")])
        XCTAssertNil(entries[ReferenceKey(kind: .equation, number: "2")])
        XCTAssertNotNil(entries[ReferenceKey(kind: .lemma, number: "4.2")])
        XCTAssertNotNil(entries[ReferenceKey(kind: .equation, number: "9")])
        XCTAssertNotNil(entries[ReferenceKey(kind: .equation, number: "3")])
        XCTAssertNotNil(entries[ReferenceKey(kind: .equation, number: "8")])
        XCTAssertNotNil(entries[ReferenceKey(kind: .equation, number: "14")])
        XCTAssertNotNil(entries[ReferenceKey(kind: .theorem, number: "1")])
        XCTAssertNotNil(entries[ReferenceKey(kind: .theorem, number: "5")])
        XCTAssertFalse(LLMReferenceIndexSupport.isLikelyDeclaration(
            DetectedReference(kind: .equation, number: "1"), in: page
        ))
        XCTAssertTrue(LLMReferenceIndexSupport.isLikelyDeclaration(
            DetectedReference(kind: .equation, number: "9"), in: page
        ))
    }

    func testEquationNumberNeedsAFormulaOnItsLine() {
        // Synthetic. A citation that continues past the number, and a cell
        // between two integers, are not labels. A formula on the same line,
        // a tag that ends the line, a dotted tag, and "(14)" under a one-digit
        // limit followed by a sentence stay.
        let page = """
        The estimate is recorded below.
        (1.10) |x| ≤ r ⇒ |ψ(x)| ≤ r/2.
        A long identity satisfies A = B = C = D = E = F. (5.1)
        x = y + z (8).
        (2.4)
        where the symbol denotes the usual pairing.
        Let η1 and η2 solve the inequalities (2.51) and
        (2.52) respectively on the interval such that y2(t0) ≤ ηk(t0).
        The integral equals f = g.
        1
        (14)
        the bound continues below.
        1
        (12)
        12
        (9)
        where the sum is taken.
        """
        let nsPage = page as NSString
        let positions = [
            nsPage.range(of: "(5.1)").location: 0.86,
            nsPage.range(of: "(2.51)").location: 0.82,
            nsPage.range(of: "(8)").location: 0.84,
        ]
        let declarations = LLMReferenceIndexSupport.declarationMatches(
            in: page, equationLabelX: positions
        ).map(\.reference)

        XCTAssertTrue(declarations.contains(DetectedReference(kind: .equation, number: "1.10")))
        XCTAssertTrue(declarations.contains(DetectedReference(kind: .equation, number: "5.1")))
        XCTAssertTrue(declarations.contains(DetectedReference(kind: .equation, number: "8")))
        XCTAssertTrue(declarations.contains(DetectedReference(kind: .equation, number: "2.4")))
        XCTAssertTrue(declarations.contains(DetectedReference(kind: .equation, number: "14")))
        XCTAssertTrue(declarations.contains(DetectedReference(kind: .equation, number: "9")))
        XCTAssertFalse(declarations.contains(DetectedReference(kind: .equation, number: "2.51")))
        XCTAssertFalse(declarations.contains(DetectedReference(kind: .equation, number: "2.52")))
        XCTAssertFalse(declarations.contains(DetectedReference(kind: .equation, number: "12")))
    }

    func testEquationFallbackRetainsSourceEvidenceWhenModelMissesIt() {
        let page = """
        We minimize the joint loss
        L = λE ∑ LHuber(δE, Ê, E) + λF ∑ LHuber(δF, −∂Ê/∂r, F)
        (1)
        where the two terms measure energy and force error.
        """
        var results: [ReferenceKey: IndexedReference] = [:]

        LLMReferenceIndexSupport.addEquationDeclarationFallbacks(
            sourceText: page,
            pageIndex: 9,
            to: &results
        )

        let entry = results[ReferenceKey(kind: .equation, number: "1")]
        XCTAssertNotNil(entry)
        XCTAssertEqual(entry?.contentOrigin, .sourceFallback)
        XCTAssertTrue(entry?.formattedBody.contains("joint loss") == true)
        XCTAssertEqual(entry?.evidence?.sourceExcerpt, page)
    }

    func testDeclarationContextCentresEquationAndDropsDistantCitations() {
        let leading = String(repeating: "background prose ", count: 240)
        let trailing = String(repeating: " bibliography (2019)", count: 240)
        let page = leading + "\nL = λE ∑ loss + λF ∑ force\n(1)\nwhere the terms are defined.\n" + trailing

        let chunks = LLMReferenceIndexSupport.declarationContextChunks(
            pageText: page,
            sourceText: page
        )

        XCTAssertFalse(chunks.isEmpty)
        XCTAssertTrue(chunks.allSatisfy { $0.count <= 2_800 })
        XCTAssertTrue(chunks.joined().contains("(1)"))
        XCTAssertFalse(chunks.joined().hasSuffix("bibliography (2019)"))
    }
}

final class ReferenceIndexBenchmarkTests: XCTestCase {
    func testSourceOnlyBenchmarkConfigDoesNotRequireModelArguments() {
        let config = ReferenceIndexBenchmark.Config(arguments: [
            "Cauchy", "--benchmark-indexing", "/tmp/sample.pdf", "--source-only"
        ])

        XCTAssertNotNil(config)
        XCTAssertEqual(config?.sourceOnly, true)
        XCTAssertEqual(config?.sampleSize, 12)
    }

    func testReferenceAuditRetainsSourceOffsetsAndOrigin() throws {
        let source = "Theorem A.0.1. A source-backed statement."
        let entry = IndexedReference(
            reference: DetectedReference(kind: .theorem, number: "A.0.1"),
            formattedBody: "A formatted statement.",
            pageIndex: 2,
            evidence: ReferenceEvidence(
                status: .supported,
                sourceExcerpt: source,
                matchedText: "Theorem A.0.1",
                occurrenceCount: 1,
                startOffset: 0,
                endOffset: source.utf16.count
            ),
            contentOrigin: .modelTranscription
        )

        let audit = ReferenceIndexBenchmark.ReferenceAudit(entry)
        let decoded = try JSONDecoder().decode(
            ReferenceIndexBenchmark.ReferenceAudit.self,
            from: JSONEncoder().encode(audit)
        )

        XCTAssertEqual(decoded, audit)
        XCTAssertEqual(decoded.sourceExcerpt, source)
        XCTAssertEqual(decoded.formattedBody, "A formatted statement.")
        XCTAssertEqual(decoded.endOffset, source.utf16.count)
    }

    func testEvaluationMeasuresAccuracyAndAbstention() {
        let theorem = ReferenceIndexBenchmark.BenchmarkReference(kind: "theorem", number: "1.1")
        let extra = ReferenceIndexBenchmark.BenchmarkReference(kind: "lemma", number: "4.2")
        let metrics = ReferenceIndexBenchmark.evaluate(
            system: "test",
            predictionsByPage: [0: [theorem], 1: [], 2: [extra]],
            truthByPage: [0: [theorem], 1: [], 2: []],
            pageIndices: [0, 1, 2]
        )

        XCTAssertEqual(metrics.truePositives, 1)
        XCTAssertEqual(metrics.falsePositives, 1)
        XCTAssertEqual(metrics.falseNegatives, 0)
        XCTAssertEqual(metrics.precision, 0.5)
        XCTAssertEqual(metrics.recall, 1)
        XCTAssertEqual(metrics.correctAbstentions, 1)
        XCTAssertEqual(metrics.falsePositivePages, 1)
    }

    func testDeterministicBaselinesSeparateMentionsFromHeadings() {
        let page = "By Theorem 1.1 this follows.\nTheorem 2.1. A new statement.\nx + y = z (3.1)"

        let all = ReferenceIndexBenchmark.detectorBaseline(in: page)
        let declarations = ReferenceIndexBenchmark.declarationBaseline(in: page)

        XCTAssertTrue(all.contains(.init(kind: "theorem", number: "1.1")))
        XCTAssertTrue(all.contains(.init(kind: "theorem", number: "2.1")))
        XCTAssertFalse(declarations.contains(.init(kind: "theorem", number: "1.1")))
        XCTAssertTrue(declarations.contains(.init(kind: "theorem", number: "2.1")))
        XCTAssertTrue(declarations.contains(.init(kind: "equation", number: "3.1")))
    }

    func testGroundTruthValidationRejectsDuplicatePages() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("truth.json")
        let data = """
        {"schemaVersion":1,"document":"sample.pdf","pages":[
          {"pageNumber":1,"references":[],"notes":null},
          {"pageNumber":1,"references":[],"notes":null}
        ]}
        """.data(using: .utf8)!
        try data.write(to: url)

        XCTAssertThrowsError(try ReferenceIndexBenchmark.loadGroundTruth(from: url, pageCount: 2))
    }

    func testGroundTruthRejectsTheWrongPDFBytes() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let documentURL = directory.appendingPathComponent("sample.pdf")
        let truthURL = directory.appendingPathComponent("truth.json")
        try Data("original PDF".utf8).write(to: documentURL)
        let originalHash = try ReferenceIndexCacheStore.fingerprint(for: documentURL)
        let truth = """
        {"schemaVersion":1,"document":"doi:example;sha256:\(originalHash)","pages":[]}
        """.data(using: .utf8)!
        try truth.write(to: truthURL)

        XCTAssertNoThrow(try ReferenceIndexBenchmark.loadGroundTruth(
            from: truthURL, pageCount: 1, documentURL: documentURL
        ))
        try Data("different PDF".utf8).write(to: documentURL)
        XCTAssertThrowsError(try ReferenceIndexBenchmark.loadGroundTruth(
            from: truthURL, pageCount: 1, documentURL: documentURL
        )) { error in
            guard case ReferenceIndexBenchmark.GroundTruthError.documentMismatch = error else {
                return XCTFail("Expected documentMismatch, got \(error)")
            }
        }
    }
}

final class ReferenceMentionFinderTests: XCTestCase {
    func testCandidateMentionsMatchExactReferenceKindAndNumber() {
        let page = """
        By Theorem 2.2.13 we see that f is constant.
        Proposition 2.2.13 gives a different statement.
        Theorem 2.2.14 is not the result cited here.
        """

        let matches = ReferenceMentionFinder.candidateMatches(
            in: page,
            for: DetectedReference(kind: .theorem, number: "2.2.13")
        )

        XCTAssertEqual(matches.count, 1)
        XCTAssertEqual(matches.first?.matchedText, "Theorem 2.2.13")
        XCTAssertEqual(matches.first?.context, "By Theorem 2.2.13 we see that f is constant.")
    }

    func testCandidateOffsetsRemainUTF16CorrectAfterMathSymbols() {
        let page = "π → f. By Theorem 2.2.13 we conclude the claim."
        let matches = ReferenceMentionFinder.candidateMatches(
            in: page,
            for: DetectedReference(kind: .theorem, number: "2.2.13")
        )

        XCTAssertEqual(matches.count, 1)
        guard let match = matches.first else { return XCTFail("Expected a citation match") }
        let range = NSRange(location: match.startOffset,
                            length: match.endOffset - match.startOffset)
        XCTAssertEqual((page as NSString).substring(with: range), "Theorem 2.2.13")
    }

    func testStandaloneCitationIncludesPreviousProofLine() {
        let page = """
        Proof. Extend a basis of U to a basis of V. By
        Theorem 3.9
        the asserted block matrix follows.
        """
        let matches = ReferenceMentionFinder.candidateMatches(
            in: page,
            for: DetectedReference(kind: .theorem, number: "3.9")
        )

        XCTAssertEqual(matches.count, 1)
        XCTAssertTrue(matches.first?.context.contains("basis of V. By Theorem 3.9") == true)
    }
}

@MainActor
final class AskContextRetrieverEvidenceTests: XCTestCase {
    func testFigureRetrievalLabelsCaptionWithoutClaimingImageInterpretation() {
        let reference = DetectedReference(kind: .figure, number: "3")
        let source = "Fig. 3 | Scaling learned interatomic potentials. a, Classification error."
        let entry = IndexedReference(
            reference: reference,
            formattedBody: "Scaling learned interatomic potentials",
            pageIndex: 4,
            evidence: ReferenceEvidence(
                status: .supported,
                sourceExcerpt: source,
                matchedText: "Fig. 3",
                occurrenceCount: 1,
                startOffset: 0,
                endOffset: source.utf16.count
            ),
            contentOrigin: .sourceFallback
        )
        let index = DocumentReferenceIndex()
        index.replace(with: DocumentReferenceIndexSnapshot(entries: [reference.key: entry], pageCount: 5))

        let retrieval = AskContextRetriever.retrieve(
            question: "What does Fig. 3 show?",
            selectedText: "",
            surroundingText: "",
            pageIndex: nil,
            referenceIndex: index,
            documentIndex: nil,
            passageLimit: 0
        )

        XCTAssertEqual(retrieval.statements.count, 1)
        XCTAssertTrue(retrieval.statements[0].contains("caption heading only; image not interpreted"))
        XCTAssertTrue(retrieval.statements[0].contains(source))
        XCTAssertEqual(retrieval.statementReferences.map(\.reference), [reference])
    }

    func testRetrievalReportsOnlyPagesActuallySupplied() {
        let retrieval = AskRetrieval(
            statements: ["Theorem 1.2, p. 7 [PDF source excerpt]:\nStatement"],
            statementRoutes: ["cited"],
            passages: ["[p. 11] Another passage", "malformed passage"]
        )

        XCTAssertEqual(retrieval.sourcePageNumbers, [7, 11])
    }

    func testPassageLocationAllowsParagraphWhitespaceButNotAmbiguousText() {
        let page = "Introduction.\n\nA theorem has a first line.\n\nIts conclusion follows.\n\nEnd."
        let chunk = "A theorem has a first line.\nIts conclusion follows."
        let location = LexicalDocumentIndex.sourceLocation(
            for: chunk,
            in: page,
            pageIndex: 2,
            after: 0
        )
        XCTAssertEqual(location?.pageIndex, 2)
        XCTAssertEqual(location?.matchedText, "A theorem has a first line.\n\nIts conclusion follows.")
        XCTAssertEqual(location?.startOffset, (page as NSString).range(of: "A theorem").location)
        XCTAssertNil(LexicalDocumentIndex.sourceLocation(
            for: "Repeated source text.",
            in: "Repeated source text.\nRepeated source text.",
            pageIndex: 0,
            after: 0
        ))
    }

    func testPromptClippingDropsPassageLocationWhenSourceTextIsTruncated() {
        let passage = "[p. 3] " + String(repeating: "source ", count: 130)
        let location = PDFTextLocation(
            pageIndex: 2,
            matchedText: String(repeating: "source ", count: 130),
            startOffset: 0,
            endOffset: 910
        )
        let retrieval = AskRetrieval(
            statements: [],
            statementRoutes: [],
            passages: [passage],
            passageRecords: [DocumentPassage(text: passage, location: location)]
        )

        let clipped = retrieval.clippedForPrompt(provider: .onDevice)

        XCTAssertEqual(clipped.passages.count, 1)
        XCTAssertLessThan(clipped.passages[0].count, passage.count)
        XCTAssertNil(clipped.passageRecords[0].location)

        let complete = DocumentPassage(
            text: "[p. 3] A complete source passage that is long enough for the prompt budget.",
            location: location
        )
        let completeRetrieval = AskRetrieval(
            statements: [],
            statementRoutes: [],
            passages: [complete.text],
            passageRecords: [complete]
        ).clippedForPrompt(provider: .onDevice)
        XCTAssertEqual(completeRetrieval.passageRecords.first?.location, location)
    }

    func testAskRetrievalCarriesAnchoredPassageWithoutInventingARegion() {
        let location = PDFTextLocation(
            pageIndex: 2,
            matchedText: "A passage from the PDF.",
            startOffset: 50,
            endOffset: 73
        )
        let record = DocumentPassage(
            text: "[p. 3] A passage from the PDF.",
            location: location
        )
        let retrieval = AskContextRetriever.retrieve(
            question: "What does the passage say?",
            selectedText: "",
            surroundingText: "",
            pageIndex: nil,
            referenceIndex: nil,
            documentIndex: AnchoredPassageIndexStub(record: record),
            passageLimit: 1
        )

        XCTAssertEqual(retrieval.passages, [record.text])
        XCTAssertEqual(retrieval.passageRecords, [record])
    }

    func testAnswerContextUsesPDFEvidenceInsteadOfModelTranscription() {
        let reference = DetectedReference(kind: .theorem, number: "A.0.1")
        let source = "Theorem A.0.1. For each x_n in the sequence, its limit is x."
        let entry = IndexedReference(
            reference: reference,
            formattedBody: "For each x^n in the sequence, its limit is x.",
            pageIndex: 2,
            evidence: ReferenceEvidence(
                status: .supported,
                sourceExcerpt: source,
                matchedText: "Theorem A.0.1",
                occurrenceCount: 1,
                startOffset: 0,
                endOffset: source.utf16.count
            )
        )
        let index = DocumentReferenceIndex()
        index.replace(with: DocumentReferenceIndexSnapshot(entries: [reference.key: entry], pageCount: 3))

        let retrieval = AskContextRetriever.retrieve(
            question: "What does Theorem A.0.1 say?",
            selectedText: "",
            surroundingText: "",
            pageIndex: nil,
            referenceIndex: index,
            documentIndex: nil,
            passageLimit: 0
        )

        XCTAssertEqual(retrieval.statements.count, 1)
        XCTAssertTrue(retrieval.statements[0].contains(source))
        XCTAssertFalse(retrieval.statements[0].contains("x^n"))
        XCTAssertTrue(DocumentReferenceIndexSnapshot.searchableText(for: entry).contains("x_n"))
    }

    func testLegacyEntryWithoutEvidenceIsNotInjectedAsGroundTruth() {
        let reference = DetectedReference(kind: .theorem, number: "1.1")
        let entry = IndexedReference(
            reference: reference,
            formattedBody: "A model-only statement.",
            pageIndex: 0
        )
        let index = DocumentReferenceIndex()
        index.replace(with: DocumentReferenceIndexSnapshot(entries: [reference.key: entry], pageCount: 1))

        let retrieval = AskContextRetriever.retrieve(
            question: "What does Theorem 1.1 say?",
            selectedText: "",
            surroundingText: "",
            pageIndex: nil,
            referenceIndex: index,
            documentIndex: nil,
            passageLimit: 0
        )

        XCTAssertTrue(retrieval.statements.isEmpty)
    }

    func testReplacingIndexRetainsMentionGraphAndClearingRemovesIt() {
        let reference = DetectedReference(kind: .theorem, number: "1.1")
        let entry = IndexedReference(
            reference: reference,
            formattedBody: "A theorem.",
            pageIndex: 0
        )
        let expected = ReferenceMentionSearchResult(
            mentions: [],
            pagesWithoutText: 1,
            unresolvedMatches: 0,
            truncated: false
        )
        let graph = ReferenceMentionGraph(
            schemaVersion: ReferenceMentionGraph.schemaVersion,
            documentFingerprint: "fingerprint",
            records: [ReferenceGraphRecord(
                definition: ReferenceGraphDefinition(
                    reference: reference,
                    pageIndex: 0,
                    definingEndOffset: nil
                ),
                result: expected
            )]
        )
        let index = DocumentReferenceIndex()

        index.replace(with: DocumentReferenceIndexSnapshot(
            entries: [reference.key: entry],
            pageCount: 1,
            mentionGraph: graph
        ))
        XCTAssertEqual(index.laterMentions(for: reference), expected)

        index.clear()
        XCTAssertNil(index.laterMentions(for: reference))
    }
}

final class OCRReferenceCandidateDetectorTests: XCTestCase {
    func testRepairsOnlyPunctuationNoiseInNumberedHeadings() {
        XCTAssertEqual(
            OCRReferenceCandidateDetector.normalizeReferenceLabel(
                in: "Definition 1.3. 2. Suppose that u is twice differentiable."
            ),
            "Definition 1.3.2. Suppose that u is twice differentiable."
        )
        XCTAssertEqual(
            OCRReferenceCandidateDetector.normalizeReferenceLabel(
                in: "Theorem 1,3.3. Let U be open."
            ),
            "Theorem 1.3.3. Let U be open."
        )
        XCTAssertEqual(
            OCRReferenceCandidateDetector.normalizeReferenceLabel(
                in: "Remark 1.4.1 r. OCR did not resolve the final digit."
            ),
            "Remark 1.4.1 r. OCR did not resolve the final digit."
        )
    }

    func testFindsNamedAndRightMarginEquationCandidatesWithRegions() {
        let headingRegion = NormalizedRect(x: 0.2, y: 0.7, width: 0.6, height: 0.04)
        let equationRegion = NormalizedRect(x: 0.8, y: 0.5, width: 0.1, height: 0.03)
        let result = OCRResult(
            rawText: "",
            observations: [
                OCRTextObservation(
                    text: "Definition 1.3. 2. Suppose that u is twice differentiable.",
                    confidence: 0.91,
                    boundingBox: headingRegion
                ),
                OCRTextObservation(
                    text: "(1.3.4)",
                    confidence: 0.88,
                    boundingBox: equationRegion
                ),
                OCRTextObservation(
                    text: "By (1.3.5) the result follows.",
                    confidence: 0.95,
                    boundingBox: NormalizedRect(x: 0.2, y: 0.4, width: 0.6, height: 0.03)
                ),
            ],
            latexSnippet: ""
        )

        let candidates = OCRReferenceCandidateDetector.candidates(in: result)

        XCTAssertEqual(candidates.map { "\($0.kind):\($0.number)" }, [
            "definition:1.3.2", "equation:1.3.4",
        ])
        XCTAssertEqual(candidates[0].region, headingRegion)
        XCTAssertEqual(candidates[1].region, equationRegion)
    }

    func testCandidateIsRegionAnchoredButNeverAnswerGrounding() throws {
        let region = NormalizedRect(x: 0.1, y: 0.8, width: 0.7, height: 0.04)
        let candidate = OCRReferenceCandidate(
            kind: ReferenceKind.definition.rawValue,
            number: "1.3.2",
            rawLine: "Definition 1.3. 2. OCR text",
            normalizedLine: "Definition 1.3.2. OCR text",
            confidence: 0.9,
            region: region
        )

        let indexed = try XCTUnwrap(candidate.indexedReference(pageIndex: 4))

        XCTAssertEqual(indexed.contentOrigin, .ocrCandidate)
        XCTAssertEqual(indexed.evidence?.effectiveSource, .visionOCR)
        XCTAssertEqual(indexed.evidence?.matchedRegion, region)
        XCTAssertEqual(indexed.groundingBody, "")
    }

    func testOCRRegionResolverAcceptsOnlyValidNormalizedBoxes() throws {
        let image = NSImage(size: NSSize(width: 10, height: 10))
        image.lockFocus()
        NSColor.white.setFill()
        NSRect(x: 0, y: 0, width: 10, height: 10).fill()
        image.unlockFocus()
        let page = try XCTUnwrap(PDFPage(image: image))
        let valid = NormalizedRect(x: 0.1, y: 0.2, width: 0.3, height: 0.04)
        let evidence = ReferenceEvidence(
            status: .uncertain,
            sourceExcerpt: "Theorem 1.1",
            matchedText: "Theorem 1.1",
            occurrenceCount: 1,
            startOffset: 0,
            endOffset: 11,
            source: .visionOCR,
            matchedRegion: valid
        )
        let invalid = ReferenceEvidence(
            status: .uncertain,
            sourceExcerpt: "Theorem 1.1",
            matchedText: "Theorem 1.1",
            occurrenceCount: 1,
            startOffset: 0,
            endOffset: 11,
            source: .visionOCR,
            matchedRegion: NormalizedRect(x: 0.9, y: 0.2, width: 0.2, height: 0.04)
        )

        XCTAssertEqual(ReferenceEvidenceRegionResolver.exactRegion(for: evidence, on: page), valid)
        XCTAssertNil(ReferenceEvidenceRegionResolver.exactRegion(for: invalid, on: page))
    }
}

final class DocumentBlockExtractorTests: XCTestCase {
    func testBuildsBlockFromIndexedReference() {
        let indexed = IndexedReference(
            reference: DetectedReference(kind: .equation, number: "9.9"),
            formattedBody: "$$a=b$$",
            pageIndex: 7,
            name: "Pythagoras"
        )

        let block = DocumentBlockExtractor.block(from: indexed)

        XCTAssertEqual(block.reference.number, "9.9")
        XCTAssertEqual(block.formattedBody, "$$a=b$$")
        XCTAssertEqual(block.pageIndex, 7)
        XCTAssertEqual(block.name, "Pythagoras")
        XCTAssertEqual(indexed.documentBlock.name, "Pythagoras")
    }
}

final class ReferencePreviewPresentationTests: XCTestCase {
    func testHeadingIsKindNumberAndParentheticalName() {
        let block = DocumentBlock(
            reference: DetectedReference(kind: .theorem, number: "3.2"),
            formattedBody: "Every open cover has a finite subcover.",
            pageIndex: 40,
            name: "Compactness"
        )

        let model = ReferencePreviewPresentation.model(for: block)

        XCTAssertEqual(model.heading, "Theorem 3.2 (Compactness)")
        XCTAssertEqual(model.body, .statement("Every open cover has a finite subcover."))
    }

    func testHeadingOmitsABlankName() {
        let block = DocumentBlock(
            reference: DetectedReference(kind: .lemma, number: "1.1"),
            formattedBody: "A lemma.",
            pageIndex: 0,
            name: "   "
        )

        XCTAssertEqual(ReferencePreviewPresentation.heading(for: block), "Lemma 1.1")
    }

    func testEquationHeadingIsTheParentheticalNumber() {
        let block = DocumentBlock(
            reference: DetectedReference(kind: .equation, number: "1.4"),
            formattedBody: "$$x + y = z$$",
            pageIndex: 2
        )

        let model = ReferencePreviewPresentation.model(for: block)

        XCTAssertEqual(model.heading, "(1.4)")
        XCTAssertEqual(model.body, .statement("$$x + y = z$$"))
    }

    func testModelAndCleanedTextAreTheSameStatementBody() {
        let origins: [ReferenceContentOrigin] = [.modelTranscription, .sourceFallback, .ocrCandidate]
        for origin in origins {
            let block = DocumentBlock(
                reference: DetectedReference(kind: .definition, number: "2"),
                formattedBody: "A clean statement.",
                pageIndex: 1,
                contentOrigin: origin
            )
            XCTAssertEqual(
                ReferencePreviewPresentation.body(for: block),
                .statement("A clean statement."),
                "origin \(origin) must not introduce a second preview mode"
            )
        }
    }

    func testFigureHeadingStaysKindAndNumberAndCaptionSitsInTheBody() {
        let block = DocumentBlock(
            reference: DetectedReference(kind: .figure, number: "3"),
            formattedBody: "Scaling learned interatomic potentials",
            pageIndex: 4,
            name: "Scaling learned interatomic potentials"
        )

        let model = ReferencePreviewPresentation.model(for: block)

        XCTAssertEqual(model.heading, "Figure 3")
        XCTAssertEqual(model.body, .figure(caption: "Scaling learned interatomic potentials"))
    }

    func testFigureCaptionFallsBackToTheNameAndCanBeAbsent() {
        let named = DocumentBlock(
            reference: DetectedReference(kind: .figure, number: "2"),
            formattedBody: "  ",
            pageIndex: 1,
            name: "A contour"
        )
        let blank = DocumentBlock(
            reference: DetectedReference(kind: .figure, number: "2"),
            formattedBody: " ",
            pageIndex: 1,
            name: " "
        )

        XCTAssertEqual(ReferencePreviewPresentation.body(for: named), .figure(caption: "A contour"))
        XCTAssertEqual(ReferencePreviewPresentation.body(for: blank), .figure(caption: nil))
    }

    func testHeadingOmitsANameThatEqualsDisplayName() {
        let proposition = DocumentBlock(
            reference: DetectedReference(kind: .proposition, number: "2.5.1"),
            formattedBody: "A path.",
            pageIndex: 4,
            name: "Proposition 2.5.1"
        )
        XCTAssertEqual(ReferencePreviewPresentation.heading(for: proposition), "Proposition 2.5.1")

        let lowercased = DocumentBlock(
            reference: DetectedReference(kind: .proposition, number: "2.5.1"),
            formattedBody: "A path.",
            pageIndex: 4,
            name: "proposition 2.5.1"
        )
        XCTAssertEqual(ReferencePreviewPresentation.heading(for: lowercased), "Proposition 2.5.1")

        let abbreviated = DocumentBlock(
            reference: DetectedReference(kind: .proposition, number: "2.5.1"),
            formattedBody: "A path.",
            pageIndex: 4,
            name: "Prop. 2.5.1"
        )
        XCTAssertEqual(ReferencePreviewPresentation.heading(for: abbreviated), "Proposition 2.5.1")

        // displayName for an equation is "(1.4)", so "Equation 1.4" is kind+number
        // without being equal to that string.
        let equation = DocumentBlock(
            reference: DetectedReference(kind: .equation, number: "1.4"),
            formattedBody: "$$x = y$$",
            pageIndex: 0,
            name: "Equation 1.4"
        )
        XCTAssertEqual(ReferencePreviewPresentation.heading(for: equation), "(1.4)")
    }

    func testBodyContainingBackslashNRendersAsANewline() {
        // "\\n" in this source is the two-character escape, not a newline.
        let raw = "Let $\\gamma$ be a path.\\nMoreover, if $a$ holds."
        XCTAssertFalse(raw.contains("\n"))
        XCTAssertTrue(raw.contains("\\n"))

        let block = DocumentBlock(
            reference: DetectedReference(kind: .proposition, number: "2.5.1"),
            formattedBody: raw,
            pageIndex: 4,
            name: "Proposition 2.5.1"
        )
        guard case .statement(let text) = ReferencePreviewPresentation.body(for: block) else {
            return XCTFail("Expected a statement body")
        }

        XCTAssertFalse(text.contains("\\n"))
        XCTAssertTrue(text.contains("\n"))
        let lines = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        XCTAssertEqual(lines, [
            "Let $\\gamma$ be a path.",
            "Moreover, if $a$ holds.",
        ])
    }

    func testJSONEscapesDoNotEatLaTeXCommands() {
        let raw = "Let $\\nu$ and $\\tau$ with $\\theta \\to 0$ and $\\text{if}$.\\nThen $\\neq$ and say \\\"hi\\\" a\\tb."
        let text = ReferencePreviewPresentation.statementText(from: raw)

        XCTAssertTrue(text.contains("\\nu"))
        XCTAssertTrue(text.contains("\\tau"))
        XCTAssertTrue(text.contains("\\theta"))
        XCTAssertTrue(text.contains("\\to"))
        XCTAssertTrue(text.contains("\\text"))
        XCTAssertTrue(text.contains("\\neq"))
        XCTAssertTrue(text.contains("\nThen"))
        XCTAssertFalse(text.contains("\\nThen"))
        XCTAssertTrue(text.contains("\"hi\""))
        XCTAssertTrue(text.contains("a\tb"))
        XCTAssertFalse(text.contains("\\tb"))
    }

    func testEscapedBreakDoesNotMonospaceTheRestOfTheStatement() {
        let raw = "such that $\\gamma(t) = |\\gamma(t)|e^{2\\pi i a(t)}\\nMoreover, if $a$ and $b$ are two such functions. `still prose`"
        let text = ReferencePreviewPresentation.statementText(from: raw)

        XCTAssertFalse(text.contains("`"))
        XCTAssertFalse(text.contains("\\n"))

        let segments = MessageContentParser.parse(text)
        XCTAssertFalse(segments.contains { segment in
            if case .code = segment { return true }
            return false
        })

        let math = segments.compactMap { segment -> String? in
            switch segment {
            case .inlineMath(let latex), .displayMath(let latex):
                return latex
            default:
                return nil
            }
        }
        XCTAssertTrue(math.contains { $0.contains("\\pi") })
        XCTAssertFalse(math.contains { $0.contains("Moreover") || $0.contains("still prose") })
        XCTAssertTrue(segments.contains { segment in
            if case .text(let value) = segment { return value.contains("Moreover") }
            return false
        })
    }

    /// JERRY-134 at the render layer: the unescaped break is a paragraph, and
    /// the strings handed to `Text` no longer contain the formula source.
    func testUnescapedPropositionDoesNotPaintRawTeX() {
        let raw = "such that $\\gamma(t) = |\\gamma(t)|e^{2\\pi i a(t)}\\nMoreover, if $a$ and $b$ are two such functions."
        let text = ReferencePreviewPresentation.statementText(from: raw)

        XCTAssertTrue(text.contains("\n"))
        XCTAssertFalse(text.contains("\\n"))
        XCTAssertTrue(text.contains("\\pi"))

        let dump = ReferenceMathRendering.plainTextDump(of: text)
        XCTAssertTrue(dump.contains("Moreover"))
        XCTAssertFalse(dump.contains("\\"))
        XCTAssertFalse(dump.contains("$"))
        XCTAssertTrue(ReferenceMathRendering.mathSources(of: text).contains { $0.contains("\\pi") })
    }

    func testReferenceCardTypesetsASuperscriptAndAnArrow() {
        let arrow = "let f : X →Y be a map"
        XCTAssertEqual(ReferenceCardMath.typeset(arrow), "let $f : X \\to Y$ be a map")

        let inverse = "its preimage f\u{2212}1(U) is open"
        XCTAssertEqual(ReferenceCardMath.typeset(inverse), "its preimage $f^{-1}(U)$ is open")

        let superscript = "the value x\u{00B2} stays finite"
        XCTAssertEqual(ReferenceCardMath.typeset(superscript), "the value $x^{2}$ stays finite")

        let attached = "f\u{207B}\u{00B9}(U)"
        XCTAssertEqual(ReferenceCardMath.typeset(attached), "$f^{-1}(U)$")

        XCTAssertEqual(ReferenceCardMath.typeset("a well-known path"), "a well-known path")
        XCTAssertEqual(ReferenceCardMath.typeset("xf\u{2212}1(U)"), "xf\u{2212}1(U)")
    }

    func testReferenceCardLeavesDelimitedMathAlone() {
        let raw = "Let $\\gamma\\colon [0,1] \\to \\mathbb{C}$ be a path."
        XCTAssertEqual(ReferenceCardMath.typeset(raw), raw)
        XCTAssertEqual(ReferenceCardMath.typeset(ReferenceCardMath.typeset(raw)), raw)
    }

    /// `\notin`, `\backslash`, `\rightarrow`, `\neq` and `\to` survive both a
    /// correct JSON string and the controls `JSONDecoder` leaves behind.
    func testLaTeXCommandsRoundTripThroughTheStatementPipeline() throws {
        let encoded = #"{"body":"$z_0 \\notin U$, $f : U \\backslash \\{z_0\\} \\rightarrow \\mathbb{C}$, $\\neq$, $\\to$"}"#
        struct Box: Decodable { let body: String }
        let decoded = try JSONDecoder().decode(Box.self, from: Data(encoded.utf8))
        let literal = ReferencePreviewPresentation.statementText(from: decoded.body)
        assertCommandsIntact(literal)

        let eaten = ReferencePreviewPresentation.riemannEatenBody
            + " Take $a " + "\n" + "eq 0$."
        let restored = ReferencePreviewPresentation.statementText(from: eaten)
        XCTAssertTrue(restored.contains("\\notin"), restored)
        XCTAssertTrue(restored.contains("\\backslash"), restored)
        XCTAssertTrue(restored.contains("\\rightarrow"), restored)
        XCTAssertTrue(restored.contains("\\neq"), restored)
        XCTAssertFalse(restored.contains("\u{8}"))
        XCTAssertFalse(restored.contains("\u{c}"))
        XCTAssertFalse(ReferencePreviewPresentation.prefersPageCrop(restored))

        let segments = MessageContentParser.parse(restored)
        let prose = segments.compactMap { segment -> String? in
            if case .text(let value) = segment { return value }
            return nil
        }.joined(separator: " ")
        XCTAssertTrue(prose.contains("suppose"), prose)
        XCTAssertTrue(prose.contains("holomorphic"), prose)
        let math = segments.compactMap { segment -> String? in
            switch segment {
            case .inlineMath(let latex), .displayMath(let latex): return latex
            default: return nil
            }
        }
        XCTAssertTrue(math.contains { $0.contains("\\notin") })
        XCTAssertTrue(math.contains { $0.contains("\\backslash") && $0.contains("\\rightarrow") })
        XCTAssertFalse(math.contains { $0.contains("suppose") || $0.contains("holomorphic") })

        let corollary = ReferencePreviewPresentation.statementText(from: ReferencePreviewPresentation.corollaryEatenBody)
        XCTAssertTrue(corollary.contains("\\frac"))
        XCTAssertTrue(corollary.contains("\\oint"))
        XCTAssertTrue(corollary.contains("^{(n)}"))
        XCTAssertFalse(corollary.contains("\u{c}"))
        XCTAssertFalse(
            ReferencePreviewPresentation.prefersPageCrop(corollary),
            "clean corollary should stay text"
        )
        XCTAssertTrue(MessageContentParser.parse(corollary).contains { segment in
            if case .text(let value) = segment { return value.contains("for any") }
            return false
        })
    }

    /// A newline before prose, and a tab before a word, stay whitespace.
    /// A one-letter remainder such as a tab before "o" is not rewritten as `\to`.
    func testRealNewlineAndTabAreNotTurnedIntoCommands() {
        let paragraph = "Let $a$ hold.\nMoreover, the path is closed.\tThen $b$ holds."
        let text = ReferencePreviewPresentation.statementText(from: paragraph)
        XCTAssertTrue(text.contains("\nMoreover"), text)
        XCTAssertTrue(text.contains("\tThen"), text)
        XCTAssertFalse(text.contains("\\Moreover"), text)
        XCTAssertFalse(text.contains("\\Then"), text)
        XCTAssertFalse(ReferencePreviewPresentation.prefersPageCrop(text), text)

        let tabBeforeO = ReferencePreviewPresentation.statementText(from: "Take $t" + "\t" + "o 1$.")
        XCTAssertTrue(tabBeforeO.contains("\t"), tabBeforeO)
        XCTAssertFalse(tabBeforeO.contains("\\to"), tabBeforeO)
    }

    /// Not trustworthy: a control other than newline or tab, an unclosed `$`,
    /// a space-free math run of 24 or more characters, an unknown letter
    /// command, or unbalanced braces in a math span. The restored theorem
    /// fails none of these and stays text. The mangled run still has a
    /// backspace, so the card crops the page.
    func testNotTrustworthyRuleKeepsCleanTextAndCropsTheBrokenStatement() {
        let clean = ReferencePreviewPresentation.statementText(from: ReferencePreviewPresentation.riemannEatenBody)
        XCTAssertFalse(ReferencePreviewPresentation.prefersPageCrop(clean), clean)
        XCTAssertTrue(clean.contains("\\notin"), clean)
        XCTAssertTrue(clean.contains("suppose"), clean)

        let broken = ReferencePreviewPresentation.statementText(
            from: "Suppose that $z_0 " + "\u{8}" + "otin Uandsupposethatf:Uackslashz0ightarrowCisholomorphic.$"
        )
        XCTAssertTrue(ReferencePreviewPresentation.prefersPageCrop(broken), broken)
    }

    func testMangledStatementPrefersThePageCrop() {
        let mangled = "Suppose that $z_0 " + "\u{8}" + "otin Uandsupposethatf:Uackslashz0ightarrowCisholomorphic.Thenz0isaremovablesingularity$"
        let text = ReferencePreviewPresentation.statementText(from: mangled)
        XCTAssertTrue(ReferencePreviewPresentation.prefersPageCrop(text), "mangled run should crop")

        // `\n` that does not continue a known command is a paragraph break, so the
        // unknown name cannot start with n or t. `\fakecommand` is still a command.
        let unknown = ReferencePreviewPresentation.statementText(from: "Let $f$ satisfy $\\fakecommand{x}=1$.")
        XCTAssertTrue(ReferencePreviewPresentation.prefersPageCrop(unknown), "unknown command should crop")

        let unbalanced = ReferencePreviewPresentation.statementText(from: "Let $f(z) = z^2 + 1 be entire.")
        XCTAssertTrue(ReferencePreviewPresentation.prefersPageCrop(unbalanced), "unclosed delimiter should crop")

        XCTAssertFalse(ReferencePreviewPresentation.prefersPageCrop("A continuous function on a compact set is bounded."))
    }

    func testExistingStatementFixturesStayText() {
        let proposition = "Let $\\gamma\\colon [0,1] \\to \\mathbb{C}\\setminus\\{0\\}$ be a path. Then there is a continuous function $a\\colon [0,1] \\to \\mathbb{R}$ such that $\\gamma(t) = |\\gamma(t)|e^{2\\pi i a(t)}\\nMoreover, if $a$ and $b$ are two such functions, then there exists $n \\in \\mathbb{Z}$ such that $a(t) = b(t) + n$."
        let propositionText = ReferencePreviewPresentation.statementText(from: proposition)
        XCTAssertFalse(ReferencePreviewPresentation.prefersPageCrop(propositionText), propositionText)

        let lemma = "Let \\gamma be a closed curve where $n$ satisfies \\frac{1}{2\\pi i}.\\n\\begin{align}\\n\\label{eq:sample}\\n\\int_{\\gamma} \\frac{dz}{z} &= 2\\pi i\\n\\end{align}\\nMoreover **$\\frac{1}{2}$** is the residue."
        let lemmaText = ReferencePreviewPresentation.statementText(from: lemma)
        XCTAssertFalse(ReferencePreviewPresentation.prefersPageCrop(lemmaText), lemmaText)
        XCTAssertTrue(lemmaText.contains("\\begin{align}"))
        XCTAssertTrue(lemmaText.contains("Moreover"))
    }

    func testCardGrowsUntilSixtyPercentOfTheWindow() {
        XCTAssertEqual(ReferencePreviewMetrics.cardWidth, 320)
        XCTAssertEqual(ReferencePreviewMetrics.cappedHeight(windowHeight: 800, contentHeight: 200), 200)
        XCTAssertEqual(ReferencePreviewMetrics.cappedHeight(windowHeight: 800, contentHeight: 900), 480)
        XCTAssertFalse(ReferencePreviewMetrics.overflows(windowHeight: 800, contentHeight: 200))
        XCTAssertTrue(ReferencePreviewMetrics.overflows(windowHeight: 800, contentHeight: 900))
    }

    private func assertCommandsIntact(_ text: String) {
        XCTAssertTrue(text.contains("\\notin"), text)
        XCTAssertTrue(text.contains("\\backslash"), text)
        XCTAssertTrue(text.contains("\\rightarrow"), text)
        XCTAssertTrue(text.contains("\\neq"), text)
        XCTAssertTrue(text.contains("\\to"), text)
        XCTAssertFalse(text.contains("\u{8}"), text)
    }
}

/// The page crop the card shows. A bottom-left PDF crop drawn into a
/// top-left bitmap puts the last line on top; this locks the other way.
final class PDFRegionRendererTests: XCTestCase {
    func testCropKeepsTheFirstLineAtTheTop() throws {
        let pageRect = CGRect(x: 0, y: 0, width: 420, height: 560)
        let first = "FIRST LINE AT THE TOP OF THE PAGE"
        let last = "last"
        let page = try Self.page(pageRect, first: first, last: last)
        let rendered = try XCTUnwrap(
            PDFRegionRenderer.render(
                page: page,
                bounds: NormalizedRect(x: 0, y: 0, width: 1, height: 1),
                scale: 2
            )
        )
        let reference = try XCTUnwrap(Self.unflippedReference(pageRect, first: first, last: last))

        let cropRows = Self.inkRows(of: rendered)
        let referenceRows = Self.inkRows(of: reference)
        let cropPeak = Self.peakFraction(cropRows)
        let referencePeak = Self.peakFraction(referenceRows)

        XCTAssertLessThan(cropPeak, 0.4, "first line is at row fraction \(cropPeak)")
        XCTAssertLessThan(referencePeak, 0.4, "unflipped reference peaks at \(referencePeak)")
        XCTAssertLessThan(
            abs(cropPeak - referencePeak),
            abs(cropPeak - (1 - referencePeak)),
            "crop peak \(cropPeak) matches the flipped reference, not the upright one at \(referencePeak)"
        )
    }

    /// The card already shows the title. The crop starts under that line, and
    /// neither edge may cut a line box in half.
    func testStatementCropDoesNotCutATextLine() throws {
        let heading = CGRect(x: 72, y: 700, width: 400, height: 18)
        let body1 = CGRect(x: 72, y: 678, width: 420, height: 18)
        let body2 = CGRect(x: 72, y: 656, width: 380, height: 18)
        let below = CGRect(x: 72, y: 620, width: 200, height: 18)
        let lines = [heading, body1, body2, below]
        let page = CGRect(x: 0, y: 0, width: 612, height: 792)
        // The old pad reached up through the heading and down through body2.
        let proposed = CGRect(x: 60, y: 660, width: 450, height: 55)

        let underHeading = ReferenceEvidenceRegionResolver.statementCrop(
            proposed: proposed,
            lines: lines,
            headingLine: heading,
            pageBounds: page
        )
        assertWholeLines(underHeading, lines)
        XCTAssertFalse(underHeading.intersects(heading), "heading line is still in the crop \(underHeading)")
        XCTAssertTrue(underHeading.contains(body1))
        XCTAssertTrue(underHeading.contains(body2))
        XCTAssertFalse(underHeading.intersects(below))
        XCTAssertLessThan(underHeading.maxY, heading.minY)

        let snapped = ReferenceEvidenceRegionResolver.statementCrop(
            proposed: proposed,
            lines: lines,
            headingLine: nil,
            pageBounds: page
        )
        assertWholeLines(snapped, lines)
        XCTAssertTrue(snapped.contains(heading))
        XCTAssertTrue(snapped.contains(body2))
        XCTAssertFalse(snapped.intersects(below))
    }

    func testRenderedStatementCropStartsBelowTheHeading() throws {
        let pageRect = CGRect(x: 0, y: 0, width: 612, height: 792)
        let page = try Self.theoremPage(pageRect)
        let text = try XCTUnwrap(page.string) as NSString
        let headingRange = text.range(of: "Theorem 3.5.21")
        let bodyRange = text.range(of: "Suppose")
        XCTAssertNotEqual(headingRange.location, NSNotFound)
        XCTAssertNotEqual(bodyRange.location, NSNotFound)
        let evidence = ReferenceEvidence(
            status: .supported,
            sourceExcerpt: text.substring(from: bodyRange.location),
            matchedText: text.substring(with: headingRange),
            occurrenceCount: 1,
            startOffset: bodyRange.location,
            endOffset: text.length,
            matchStartOffset: headingRange.location,
            matchEndOffset: NSMaxRange(headingRange)
        )
        let band = try XCTUnwrap(ReferenceEvidenceRegionResolver.statementBand(for: evidence, on: page))
        let crop = band.cgRect(in: pageRect)
        let lines = ReferenceEvidenceRegionResolver.textLineBoxes(on: page)
        XCTAssertGreaterThan(lines.count, 1, "the text layer should expose more than one line")
        assertWholeLines(crop, lines)

        guard let headingBox = lines.max(by: { $0.maxY < $1.maxY }),
              let bodyBox = lines.filter({ $0.maxY < headingBox.minY }).max(by: { $0.maxY < $1.maxY }) else {
            return XCTFail("missing heading or body line")
        }
        XCTAssertFalse(
            crop.intersection(headingBox).height > 0.5,
            "crop \(crop) still meets the heading line \(headingBox)"
        )
        XCTAssertTrue(
            crop.insetBy(dx: -0.4, dy: -0.4).contains(bodyBox),
            "body line \(bodyBox) is not inside \(crop)"
        )
    }

    private func assertWholeLines(_ crop: CGRect, _ lines: [CGRect], file: StaticString = #filePath, line: UInt = #line) {
        for box in lines {
            let hit = crop.intersection(box)
            let misses = hit.isNull || hit.isEmpty || hit.width < 0.4 || hit.height < 0.4
            if misses { continue }
            XCTAssertTrue(
                crop.insetBy(dx: -0.4, dy: -0.4).contains(box),
                "crop \(crop) cuts line \(box)",
                file: file,
                line: line
            )
        }
    }

    private static func theoremPage(_ pageRect: CGRect) throws -> PDFPage {
        let data = NSMutableData()
        var media = pageRect
        guard let consumer = CGDataConsumer(data: data as CFMutableData),
              let context = CGContext(consumer: consumer, mediaBox: &media, nil) else {
            throw XCTSkip("could not open a PDF context")
        }
        context.beginPDFPage(nil)
        context.setFillColor(gray: 1, alpha: 1)
        context.fill(pageRect)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        let font = NSFont(name: "Times-Roman", size: 16) ?? NSFont.systemFont(ofSize: 16)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.black,
        ]
        let drawn = [
            "Theorem 3.5.21 (Riemann's removable singularity theorem)",
            "Suppose that U is an open subset of C and z0 is outside U,",
            "and f is holomorphic. Then z0 is a removable singularity of f.",
        ]
        var baseline = pageRect.height - 96
        for line in drawn {
            NSString(string: line).draw(at: NSPoint(x: 72, y: baseline), withAttributes: attributes)
            baseline -= 22
        }
        NSGraphicsContext.restoreGraphicsState()
        context.endPDFPage()
        context.closePDF()
        return try XCTUnwrap(PDFDocument(data: data as Data)?.page(at: 0))
    }

    private static func page(_ pageRect: CGRect, first: String, last: String) throws -> PDFPage {
        let data = NSMutableData()
        var media = pageRect
        guard let consumer = CGDataConsumer(data: data as CFMutableData),
              let context = CGContext(consumer: consumer, mediaBox: &media, nil) else {
            throw XCTSkip("could not open a PDF context")
        }
        context.beginPDFPage(nil)
        context.setFillColor(gray: 1, alpha: 1)
        context.fill(pageRect)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        let font = NSFont.systemFont(ofSize: 18)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.black,
        ]
        // PDF y grows up, so the first line is near the top of the page.
        NSString(string: first).draw(at: NSPoint(x: 24, y: pageRect.height - 48), withAttributes: attributes)
        NSString(string: last).draw(at: NSPoint(x: 24, y: 28), withAttributes: attributes)
        NSGraphicsContext.restoreGraphicsState()
        context.endPDFPage()
        context.closePDF()
        return try XCTUnwrap(PDFDocument(data: data as Data)?.page(at: 0))
    }

    /// The same two lines, drawn with the first line at the top of the bitmap.
    private static func unflippedReference(_ pageRect: CGRect, first: String, last: String) -> CGImage? {
        let image = NSImage(size: pageRect.size)
        image.lockFocusFlipped(true)
        NSColor.white.setFill()
        NSRect(origin: .zero, size: pageRect.size).fill()
        let font = NSFont.systemFont(ofSize: 18)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.black,
        ]
        NSString(string: first).draw(at: NSPoint(x: 24, y: 28), withAttributes: attributes)
        NSString(string: last).draw(
            at: NSPoint(x: 24, y: pageRect.height - 48),
            withAttributes: attributes
        )
        image.unlockFocus()
        var proposed = NSRect(origin: .zero, size: pageRect.size)
        return image.cgImage(forProposedRect: &proposed, context: nil, hints: nil)
    }

    /// Ink per row, top of the displayed image first. `colorAt` is top-down.
    private static func inkRows(of image: CGImage) -> [Int] {
        let rep = NSBitmapImageRep(cgImage: image)
        var rows = Array(repeating: 0, count: rep.pixelsHigh)
        let step = 2
        for y in 0..<rep.pixelsHigh {
            var x = 0
            while x < rep.pixelsWide {
                if let color = rep.colorAt(x: x, y: y) {
                    let brightness = (color.redComponent + color.greenComponent + color.blueComponent) / 3
                    if color.alphaComponent > 0.3 && brightness < 0.45 {
                        rows[y] += 1
                    }
                }
                x += step
            }
        }
        return rows
    }

    /// Fraction down the image of the row with the most ink. The long first
    /// line is that row when the crop is upright.
    private static func peakFraction(_ rows: [Int]) -> Double {
        guard let peak = rows.enumerated().max(by: { $0.element < $1.element }),
              rows.count > 1 else { return 1 }
        return Double(peak.offset) / Double(rows.count - 1)
    }

    func testDarkCropDropsTheWhitePage() {
        let image = NSImage(size: NSSize(width: 8, height: 4))
        image.lockFocus()
        NSColor.white.setFill()
        NSRect(x: 0, y: 0, width: 8, height: 4).fill()
        NSColor.black.setFill()
        NSRect(x: 3, y: 0, width: 2, height: 4).fill()
        image.unlockFocus()

        let lifted = StatementCropInk.dark(image)
        guard let tiff = lifted.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else {
            return XCTFail("dark crop has no bitmap")
        }
        let paper = rep.colorAt(x: 0, y: 0)
        var inkAlpha: CGFloat = 0
        for x in 0..<rep.pixelsWide {
            inkAlpha = max(inkAlpha, rep.colorAt(x: x, y: 0)?.alphaComponent ?? 0)
        }
        XCTAssertLessThan(paper?.alphaComponent ?? 1, 0.05)
        XCTAssertGreaterThan(inkAlpha, 0.8)
    }
}

private struct AnchoredPassageIndexStub: DocumentIndexProtocol {
    let record: DocumentPassage

    func passages(matching query: String, limit: Int, excludingPage: Int?) -> [String] {
        limit > 0 ? [record.text] : []
    }

    func passageRecords(
        matching query: String,
        queryVector: [Float]?,
        limit: Int,
        excludingPage: Int?
    ) -> [DocumentPassage] {
        limit > 0 ? [record] : []
    }
}
