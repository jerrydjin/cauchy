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
    private static let namedBlockListRegex = try! NSRegularExpression(pattern: ReferenceParsing.namedBlockListPattern)
    private static let referenceNumberRegex = try! NSRegularExpression(pattern: ReferenceParsing.referenceNumber)
    private static let equationCiteRegex = try! NSRegularExpression(pattern: ReferenceParsing.equationCitePattern)
    private static let figureRegex = try! NSRegularExpression(pattern: ReferenceParsing.figurePattern)
    private static let pairedFiguresRegex = try! NSRegularExpression(pattern: ReferenceParsing.pairedFiguresPattern)
    private static let bibliographyQualifierRegex = try! NSRegularExpression(
        pattern: ReferenceParsing.bibliographyQualifierPrefix
    )

    static func allReferences(in text: String) -> [DetectedReferenceMatch] {
        detection(in: text).local
    }

    static func bestReference(in text: String, cursorOffset: Int) -> DetectedReference? {
        let found = detection(in: text)
        guard !found.local.isEmpty || !found.bibliographySpans.isEmpty else { return nil }

        let clampedOffset = max(0, min(cursorOffset, text.count))
        let cursorIndex = text.index(text.startIndex, offsetBy: clampedOffset)

        // A bracket citation such as "[12, Theorem 3.2]" names a statement in
        // the cited work. The cursor stays unresolved there.
        if found.bibliographySpans.contains(where: { $0.contains(cursorIndex) }) {
            return nil
        }

        if let containing = found.local.first(where: { $0.range.contains(cursorIndex) }) {
            return containing.reference
        }

        return found.local.min(by: {
            distance(from: cursorIndex, to: $0.range, in: text) < distance(from: cursorIndex, to: $1.range, in: text)
        })?.reference
    }

    static func firstReference(in text: String) -> DetectedReference? {
        allReferences(in: text).first?.reference
    }

    private struct Detection {
        var local: [DetectedReferenceMatch]
        var bibliographySpans: [Range<String.Index>]
    }

    private static func detection(in text: String) -> Detection {
        let raw = namedBlockMatches(in: text)
            + namedBlockListMatches(in: text)
            + equationCiteMatches(in: text)
            + figureMatches(in: text)
            + pairedFigureMatches(in: text)

        var local: [DetectedReferenceMatch] = []
        var bibliographySpans: [Range<String.Index>] = []
        for match in raw {
            if let span = bibliographySpan(covering: match.range, in: text) {
                bibliographySpans.append(span)
            } else {
                local.append(match)
            }
        }
        local.sort { $0.range.lowerBound < $1.range.lowerBound }
        return Detection(local: local, bibliographySpans: bibliographySpans)
    }

    private static func namedBlockMatches(in text: String) -> [DetectedReferenceMatch] {
        return matches(from: namedBlockRegex, in: text) { match, source in
            guard let kindRange = Range(match.range(at: 1), in: source),
                  let numberRange = Range(match.range(at: 2), in: source),
                  let kind = ReferenceParsing.kind(forKeyword: String(source[kindRange])) else {
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

    private static func namedBlockListMatches(in text: String) -> [DetectedReferenceMatch] {
        let range = NSRange(text.startIndex..., in: text)
        return namedBlockListRegex.matches(in: text, range: range).flatMap { match in
            guard let kindRange = Range(match.range(at: 1), in: text),
                  let listRange = Range(match.range(at: 2), in: text),
                  let phraseRange = Range(match.range, in: text),
                  let kind = ReferenceParsing.kind(forKeyword: String(text[kindRange])) else {
                return [DetectedReferenceMatch]()
            }
            let numberNSRange = NSRange(listRange, in: text)
            return referenceNumberRegex.matches(in: text, range: numberNSRange).compactMap { numberMatch in
                guard let numberRange = Range(numberMatch.range, in: text) else { return nil }
                let span = numberRange.lowerBound == listRange.lowerBound
                    ? phraseRange.lowerBound..<numberRange.upperBound
                    : numberRange
                return DetectedReferenceMatch(
                    reference: DetectedReference(kind: kind, number: String(text[numberRange])),
                    range: span
                )
            }
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

    /// "[12, Theorem 3.2]" qualifies the mention with a bibliography number.
    /// The span runs from the opening bracket through the closing one.
    private static func bibliographySpan(
        covering matchRange: Range<String.Index>,
        in text: String
    ) -> Range<String.Index>? {
        guard let open = text[..<matchRange.lowerBound].lastIndex(of: "[") else { return nil }
        let qualifier = text.index(after: open)..<matchRange.lowerBound
        if text[qualifier].contains("]") { return nil }
        let qualifierNS = NSRange(qualifier, in: text)
        guard let found = bibliographyQualifierRegex.firstMatch(in: text, range: qualifierNS),
              found.range.location == qualifierNS.location else { return nil }
        guard let close = text[matchRange.upperBound...].firstIndex(of: "]"),
              !text[matchRange.upperBound..<close].contains("[") else { return nil }
        return open..<text.index(after: close)
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
