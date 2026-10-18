import Foundation

struct DetectedReference: Equatable, Sendable, Codable {
    let kind: ReferenceKind
    let number: String

    var displayName: String {
        switch kind {
        case .equation:
            "(\(number))"
        default:
            "\(kind.displayName) \(number)"
        }
    }

    var key: ReferenceKey {
        ReferenceKey(kind: kind, number: number)
    }
}

struct DetectedReferenceMatch: Equatable, Sendable {
    let reference: DetectedReference
    let range: Range<String.Index>
}

enum ReferenceDetector {
    private static let namedBlockRegex = try! NSRegularExpression(pattern: ReferenceParsing.namedBlockPattern)
    private static let equationCiteRegex = try! NSRegularExpression(pattern: ReferenceParsing.equationCitePattern)
    private static let figureRegex = try! NSRegularExpression(pattern: ReferenceParsing.figurePattern)
    private static let pairedFiguresRegex = try! NSRegularExpression(pattern: ReferenceParsing.pairedFiguresPattern)
    private static let bracketCitationRegex = try! NSRegularExpression(pattern: ReferenceParsing.bracketCitationBody)
    private static let authorYearParentheticalRegex = try! NSRegularExpression(pattern: ReferenceParsing.authorYearParenthetical)
    private static let authorYearBracketRegex = try! NSRegularExpression(pattern: ReferenceParsing.authorYearBracket)
    private static let bracketKeyRegex = try! NSRegularExpression(
        pattern: #"^(?:see\s+)?(\#(ReferenceParsing.bibliographyKey))(?:\s*[-–—]\s*\d+)?(?:\s*,\s*(.+))?$"#
    )

    static func allReferences(in text: String) -> [DetectedReferenceMatch] {
        detection(in: text).local
    }

    static func bestReference(in text: String, cursorOffset: Int) -> DetectedReference? {
        let found = detection(in: text)
        guard !found.local.isEmpty else { return nil }
        let cursorIndex = cursorIndex(in: text, offset: cursorOffset)

        // "[IK99, Lemma 1.15]" names a result in the cited paper.
        if found.citations.contains(where: { $0.range.contains(cursorIndex) }) {
            return nil
        }

        if let containing = found.local.first(where: { $0.range.contains(cursorIndex) }) {
            return containing.reference
        }

        return found.local.min(by: {
            distance(from: cursorIndex, to: $0.range, in: text) < distance(from: cursorIndex, to: $1.range, in: text)
        })?.reference
    }

    /// The citation under the cursor, if the pointer is inside one.
    static func externalCitation(in text: String, cursorOffset: Int) -> ExternalCitation? {
        let cursorIndex = cursorIndex(in: text, offset: cursorOffset)
        return detection(in: text).citations.first { $0.range.contains(cursorIndex) }
    }

    private static func cursorIndex(in text: String, offset: Int) -> String.Index {
        let clamped = max(0, min(offset, text.count))
        return text.index(text.startIndex, offsetBy: clamped)
    }

    private struct Detection {
        var local: [DetectedReferenceMatch]
        var citations: [ExternalCitation]
    }

    private static func detection(in text: String) -> Detection {
        let raw = namedBlockMatches(in: text)
            + equationCiteMatches(in: text)
            + figureMatches(in: text)
            + pairedFigureMatches(in: text)
        let citations = externalCitations(in: text)
        let local = raw.filter { match in
            !citations.contains { citation in
                citation.range.lowerBound <= match.range.lowerBound
                    && match.range.upperBound <= citation.range.upperBound
            }
        }.sorted { $0.range.lowerBound < $1.range.lowerBound }
        return Detection(local: local, citations: citations)
    }

    private static func externalCitations(in text: String) -> [ExternalCitation] {
        var citations: [ExternalCitation] = []
        let full = NSRange(text.startIndex..., in: text)

        for match in authorYearParentheticalRegex.matches(in: text, range: full) {
            guard let range = Range(match.range, in: text),
                  let authorRange = Range(match.range(at: 1), in: text),
                  let yearRange = Range(match.range(at: 2), in: text) else { continue }
            citations.append(ExternalCitation(
                key: nil,
                author: String(text[authorRange]),
                year: String(text[yearRange]),
                qualifier: nil,
                range: range
            ))
        }

        for match in authorYearBracketRegex.matches(in: text, range: full) {
            guard let range = Range(match.range, in: text),
                  let authorRange = Range(match.range(at: 1), in: text),
                  let yearRange = Range(match.range(at: 2), in: text),
                  !citations.contains(where: { $0.range.overlaps(range) }) else { continue }
            citations.append(ExternalCitation(
                key: nil,
                author: String(text[authorRange]),
                year: String(text[yearRange]),
                qualifier: nil,
                range: range
            ))
        }

        for match in bracketCitationRegex.matches(in: text, range: full) {
            guard let range = Range(match.range, in: text),
                  let bodyRange = Range(match.range(at: 1), in: text),
                  !citations.contains(where: { $0.range.overlaps(range) }),
                  let citation = bracketCitation(body: String(text[bodyRange]), range: range) else { continue }
            citations.append(citation)
        }
        return citations
    }

    /// A bracket is a citation when it is a bare key, or a key plus a named
    /// result. An interval such as "[0, 1]" is not one.
    private static func bracketCitation(body: String, range: Range<String.Index>) -> ExternalCitation? {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        let nsRange = NSRange(trimmed.startIndex..., in: trimmed)
        guard let match = bracketKeyRegex.firstMatch(in: trimmed, range: nsRange),
              match.range.location == 0,
              let keyRange = Range(match.range(at: 1), in: trimmed) else { return nil }
        let key = String(trimmed[keyRange])
        let qualifier: String?
        if match.range(at: 2).location != NSNotFound, let qualifierRange = Range(match.range(at: 2), in: trimmed) {
            let text = String(trimmed[qualifierRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard text.contains(where: \.isLetter) else { return nil }
            qualifier = text
        } else if key.count == 4, key.hasPrefix("19") || key.hasPrefix("20") {
            // "[2019]" is a year, not bibliography entry 2019.
            return ExternalCitation(key: nil, author: nil, year: key, qualifier: nil, range: range)
        } else {
            qualifier = nil
        }
        return ExternalCitation(key: key, author: nil, year: nil, qualifier: qualifier, range: range)
    }

    static func firstReference(in text: String) -> DetectedReference? {
        allReferences(in: text).first?.reference
    }

    private static func namedBlockMatches(in text: String) -> [DetectedReferenceMatch] {
        return matches(from: namedBlockRegex, in: text) { match, source in
            guard let kindRange = Range(match.range(at: 1), in: source),
                  let numberRange = Range(match.range(at: 2), in: source),
                  let kind = ReferenceKind.fromKeyword(String(source[kindRange])) else {
                return nil
            }
            let number = String(source[numberRange])
            let range = Range(match.range, in: source)!
            return DetectedReferenceMatch(
                reference: DetectedReference(kind: kind, number: number),
                range: range
            )
        }
    }

    private static func equationCiteMatches(in text: String) -> [DetectedReferenceMatch] {
        return matches(from: equationCiteRegex, in: text) { match, source in
            guard let numberRange = Range(match.range(at: 1), in: source) else { return nil }
            let number = String(source[numberRange])
            let range = Range(match.range, in: source)!
            return DetectedReferenceMatch(
                reference: DetectedReference(kind: .equation, number: number),
                range: range
            )
        }
    }

    private static func figureMatches(in text: String) -> [DetectedReferenceMatch] {
        matches(from: figureRegex, in: text) { match, source in
            guard let numberRange = Range(match.range(at: 1), in: source),
                  let range = Range(match.range, in: source) else { return nil }
            return DetectedReferenceMatch(
                reference: DetectedReference(kind: .figure, number: String(source[numberRange])),
                range: range
            )
        }
    }

    private static func pairedFigureMatches(in text: String) -> [DetectedReferenceMatch] {
        let range = NSRange(text.startIndex..., in: text)
        return pairedFiguresRegex.matches(in: text, range: range).flatMap { match in
            guard let firstNumber = Range(match.range(at: 2), in: text),
                  let firstPanel = Range(match.range(at: 1), in: text),
                  let secondNumber = Range(match.range(at: 4), in: text),
                  let secondPanel = Range(match.range(at: 3), in: text),
                  let phrase = Range(match.range, in: text) else { return [DetectedReferenceMatch]() }
            return [
                DetectedReferenceMatch(
                    reference: DetectedReference(kind: .figure, number: String(text[firstNumber])),
                    range: phrase.lowerBound..<firstPanel.upperBound
                ),
                DetectedReferenceMatch(
                    reference: DetectedReference(kind: .figure, number: String(text[secondNumber])),
                    range: secondPanel
                )
            ]
        }
    }

    private static func matches(
        from regex: NSRegularExpression,
        in text: String,
        transform: (NSTextCheckingResult, String) -> DetectedReferenceMatch?
    ) -> [DetectedReferenceMatch] {
        let range = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, range: range).compactMap { match in
            transform(match, text)
        }
    }

    private static func distance(from index: String.Index, to range: Range<String.Index>, in text: String) -> Int {
        let cursorOffset = index.utf16Offset(in: text)
        let startOffset = range.lowerBound.utf16Offset(in: text)
        let endOffset = range.upperBound.utf16Offset(in: text)
        if cursorOffset < startOffset { return startOffset - cursorOffset }
        if cursorOffset >= endOffset { return cursorOffset - endOffset }
        return 0
    }
}
