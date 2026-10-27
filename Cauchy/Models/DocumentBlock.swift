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
        DocumentBlock(from: self)
    }

    /// "Definition 3.2 (Compactness), p. 41" — used when injecting the
    /// statement into an assistant prompt. A name that only repeats the
    /// label is left off, same as the reference card.
    var promptHeading: String {
        let title = ReferencePreviewPresentation.printedName(
            kind: reference.kind,
            number: reference.number,
            name: name
        ).map { " (\($0))" } ?? ""
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
    /// Printed name, e.g. "Compactness" in "Definition 3.2 (Compactness)".
    /// nil when the notes give no name. For a figure this is the caption title,
    /// which the preview shows under the image rather than in the heading.
    let name: String?
    let evidence: ReferenceEvidence?
    let contentOrigin: ReferenceContentOrigin

    var title: String { reference.displayName }

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

    init(from indexed: IndexedReference) {
        self.reference = indexed.reference
        self.formattedBody = indexed.formattedBody
        self.pageIndex = indexed.pageIndex
        self.name = indexed.name
        self.evidence = indexed.evidence
        self.contentOrigin = indexed.contentOrigin
    }
}

/// What the reference pane shows for one hovered or selected entry.
/// One body: the clean statement, or the figure. Evidence is not a mode.
struct ReferencePreviewModel: Equatable, Sendable {
    enum Body: Equatable, Sendable {
        case statement(String)
        case figure(caption: String?)
    }

    /// Kind and number, plus a parenthetical name when the entry has one.
    /// "Theorem 3.2" or "Theorem 3.2 (Compactness)".
    let heading: String
    let body: Body
}

enum ReferencePreviewPresentation {
    static func model(for block: DocumentBlock) -> ReferencePreviewModel {
        ReferencePreviewModel(heading: heading(for: block), body: body(for: block))
    }

    /// Figures keep the caption under the image, so the heading stays
    /// "Figure 3.2" even when a caption title was stored as the name.
    /// A parenthetical that only repeats the label ("Proposition 2.5.1
    /// (Proposition 2.5.1)", "Prop. 2.5.1", "Equation 1.4") is dropped.
    static func heading(for block: DocumentBlock) -> String {
        let base = block.reference.displayName
        guard block.reference.kind != .figure,
              let name = printedName(
                kind: block.reference.kind,
                number: block.reference.number,
                name: block.name
              ) else {
            return base
        }
        return "\(base) (\(name))"
    }

    /// Longest real printed name, or nil when the stored name is blank or
    /// only restates the kind and number.
    static func printedName(kind: ReferenceKind, number: String, name: String?) -> String? {
        DocumentFind.displayNames(kind: kind, number: number, name: name).first
    }

    static func body(for block: DocumentBlock) -> ReferencePreviewModel.Body {
        if block.reference.kind == .figure {
            return .figure(caption: cleaned(block.formattedBody) ?? cleaned(block.name))
        }
        return .statement(statementText(from: block.formattedBody))
    }

    /// Statement text for the reference card.
    ///
    /// On-device extraction writes JSON escapes into the string field itself:
    /// the two characters `\` and `n` where a paragraph break belongs, and
    /// sometimes `\"` or a backtick. `MessageContentView` then treats `$…$`
    /// as math across that break, SwiftMath rejects the prose, and the
    /// fallback draws the rest of the sentence in monospace — which is how
    /// `\pi` shows up as source. LaTeX commands that share the first letter
    /// (`\nu`, `\to`, `\tau`) stay commands.
    static func statementText(from raw: String) -> String {
        collapseExtraBreaks(
            terminatingMathBeforeProse(
                stripBackticks(unescapeJSONEscapes(raw))
            )
        )
    }

    private static func cleaned(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else { return nil }
        return trimmed
    }

    /// Letter run after the escape character. `\neq` → "eq", `\to` → "o".
    /// A sentence ("Moreover") is not in either set, so `\nMoreover` becomes
    /// a break. `\nu` and `\tau` are, so they stay LaTeX.
    private static let commandSuffixesAfterN: Set<String> = [
        "u", "abla", "atural", "eg", "eq", "e", "i", "ot", "otin", "otag",
        "ewline", "mid", "leq", "geq", "less", "gtr", "leqslant", "geqslant",
        "subseteq", "supseteq", "subseteqq", "supseteqq", "parallel",
        "shortparallel", "shortmid", "triangleleft", "triangleright",
        "trianglelefteq", "trianglerighteq", "cong", "sim", "simeq", "approx",
        "prec", "succ", "preceq", "succeq", "vdash", "vDash", "Vdash", "VDash",
        "leftarrow", "rightarrow", "leftrightarrow", "Leftarrow", "Rightarrow",
        "Leftrightarrow", "earrow", "warrow", "exists", "orm", "onumber",
    ]

    private static let commandSuffixesAfterT: Set<String> = [
        "au", "heta", "hetasym", "imes", "o", "op", "riangle", "riangleq",
        "riangleleft", "riangleright", "rianglelefteq", "rianglerighteq",
        "ext", "extbf", "extit", "extrm", "exttt", "extsf", "extup",
        "extnormal", "extstyle", "extmd", "extsc", "frac", "ilde", "an", "anh",
        "herefore", "woheadleftarrow", "woheadrightarrow", "hicksim", "hickapprox",
    ]

    private static func unescapeJSONEscapes(_ raw: String) -> String {
        var output = ""
        output.reserveCapacity(raw.count)
        var index = raw.startIndex
        while index < raw.endIndex {
            if raw[index] == "\\",
               let codeIndex = raw.index(index, offsetBy: 1, limitedBy: raw.index(before: raw.endIndex)),
               codeIndex < raw.endIndex {
                let code = raw[codeIndex]
                let rest = raw.index(after: codeIndex)
                if (code == "n" || code == "t"), !continuesLaTeXCommand(code, in: raw, from: rest) {
                    // A lone newline is a soft wrap in the card and disappears.
                    // The model used this escape as a paragraph break.
                    output.append(code == "n" ? "\n\n" : "\t")
                    index = rest
                    continue
                }
                if code == "\"" {
                    output.append("\"")
                    index = rest
                    continue
                }
            }
            output.append(raw[index])
            index = raw.index(after: index)
        }
        return output
    }

    private static func continuesLaTeXCommand(
        _ escape: Character,
        in text: String,
        from index: String.Index
    ) -> Bool {
        guard index < text.endIndex, text[index].isLetter else { return false }
        var end = index
        while end < text.endIndex, text[end].isLetter {
            end = text.index(after: end)
        }
        let name = String(text[index..<end])
        let commands = escape == "n" ? commandSuffixesAfterN : commandSuffixesAfterT
        return commands.contains(name)
    }

    /// A backtick in a statement is an extraction artifact. Paired, it becomes
    /// a code span and the math inside it is never drawn.
    private static func stripBackticks(_ text: String) -> String {
        var output = ""
        output.reserveCapacity(text.count)
        var index = text.startIndex
        while index < text.endIndex {
            if text[index] == "\\" {
                let next = text.index(after: index)
                if next < text.endIndex, text[next] == "`" {
                    index = text.index(after: next)
                    continue
                }
            }
            if text[index] == "`" {
                index = text.index(after: index)
                continue
            }
            output.append(text[index])
            index = text.index(after: index)
        }
        return output
    }

    private enum MathScan {
        case none
        case inline
        case display
    }

    /// Closes `$…$` at a newline and `$$…$$` when the next line is prose, so
    /// an escaped break cannot swallow the following sentence into one failed
    /// formula.
    private static func terminatingMathBeforeProse(_ text: String) -> String {
        var result = ""
        result.reserveCapacity(text.count + 8)
        var index = text.startIndex
        var mode = MathScan.none
        var interior = ""

        func closeMath() {
            let trimmed = interior.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                let delimiter = mode == .display ? "$$" : "$"
                result.append(delimiter)
                result.append(trimmed)
                result.append(delimiter)
            }
            interior = ""
            mode = .none
        }

        while index < text.endIndex {
            if mode != .inline, text[index...].hasPrefix("$$") {
                if mode == .display {
                    closeMath()
                } else {
                    mode = .display
                    interior = ""
                }
                index = text.index(index, offsetBy: 2)
                continue
            }

            let character = text[index]
            if character == "$", mode != .display {
                if mode == .inline {
                    closeMath()
                } else {
                    mode = .inline
                    interior = ""
                }
                index = text.index(after: index)
                continue
            }

            if character == "\n", mode == .inline {
                closeMath()
                result.append("\n")
                index = text.index(after: index)
                continue
            }

            if character == "\n", mode == .display {
                let upcoming = lineAfterNewline(text, at: index)
                if upcoming.trimmingCharacters(in: .whitespaces).isEmpty || looksLikeProse(upcoming) {
                    closeMath()
                    result.append("\n")
                    index = text.index(after: index)
                    continue
                }
            }

            if mode == .none {
                result.append(character)
            } else {
                interior.append(character)
            }
            index = text.index(after: index)
        }

        if mode != .none {
            closeMath()
        }
        return result
    }

    private static func lineAfterNewline(_ text: String, at index: String.Index) -> String {
        let start = text.index(after: index)
        guard start < text.endIndex else { return "" }
        if let nextBreak = text[start...].firstIndex(of: "\n") {
            return String(text[start..<nextBreak])
        }
        return String(text[start...])
    }

    private static func looksLikeProse(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !trimmed.contains("\\") else { return false }
        let words = trimmed.split(whereSeparator: \.isWhitespace)
        guard words.count >= 2 else { return false }
        return words.contains { word in
            word.filter(\.isLetter).count >= 4
        }
    }

    private static func collapseExtraBreaks(_ text: String) -> String {
        var collapsed = text
        while collapsed.contains("\n\n\n") {
            collapsed = collapsed.replacingOccurrences(of: "\n\n\n", with: "\n\n")
        }
        return collapsed
    }
}
