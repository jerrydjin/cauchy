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
    private static let pluralBlockRegex = try! NSRegularExpression(pattern: ReferenceParsing.pluralBlockPattern)
    private static let pluralNumberRegex = try! NSRegularExpression(pattern: ReferenceParsing.referenceNumberPattern)
    private static let bracketCitationRegex = try! NSRegularExpression(pattern: ReferenceParsing.bracketCitationBody)
    private static let authorYearParentheticalRegex = try! NSRegularExpression(pattern: ReferenceParsing.authorYearParenthetical)
    private static let authorYearBracketRegex = try! NSRegularExpression(pattern: ReferenceParsing.authorYearBracket)
    private static let bracketKeyRegex = try! NSRegularExpression(
        pattern: #"^(?:see\s+)?(\#(ReferenceParsing.bibliographyKey))(?:\s*[-–—]\s*\d+)?(?:\s*,\s*(.+))?$"#
    )
    /// "Theorem (3.2)" prints the statement number in parentheses.
    private static let statementBeforeParenthesis = try! NSRegularExpression(
        pattern: #"(?i)\b(\#(ReferenceParsing.namedBlockKeywords))\s*$"#
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

    /// `PDFTextExtractor` reports the cursor as a UTF-16 offset, including
    /// after it stitches the previous page with `prefix.utf16.count`.
    /// A character offset lands past the citation once the line contains a
    /// non-BMP glyph.
    private static func cursorIndex(in text: String, offset: Int) -> String.Index {
        let utf16Length = (text as NSString).length
        var clamped = max(0, min(offset, utf16Length))
        while true {
            if let range = Range(NSRange(location: clamped, length: 0), in: text) {
                return range.lowerBound
            }
            if clamped == 0 { return text.startIndex }
            clamped -= 1
        }
    }

    private struct Detection {
        var local: [DetectedReferenceMatch]
        var citations: [ExternalCitation]
    }

    private static func detection(in text: String) -> Detection {
        let raw = namedBlockMatches(in: text)
            + pluralBlockMatches(in: text)
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
        let trimmed = body
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        let nsRange = NSRange(trimmed.startIndex..., in: trimmed)
        guard let match = bracketKeyRegex.firstMatch(in: trimmed, range: nsRange),
              match.range.location == 0,
              let keyRange = Range(match.range(at: 1), in: trimmed) else { return nil }
        let key = String(trimmed[keyRange])
        let qualifier: String?
        if match.range(at: 2).location != NSNotFound, let qualifierRange = Range(match.range(at: 2), in: trimmed) {
            let text = String(trimmed[qualifierRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            // "[0, 1]" is an interval. "[3, (1.3)]" and "[12, Theorem 3.2]" are citations.
            guard text.contains(where: \.isLetter) || text.contains("(") else { return nil }
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

    private static func pluralBlockMatches(in text: String) -> [DetectedReferenceMatch] {
        let full = NSRange(text.startIndex..., in: text)
        return pluralBlockRegex.matches(in: text, range: full).flatMap { match -> [DetectedReferenceMatch] in
            guard let kindRange = Range(match.range(at: 1), in: text),
                  let kind = ReferenceKind.fromKeyword(String(text[kindRange])),
                  let phrase = Range(match.range, in: text) else { return [] }
            let list = String(text[Range(match.range(at: 2), in: text)!])
            let numbers = pluralNumberRegex.matches(in: list, range: NSRange(list.startIndex..., in: list))
            return numbers.compactMap { numberMatch in
                let absolute = NSRange(
                    location: match.range(at: 2).location + numberMatch.range.location,
                    length: numberMatch.range.length
                )
                guard let numberRange = Range(absolute, in: text) else { return nil }
                let start = numberMatch.range.location == 0 ? phrase.lowerBound : numberRange.lowerBound
                return DetectedReferenceMatch(
                    reference: DetectedReference(kind: kind, number: String(text[numberRange])),
                    range: start..<numberRange.upperBound
                )
            }
        }
    }

    private static func equationCiteMatches(in text: String) -> [DetectedReferenceMatch] {
        return matches(from: equationCiteRegex, in: text) { match, source in
            guard let numberRange = Range(match.range(at: 1), in: source),
                  let range = Range(match.range, in: source) else { return nil }
            let number = String(source[numberRange])
            // A bare parenthetical after a statement word is that statement.
            // "Eq. (2.3)" and "by (1.2)" still start with the equation prefix.
            if source[range].hasPrefix("("),
               let keyword = statementKeyword(endingAt: range.lowerBound, in: source) {
                return DetectedReferenceMatch(
                    reference: DetectedReference(kind: keyword.kind, number: number),
                    range: keyword.start..<range.upperBound
                )
            }
            return DetectedReferenceMatch(
                reference: DetectedReference(kind: .equation, number: number),
                range: range
            )
        }
    }

    /// The statement word immediately before a parenthesized number, if any.
    private static func statementKeyword(
        endingAt index: String.Index,
        in source: String
    ) -> (kind: ReferenceKind, start: String.Index)? {
        let prefix = String(source[..<index])
        let nsRange = NSRange(prefix.startIndex..., in: prefix)
        guard let match = statementBeforeParenthesis.firstMatch(in: prefix, range: nsRange),
              let kindRange = Range(match.range(at: 1), in: prefix),
              let word = Range(match.range, in: prefix),
              let kind = ReferenceKind.fromKeyword(String(prefix[kindRange])) else { return nil }
        let start = source.index(
            source.startIndex,
            offsetBy: prefix.distance(from: prefix.startIndex, to: word.lowerBound)
        )
        return (kind, start)
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
