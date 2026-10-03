import Foundation

enum ReferenceGroundingStatus: String, Codable, Equatable, Sendable {
    /// One unambiguous defining source occurrence was located in PDF text.
    case supported
    /// The reference is present, but more than one occurrence could be the
    /// defining source. The entry stays useful while the ambiguity remains
    /// visible to the reader.
    case uncertain
}

enum ReferenceEvidenceSource: String, Codable, Equatable, Sendable {
    /// Exact text and offsets from PDFKit's searchable text layer.
    case pdfText
    /// A local Vision OCR line plus its observed page region. Useful for
    /// navigation, but never treated as verbatim source text for Ask.
    case visionOCR
}

/// Verbatim evidence retained from the PDF text layer for an indexed result.
/// This is intentionally separate from `formattedBody`: the body is a model
/// transcription for readable maths, while this excerpt is the auditable source.
struct ReferenceEvidence: Codable, Equatable, Sendable {
    let status: ReferenceGroundingStatus
    let sourceExcerpt: String
    let matchedText: String
    let occurrenceCount: Int
    /// UTF-16 offsets into the original page text, which make benchmark output
    /// and exact PDF highlighting reproducible.
    let startOffset: Int
    let endOffset: Int
    /// UTF-16 range of the exact matched heading or equation label in the PDF
    /// page's text layer. Unlike the excerpt range, this resolves to a small
    /// page-space region for visual inspection.
    let matchStartOffset: Int?
    let matchEndOffset: Int?
    /// nil decodes as `.pdfText` for indexes written before OCR candidates.
    let source: ReferenceEvidenceSource?
    /// Present for OCR evidence, whose offsets do not belong to PDFKit's text
    /// layer and therefore cannot be resolved through `PDFPage.selection`.
    let matchedRegion: NormalizedRect?

    init(
        status: ReferenceGroundingStatus,
        sourceExcerpt: String,
        matchedText: String,
        occurrenceCount: Int,
        startOffset: Int,
        endOffset: Int,
        matchStartOffset: Int? = nil,
        matchEndOffset: Int? = nil,
        source: ReferenceEvidenceSource = .pdfText,
        matchedRegion: NormalizedRect? = nil
    ) {
        self.status = status
        self.sourceExcerpt = sourceExcerpt
        self.matchedText = matchedText
        self.occurrenceCount = occurrenceCount
        self.startOffset = startOffset
        self.endOffset = endOffset
        self.matchStartOffset = matchStartOffset
        self.matchEndOffset = matchEndOffset
        self.source = source
        self.matchedRegion = matchedRegion
    }


    var effectiveSource: ReferenceEvidenceSource { source ?? .pdfText }

    /// OCR offsets belong to a synthesized transcript, not the searchable PDF
    /// page, so mention search must not compare them to PDFKit offsets.
    var textLayerMatchEndOffset: Int? {
        effectiveSource == .pdfText ? matchEndOffset : nil
    }
}

enum ReferenceContentOrigin: String, Codable, Equatable, Sendable {
    /// A model transcribed and formatted the body, then deterministic checks
    /// accepted it.
    case modelTranscription
    /// The model omitted or malformed the statement, so Cauchy retained a
    /// lightly cleaned copy of the PDF text instead of losing the reference.
    case sourceFallback
    /// A conservative label and line region found by local Vision OCR. The
    /// transcript is explicitly unverified and excluded from answer grounding.
    case ocrCandidate
}

struct IndexedReference: Equatable, Sendable, Codable {
    let reference: DetectedReference
    let formattedBody: String
    let pageIndex: Int
    /// The printed title, e.g. "Compactness" for "Definition 3.2 (Compactness)".
    /// nil when the notes give no name (or the entry predates schema v4).
    let name: String?
    /// Exact source evidence (schema v6+). nil only for deliberately decoded
    /// legacy/test values; production indexes always attach it.
    let evidence: ReferenceEvidence?
    let contentOrigin: ReferenceContentOrigin

    init(
        reference: DetectedReference,
        formattedBody: String,
        pageIndex: Int,
        name: String? = nil,
        evidence: ReferenceEvidence? = nil,
        contentOrigin: ReferenceContentOrigin = .modelTranscription
    ) {
        self.reference = reference
        self.formattedBody = formattedBody
        self.pageIndex = pageIndex
        self.name = name
        self.evidence = evidence
        self.contentOrigin = contentOrigin
    }

    var documentBlock: DocumentBlock {
        DocumentBlock(
            reference: reference,
            formattedBody: formattedBody,
            pageIndex: pageIndex,
            evidence: evidence,
            contentOrigin: contentOrigin
        )
    }

    /// "Definition 3.2 (Compactness), p. 41" — used when injecting the
    /// statement into an assistant prompt.
    var promptHeading: String {
        let title = name.map { " (\($0))" } ?? ""
        return "\(reference.displayName)\(title), p. \(pageIndex + 1)"
    }

    /// Answers are grounded in the PDF text, never in an unverified model
    /// transcription. An older entry without evidence is not an answer source;
    /// the ordinary document passages can still support the question.
    var groundingBody: String {
        guard evidence?.effectiveSource == .pdfText else { return "" }
        return evidence?.sourceExcerpt ?? ""
    }
}

struct DocumentBlock: Equatable, Sendable {
    let reference: DetectedReference
    let formattedBody: String
    let pageIndex: Int
    let evidence: ReferenceEvidence?
    let contentOrigin: ReferenceContentOrigin

    var title: String { reference.displayName }

    init(
        reference: DetectedReference,
        formattedBody: String,
        pageIndex: Int,
        evidence: ReferenceEvidence? = nil,
        contentOrigin: ReferenceContentOrigin = .modelTranscription
    ) {
        self.reference = reference
        self.formattedBody = formattedBody
        self.pageIndex = pageIndex
        self.evidence = evidence
        self.contentOrigin = contentOrigin
    }

    init(from indexed: IndexedReference) {
        self.reference = indexed.reference
        self.formattedBody = indexed.formattedBody
        self.pageIndex = indexed.pageIndex
        self.evidence = indexed.evidence
        self.contentOrigin = indexed.contentOrigin
    }
}
