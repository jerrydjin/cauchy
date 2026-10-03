import AppKit
import PDFKit
import XCTest
@testable import Cauchy

final class HighlightExportServiceTests: XCTestCase {
    private func writeSearchablePDF(to url: URL) throws {
        let data = NSMutableData()
        guard let consumer = CGDataConsumer(data: data as CFMutableData) else {
            return XCTFail("Could not create PDF consumer")
        }
        var mediaBox = CGRect(x: 0, y: 0, width: 612, height: 792)
        guard let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            return XCTFail("Could not create PDF context")
        }
        context.beginPDFPage(nil)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        NSString(string: "Theorem 1.1. A grounded statement.\nBy Theorem 1.1 the claim follows.")
            .draw(at: NSPoint(x: 72, y: 650), withAttributes: [.font: NSFont.systemFont(ofSize: 14)])
        NSGraphicsContext.restoreGraphicsState()
        context.endPDFPage()
        context.closePDF()
        try (data as Data).write(to: url)
        XCTAssertTrue(PDFDocument(url: url)?.page(at: 0)?.string?.contains("Theorem 1.1") == true)
    }

    private func highlight(
        page: Int,
        text: String,
        title: String? = nil,
        note: String? = nil,
        colour: HighlightColor = .yellow,
        messages: [ThreadMessage] = [],
        createdAt: Date = Date(timeIntervalSince1970: 0)
    ) -> Highlight {
        Highlight(
            pageIndex: page,
            selectedText: text,
            color: colour,
            title: title,
            note: note,
            messages: messages,
            createdAt: createdAt
        )
    }

    func testReadingOrderSortsByPageThenCreation() {
        let late = highlight(page: 1, text: "b", createdAt: Date(timeIntervalSince1970: 200))
        let early = highlight(page: 1, text: "a", createdAt: Date(timeIntervalSince1970: 100))
        let laterPage = highlight(page: 5, text: "c", createdAt: Date(timeIntervalSince1970: 0))

        let ordered = HighlightExportService.readingOrder([laterPage, late, early])

        XCTAssertEqual(ordered.map(\.selectedText), ["a", "b", "c"])
    }

    func testMarkdownIncludesPassageNoteAndConversation() {
        let markdown = HighlightExportService.markdown(
            documentTitle: "Attention Is All You Need",
            highlights: [
                highlight(
                    page: 2,
                    text: "Scaled dot-product attention",
                    title: "Attention scaling",
                    note: "check the 1/sqrt(d) factor",
                    messages: [
                        ThreadMessage(role: .user, content: "Why divide by sqrt(d)?"),
                        ThreadMessage(role: .assistant, content: "To keep the dot products small."),
                    ]
                )
            ]
        )

        XCTAssertTrue(markdown.hasPrefix("# Attention Is All You Need"))
        XCTAssertTrue(markdown.contains("## Attention scaling"))
        XCTAssertTrue(markdown.contains("**Page 3**"))
        XCTAssertTrue(markdown.contains("> Scaled dot-product attention"))
        XCTAssertTrue(markdown.contains("**Note:** check the 1/sqrt(d) factor"))
        XCTAssertTrue(markdown.contains("**Q:** Why divide by sqrt(d)?"))
        XCTAssertTrue(markdown.contains("To keep the dot products small."))
    }

    func testMarkdownPreservesAnswerEvidenceBoundary() {
        let markdown = HighlightExportService.markdown(
            documentTitle: "Doc",
            highlights: [highlight(
                page: 2,
                text: "A passage",
                messages: [ThreadMessage(
                    role: .assistant,
                    content: "A grounded answer.",
                    answerEvidence: AnswerEvidence(
                        basis: .pdf,
                        sourcePages: [3, 7],
                        referencedStatementCount: 1,
                        retrievedPassageCount: 0,
                        providerID: "onDevice"
                    )
                )]
            )]
        )

        XCTAssertTrue(markdown.contains("Answer basis: Claims PDF basis"))
        XCTAssertTrue(markdown.contains("PDF sources supplied: pp. 3, 7"))
    }

    /// A passage spanning several lines has to stay inside one block quote —
    /// an unprefixed line silently ends the quote in every Markdown renderer.
    func testMultiLinePassageQuotesEveryLine() {
        let markdown = HighlightExportService.markdown(
            documentTitle: "Doc",
            highlights: [highlight(page: 0, text: "first line\nsecond line")]
        )

        XCTAssertTrue(markdown.contains("> first line\n> second line"))
    }

    func testMarkdownNamesANonDefaultColour() {
        let plain = HighlightExportService.markdown(
            documentTitle: "Doc",
            highlights: [highlight(page: 0, text: "x", colour: .yellow)]
        )
        let tinted = HighlightExportService.markdown(
            documentTitle: "Doc",
            highlights: [highlight(page: 0, text: "x", colour: .blue)]
        )

        XCTAssertFalse(plain.contains("Yellow"))
        XCTAssertTrue(tinted.contains("Blue"))
    }

    func testSingleThreadMarkdownStandsAlone() {
        let markdown = HighlightExportService.markdown(
            for: highlight(page: 0, text: "one passage", title: "Just this"),
            documentTitle: "Doc"
        )

        XCTAssertTrue(markdown.contains("# Doc"))
        XCTAssertTrue(markdown.contains("## Just this"))
        XCTAssertFalse(markdown.contains("---"))
    }

    func testReadingSessionRoundTripIncludesPDFProgressAndHighlights() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let source = root.appendingPathComponent("A Paper.pdf")
        try Data("test-pdf".utf8).write(to: source)
        let destination = root.appendingPathComponent("handoff.cauchyreading", isDirectory: true)

        var workspace = DocumentWorkspace(documentURL: source)
        workspace.primaryViewport.pageIndex = 37
        workspace.primaryViewport.scaleFactor = 1.4
        workspace.highlights = [highlight(page: 12, text: "portable passage")]

        try ReadingSessionPackageService.write(
            sourcePDF: source,
            destination: destination,
            workspace: workspace
        )
        // Simulate a package written before portable evidence existed.
        let manifestURL = destination.appendingPathComponent(ReadingSessionPackageService.manifestFilename)
        var legacyManifest = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: manifestURL)) as? [String: Any]
        )
        legacyManifest["formatVersion"] = 1
        legacyManifest.removeValue(forKey: "evidenceFilename")
        try JSONSerialization.data(withJSONObject: legacyManifest).write(to: manifestURL)
        let (package, packagedPDF) = try ReadingSessionPackageService.read(from: destination)

        XCTAssertEqual(package.formatVersion, 1)
        XCTAssertNil(package.evidenceFilename)
        XCTAssertEqual(package.documentFilename, "A Paper.pdf")
        XCTAssertEqual(package.workspace.primaryViewport.pageIndex, 37)
        XCTAssertEqual(package.workspace.primaryViewport.scaleFactor, 1.4)
        XCTAssertEqual(package.workspace.highlights.first?.selectedText, "portable passage")
        XCTAssertEqual(try Data(contentsOf: packagedPDF), Data("test-pdf".utf8))
        XCTAssertFalse(package.workspace.documentURL.path.contains(root.path))
    }

    @MainActor
    func testReadingSessionCarriesHashBoundReferenceEvidence() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let source = root.appendingPathComponent("evidence.pdf")
        try writeSearchablePDF(to: source)
        let document = try XCTUnwrap(PDFDocument(url: source))
        let page = try XCTUnwrap(document.page(at: 0))
        let text = try XCTUnwrap(page.string)
        let matches = ReferenceDetector.allReferences(in: text).filter {
            $0.reference == DetectedReference(kind: .theorem, number: "1.1")
        }
        XCTAssertGreaterThanOrEqual(matches.count, 2)
        let declaration = try XCTUnwrap(matches.first)
        let start = declaration.range.lowerBound.utf16Offset(in: text)
        let end = declaration.range.upperBound.utf16Offset(in: text)
        let evidence = ReferenceEvidence(
            status: .uncertain,
            sourceExcerpt: text,
            matchedText: String(text[declaration.range]),
            occurrenceCount: matches.count,
            startOffset: 0,
            endOffset: text.utf16.count,
            matchStartOffset: start,
            matchEndOffset: end
        )
        let reference = IndexedReference(
            reference: DetectedReference(kind: .theorem, number: "1.1"),
            formattedBody: "A grounded statement.",
            pageIndex: 0,
            evidence: evidence,
            contentOrigin: .sourceFallback
        )
        let fingerprint = try ReferenceIndexCacheStore.fingerprint(for: source)
        defer { ReferenceIndexCacheStore.removeCache(for: source) }
        try ReferenceIndexCacheStore.save(PersistedReferenceIndex(
            documentFingerprint: fingerprint,
            builtAt: Date(timeIntervalSince1970: 100),
            entries: [reference.reference.key: reference],
            builtWith: "on-device",
            failedPageIndices: []
        ))

        let destination = root.appendingPathComponent("portable.cauchyreading", isDirectory: true)
        try ReadingSessionPackageService.write(
            sourcePDF: source,
            destination: destination,
            workspace: DocumentWorkspace(documentURL: source)
        )
        let (package, packagedPDF) = try ReadingSessionPackageService.read(from: destination)
        let portable = try XCTUnwrap(ReadingSessionPackageService.readEvidence(
            from: destination,
            package: package,
            documentURL: packagedPDF
        ))
        XCTAssertEqual(package.formatVersion, 2)
        XCTAssertEqual(portable.documentFingerprint, fingerprint)
        XCTAssertEqual(portable.referenceIndex.builtWith, "on-device")
        XCTAssertEqual(portable.mentionGraph.records.first?.result.mentions.count, 1)

        ReferenceIndexCacheStore.removeCache(for: source)
        XCTAssertNil(try ReferenceIndexCacheStore.load(fingerprint: fingerprint))
        let persistence = DocumentPersistenceService(root: root.appendingPathComponent("library"))
        _ = try await persistence.importReadingSession(from: destination)
        XCTAssertEqual(try ReferenceIndexCacheStore.load(fingerprint: fingerprint)?.entries.count, 1)
        XCTAssertEqual(try ReferenceIndexCacheStore.loadGraph(fingerprint: fingerprint)?
            .records.first?.result.mentions.count, 1)

        // Evidence is bound to exact PDF bytes, not merely its filename.
        let handle = try FileHandle(forWritingTo: packagedPDF)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data("tampered".utf8))
        try handle.close()
        XCTAssertThrowsError(try ReadingSessionPackageService.readEvidence(
            from: destination,
            package: package,
            documentURL: packagedPDF
        ))
    }

    func testReadingSessionOmitsLocallyInvalidReferenceEvidence() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let source = root.appendingPathComponent("invalid-evidence.pdf")
        try writeSearchablePDF(to: source)
        let fingerprint = try ReferenceIndexCacheStore.fingerprint(for: source)
        defer { ReferenceIndexCacheStore.removeCache(for: source) }
        let reference = IndexedReference(
            reference: DetectedReference(kind: .theorem, number: "1.1"),
            formattedBody: "A grounded statement.",
            pageIndex: 0,
            evidence: ReferenceEvidence(
                status: .uncertain,
                sourceExcerpt: "This text does not occur in the PDF.",
                matchedText: "Theorem 1.1",
                occurrenceCount: 1,
                startOffset: 0,
                endOffset: 36,
                matchStartOffset: 0,
                matchEndOffset: 11
            ),
            contentOrigin: .sourceFallback
        )
        try ReferenceIndexCacheStore.save(PersistedReferenceIndex(
            documentFingerprint: fingerprint,
            builtAt: Date(timeIntervalSince1970: 100),
            entries: [reference.reference.key: reference],
            builtWith: "on-device",
            failedPageIndices: []
        ))

        let destination = root.appendingPathComponent("portable.cauchyreading", isDirectory: true)
        try ReadingSessionPackageService.write(
            sourcePDF: source,
            destination: destination,
            workspace: DocumentWorkspace(documentURL: source)
        )
        let (package, _) = try ReadingSessionPackageService.read(from: destination)

        XCTAssertNil(package.evidenceFilename)
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination
            .appendingPathComponent(ReadingSessionPackageService.evidenceFilename).path))
    }

    func testReadingSessionOmitsOCRCandidateEvidence() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let source = root.appendingPathComponent("ocr-evidence.pdf")
        try writeSearchablePDF(to: source)
        let fingerprint = try ReferenceIndexCacheStore.fingerprint(for: source)
        defer { ReferenceIndexCacheStore.removeCache(for: source) }
        let candidate = try XCTUnwrap(OCRReferenceCandidate(
            kind: ReferenceKind.theorem.rawValue,
            number: "1.1",
            rawLine: "Theorem 1.1. OCR transcript.",
            normalizedLine: "Theorem 1.1. OCR transcript.",
            confidence: 0.91,
            region: NormalizedRect(x: 0.1, y: 0.8, width: 0.5, height: 0.04)
        ).indexedReference(pageIndex: 0))
        try ReferenceIndexCacheStore.save(PersistedReferenceIndex(
            documentFingerprint: fingerprint,
            builtAt: Date(timeIntervalSince1970: 100),
            entries: [candidate.reference.key: candidate],
            builtWith: "Vision OCR candidates",
            failedPageIndices: []
        ))

        let destination = root.appendingPathComponent("portable.cauchyreading", isDirectory: true)
        try ReadingSessionPackageService.write(
            sourcePDF: source,
            destination: destination,
            workspace: DocumentWorkspace(documentURL: source)
        )
        let (package, _) = try ReadingSessionPackageService.read(from: destination)

        XCTAssertNil(package.evidenceFilename)
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination
            .appendingPathComponent(ReadingSessionPackageService.evidenceFilename).path))
    }
}
