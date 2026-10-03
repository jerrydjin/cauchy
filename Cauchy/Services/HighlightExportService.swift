import Foundation
import PDFKit

enum HighlightExportError: LocalizedError {
    case cannotOpenSource
    case cannotWriteCopy

    var errorDescription: String? {
        switch self {
        case .cannotOpenSource:
            "The PDF could not be reopened to write the copy."
        case .cannotWriteCopy:
            "The annotated copy could not be written."
        }
    }
}

/// Gets a reading session out of the app: highlights and their conversations as
/// Markdown, or the PDF itself with the highlights painted in so they survive
/// in Preview and for whoever the file is sent to.
enum HighlightExportService {
    // MARK: - Markdown

    /// Highlights in reading order — page order, then when they were made —
    /// rather than the panel's most-recently-touched order, because a document
    /// read start to finish is what the export is a record of.
    nonisolated static func readingOrder(_ highlights: [Highlight]) -> [Highlight] {
        highlights.sorted {
            $0.pageIndex == $1.pageIndex
                ? $0.createdAt < $1.createdAt
                : $0.pageIndex < $1.pageIndex
        }
    }

    nonisolated static func markdown(
        documentTitle: String,
        highlights: [Highlight],
        exportedAt: Date = Date()
    ) -> String {
        let ordered = readingOrder(highlights)
        var out = "# \(documentTitle)\n\n"

        let formatter = DateFormatter()
        formatter.dateStyle = .long
        formatter.timeStyle = .short
        let count = ordered.count == 1 ? "1 highlight" : "\(ordered.count) highlights"
        out += "*\(count) · exported from Cauchy on \(formatter.string(from: exportedAt))*\n"

        for highlight in ordered {
            out += "\n---\n\n"
            out += body(of: highlight, headingLevel: 2)
        }
        return out
    }

    /// One thread on its own, for "Copy as Markdown" on a single row.
    nonisolated static func markdown(for highlight: Highlight, documentTitle: String) -> String {
        "# \(documentTitle)\n\n" + body(of: highlight, headingLevel: 2)
    }

    nonisolated private static func body(of highlight: Highlight, headingLevel: Int) -> String {
        let hashes = String(repeating: "#", count: headingLevel)
        var out = "\(hashes) \(highlight.displayName)\n\n"
        out += "**Page \(highlight.pageIndex + 1)**"
        if highlight.color != .default {
            out += " · \(highlight.color.displayName)"
        }
        out += "\n\n"

        let passage = highlight.selectedText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !passage.isEmpty {
            out += blockQuote(passage) + "\n\n"
        }

        if let note = highlight.note?.trimmingCharacters(in: .whitespacesAndNewlines), !note.isEmpty {
            out += "**Note:** \(note)\n\n"
        }

        for message in highlight.messages {
            let content = message.content.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !content.isEmpty else { continue }
            switch message.role {
            case .user:
                out += "**Q:** \(content)\n\n"
            case .assistant:
                out += "\(content)\n\n"
                if let evidence = message.answerEvidence {
                    out += "*Answer basis: \(evidence.basis.label) · PDF sources supplied: \(evidence.sourcePagesLabel)*\n\n"
                    if let status = evidence.citationStatus {
                        out += "*Citation links: \(status.label). IDs identify source locations, not proof of claims.*\n\n"
                    }
                    if let anchors = evidence.sourceAnchors, !anchors.isEmpty {
                        out += "Supplied PDF locations (inputs, not verified claim citations):\n"
                        for anchor in anchors {
                            out += "- \(anchor.sourceID.map { "[\($0)] " } ?? "")\(anchor.label), p. \(anchor.pageIndex + 1)"
                            out += " (region \(anchor.region.x), \(anchor.region.y), \(anchor.region.width), \(anchor.region.height))\n"
                        }
                        out += "\n"
                    }
                }
            }
        }
        return out
    }

    /// Every line prefixed, so a passage that wrapped across several lines in
    /// the PDF stays one quote instead of breaking out of it half way down.
    nonisolated private static func blockQuote(_ text: String) -> String {
        text
            .components(separatedBy: .newlines)
            .map { $0.isEmpty ? ">" : "> \($0)" }
            .joined(separator: "\n")
    }

    // MARK: - Annotated PDF

    /// Writes a copy of the PDF with the highlights painted into it. Reopens
    /// the file rather than reusing the live `PDFDocument`, so the copy carries
    /// no selection state and the reader's own document is never touched.
    nonisolated static func writeAnnotatedPDF(
        source: URL,
        destination: URL,
        highlights: [Highlight]
    ) throws {
        guard let document = PDFDocument(url: source) else {
            throw HighlightExportError.cannotOpenSource
        }
        // No active highlight: in an exported copy every highlight is equal,
        // and the stronger active tint would read as a mistake.
        HighlightAnnotationService.sync(document: document, highlights: highlights, activeID: nil)
        guard document.write(to: destination) else {
            throw HighlightExportError.cannotWriteCopy
        }
    }
}

// MARK: - Portable reading session

enum ReadingSessionPackageError: LocalizedError {
    case invalidPackage
    case unsupportedVersion
    case cannotWritePackage

    var errorDescription: String? {
        switch self {
        case .invalidPackage:
            "This Cauchy reading session is incomplete or damaged."
        case .unsupportedVersion:
            "This reading session was created by a newer version of Cauchy."
        case .cannotWritePackage:
            "The reading session could not be written."
        }
    }
}

struct ReadingSessionPackage: Codable, Sendable {
    var formatVersion: Int
    var documentFilename: String
    var workspace: DocumentWorkspace
    /// Optional in v1 packages. When present, names a hash-bound reference
    /// index and citation graph that can be installed without rerunning AI.
    var evidenceFilename: String?

    init(
        formatVersion: Int,
        documentFilename: String,
        workspace: DocumentWorkspace,
        evidenceFilename: String? = nil
    ) {
        self.formatVersion = formatVersion
        self.documentFilename = documentFilename
        self.workspace = workspace
        self.evidenceFilename = evidenceFilename
    }
}

struct PortableReferenceEvidence: Codable, Sendable {
    static let schemaVersion = 1

    let schemaVersion: Int
    let documentFingerprint: String
    let referenceIndex: PersistedReferenceIndex
    let mentionGraph: ReferenceMentionGraph
}

/// A `.cauchyreading` package is deliberately ordinary files in a directory:
/// the original PDF plus a JSON snapshot of the page, zoom, highlights, and
/// conversations. It can travel through AirDrop or iCloud Drive without an
/// account or a Cauchy server, and a damaged manifest never touches the PDF.
enum ReadingSessionPackageService {
    static let filenameExtension = "cauchyreading"
    static let manifestFilename = "session.json"
    static let evidenceFilename = "evidence.json"
    static let currentFormatVersion = 2

    nonisolated static func write(
        sourcePDF: URL,
        destination: URL,
        workspace: DocumentWorkspace
    ) throws {
        let manager = FileManager.default
        let parent = destination.deletingLastPathComponent()
        let temporary = parent.appendingPathComponent(
            ".cauchy-reading-\(UUID().uuidString)",
            isDirectory: true
        )
        defer { try? manager.removeItem(at: temporary) }

        do {
            try manager.createDirectory(at: temporary, withIntermediateDirectories: false)

            let documentFilename = sourcePDF.lastPathComponent
            guard !documentFilename.isEmpty,
                  documentFilename.lowercased().hasSuffix(".pdf")
            else { throw ReadingSessionPackageError.invalidPackage }

            try manager.copyItem(
                at: sourcePDF,
                to: temporary.appendingPathComponent(documentFilename)
            )

            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            // Reading progress remains exportable if an optional local cache
            // is missing or damaged; never package unvalidated partial data.
            let portableEvidence = try? makePortableEvidence(for: sourcePDF)
            if let portableEvidence {
                try encoder.encode(portableEvidence).write(
                    to: temporary.appendingPathComponent(evidenceFilename),
                    options: .atomic
                )
            }

            // The source machine's absolute path and bookmark are neither
            // useful nor desirable in a portable file. Import always points
            // the snapshot at its own managed PDF copy.
            var portableWorkspace = workspace
            portableWorkspace.documentURL = URL(fileURLWithPath: documentFilename)
            let package = ReadingSessionPackage(
                formatVersion: currentFormatVersion,
                documentFilename: documentFilename,
                workspace: portableWorkspace,
                evidenceFilename: portableEvidence == nil ? nil : evidenceFilename
            )
            try encoder.encode(package).write(
                to: temporary.appendingPathComponent(manifestFilename),
                options: .atomic
            )

            if manager.fileExists(atPath: destination.path) {
                _ = try manager.replaceItemAt(destination, withItemAt: temporary)
            } else {
                try manager.moveItem(at: temporary, to: destination)
            }
        } catch let error as ReadingSessionPackageError {
            throw error
        } catch {
            throw ReadingSessionPackageError.cannotWritePackage
        }
    }

    nonisolated static func read(from packageURL: URL) throws -> (ReadingSessionPackage, URL) {
        let manifestURL = packageURL.appendingPathComponent(manifestFilename)
        var packageIsDirectory: ObjCBool = false
        guard FileManager.default.fileExists(
            atPath: packageURL.path,
            isDirectory: &packageIsDirectory
        ), packageIsDirectory.boolValue,
              let data = try? Data(contentsOf: manifestURL)
        else { throw ReadingSessionPackageError.invalidPackage }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let package = try? decoder.decode(ReadingSessionPackage.self, from: data)
        else { throw ReadingSessionPackageError.invalidPackage }
        guard package.formatVersion <= currentFormatVersion else {
            throw ReadingSessionPackageError.unsupportedVersion
        }

        let filename = package.documentFilename
        guard filename == URL(fileURLWithPath: filename).lastPathComponent,
              filename.lowercased().hasSuffix(".pdf")
        else { throw ReadingSessionPackageError.invalidPackage }

        let documentURL = packageURL.appendingPathComponent(filename)
        let values = try? documentURL.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        guard values?.isRegularFile == true,
              values?.isSymbolicLink != true
        else { throw ReadingSessionPackageError.invalidPackage }
        return (package, documentURL)
    }

    /// Decode and validate portable evidence against the packaged PDF bytes.
    /// A package that declares evidence but cannot prove it belongs to its PDF
    /// is damaged rather than silently trusted or partially imported.
    nonisolated static func readEvidence(
        from packageURL: URL,
        package: ReadingSessionPackage,
        documentURL: URL
    ) throws -> PortableReferenceEvidence? {
        guard let filename = package.evidenceFilename else { return nil }
        guard filename == URL(fileURLWithPath: filename).lastPathComponent,
              filename == evidenceFilename else {
            throw ReadingSessionPackageError.invalidPackage
        }
        let url = packageURL.appendingPathComponent(filename)
        let values = try? url.resourceValues(forKeys: [
            .isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey,
        ])
        guard values?.isRegularFile == true, values?.isSymbolicLink != true,
              (values?.fileSize ?? .max) <= 100 * 1_024 * 1_024,
              let data = try? Data(contentsOf: url) else {
            throw ReadingSessionPackageError.invalidPackage
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let evidence = try? decoder.decode(PortableReferenceEvidence.self, from: data),
              try validate(evidence, documentURL: documentURL) else {
            throw ReadingSessionPackageError.invalidPackage
        }
        return evidence
    }

    private nonisolated static func makePortableEvidence(
        for documentURL: URL
    ) throws -> PortableReferenceEvidence? {
        let fingerprint = try ReferenceIndexCacheStore.fingerprint(for: documentURL)
        guard let index = try ReferenceIndexCacheStore.load(fingerprint: fingerprint),
              index.failedPageIndices.isEmpty else { return nil }
        let definitions = index.entries.compactMap { entry -> ReferenceGraphDefinition? in
            guard let kind = ReferenceKind(rawValue: entry.kind) else { return nil }
            return ReferenceGraphDefinition(
                reference: DetectedReference(kind: kind, number: entry.number),
                pageIndex: entry.pageIndex,
                definingEndOffset: entry.evidence?.textLayerMatchEndOffset
            )
        }
        let expected = Set(definitions.map {
            "\($0.reference.kind.rawValue):\($0.reference.number):\($0.pageIndex)"
        })
        let graph: ReferenceMentionGraph
        if let cached = try ReferenceIndexCacheStore.loadGraph(fingerprint: fingerprint),
           Set(cached.records.map {
               "\($0.definition.reference.kind.rawValue):\($0.definition.reference.number):\($0.definition.pageIndex)"
           }) == expected {
            graph = cached
        } else {
            graph = try ReferenceMentionFinder.buildGraph(
                documentURL: documentURL,
                definitions: definitions
            )
            try ReferenceIndexCacheStore.saveGraph(graph)
        }
        let evidence = PortableReferenceEvidence(
            schemaVersion: PortableReferenceEvidence.schemaVersion,
            documentFingerprint: fingerprint,
            referenceIndex: index,
            mentionGraph: graph
        )
        // Keep export and import on the same trust boundary: if the local
        // cache cannot prove its offsets and page regions against the source
        // PDF, omit it instead of writing evidence the destination will reject.
        guard try validate(evidence, documentURL: documentURL) else { return nil }
        return evidence
    }

    private nonisolated static func validate(
        _ evidence: PortableReferenceEvidence,
        documentURL: URL
    ) throws -> Bool {
        guard evidence.schemaVersion == PortableReferenceEvidence.schemaVersion,
              evidence.referenceIndex.schemaVersion == PersistedReferenceIndex.schemaVersion,
              evidence.mentionGraph.schemaVersion == ReferenceMentionGraph.schemaVersion else {
            return false
        }
        let fingerprint = try ReferenceIndexCacheStore.fingerprint(for: documentURL)
        guard evidence.documentFingerprint == fingerprint,
              evidence.referenceIndex.documentFingerprint == fingerprint,
              evidence.mentionGraph.documentFingerprint == fingerprint,
              let document = PDFDocument(url: documentURL) else { return false }
        guard evidence.referenceIndex.failedPageIndices.allSatisfy({
            $0 >= 0 && $0 < document.pageCount
        }) else { return false }

        guard evidence.referenceIndex.entries.count <= 100_000,
              evidence.mentionGraph.records.count <= 100_000 else { return false }
        var entries: [ReferenceKey: Int] = [:]
        for entry in evidence.referenceIndex.entries {
            guard let kind = ReferenceKind(rawValue: entry.kind),
                  !entry.number.isEmpty,
                  entry.pageIndex >= 0, entry.pageIndex < document.pageCount,
                  entry.formattedBody.count <= 100_000,
                  let source = entry.evidence,
                  source.effectiveSource == .pdfText,
                  let page = document.page(at: entry.pageIndex),
                  let pageText = page.string else { return false }
            let key = ReferenceKey(kind: kind, number: entry.number)
            guard entries[key] == nil,
                  source.startOffset >= 0,
                  source.endOffset >= source.startOffset,
                  source.endOffset <= (pageText as NSString).length,
                  (pageText as NSString).substring(with: NSRange(
                    location: source.startOffset,
                    length: source.endOffset - source.startOffset
                  )) == source.sourceExcerpt,
                  ReferenceEvidenceRegionResolver.exactRegion(for: source, on: page) != nil else {
                return false
            }
            entries[key] = entry.pageIndex
        }

        var graphKeys = Set<ReferenceKey>()
        for record in evidence.mentionGraph.records {
            let definition = record.definition
            let key = definition.reference.key
            guard entries[key] == definition.pageIndex,
                  graphKeys.insert(key).inserted,
                  definition.pageIndex >= 0,
                  definition.pageIndex < document.pageCount,
                  record.result.mentions.count <= 200,
                  record.result.pagesWithoutText >= 0,
                  record.result.pagesWithoutText <= document.pageCount,
                  record.result.unresolvedMatches >= 0 else { return false }
            if let definingEndOffset = definition.definingEndOffset {
                guard definingEndOffset >= 0,
                      let page = document.page(at: definition.pageIndex),
                      definingEndOffset <= page.numberOfCharacters else { return false }
            }
            for mention in record.result.mentions {
                guard mention.pageIndex >= definition.pageIndex,
                      mention.pageIndex < document.pageCount,
                      mention.context.count <= 1_000,
                      let page = document.page(at: mention.pageIndex),
                      let pageText = page.string,
                      ReferenceEvidenceRegionResolver.exactRegion(
                        matchedText: mention.matchedText,
                        startOffset: mention.startOffset,
                        endOffset: mention.startOffset + mention.matchedText.utf16.count,
                        on: page
                      ) == mention.region,
                      ReferenceMentionFinder.candidateMatches(
                        in: pageText,
                        for: definition.reference
                      ).contains(where: {
                        $0.startOffset == mention.startOffset &&
                            $0.matchedText == mention.matchedText &&
                            $0.context == mention.context
                      }),
                      mention.pageIndex > definition.pageIndex ||
                        mention.startOffset >= (definition.definingEndOffset ?? 0) else { return false }
            }
        }
        return graphKeys == Set(entries.keys)
    }
}
