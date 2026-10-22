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

    static func allReferences(in text: String) -> [DetectedReferenceMatch] {
        var matches: [DetectedReferenceMatch] = []
        matches.append(contentsOf: namedBlockMatches(in: text))
        matches.append(contentsOf: pluralBlockMatches(in: text))
        matches.append(contentsOf: equationCiteMatches(in: text))
        matches.append(contentsOf: figureMatches(in: text))
        matches.append(contentsOf: pairedFigureMatches(in: text))
        return matches.sorted { $0.range.lowerBound < $1.range.lowerBound }
    }

    static func bestReference(in text: String, cursorOffset: Int) -> DetectedReference? {
        let matches = allReferences(in: text)
        guard !matches.isEmpty else { return nil }

        let clampedOffset = max(0, min(cursorOffset, text.count))
        let cursorIndex = text.index(text.startIndex, offsetBy: clampedOffset)

        if let containing = matches.first(where: { $0.range.contains(cursorIndex) }) {
            return containing.reference
        }

        return matches.min(by: {
            distance(from: cursorIndex, to: $0.range, in: text) < distance(from: cursorIndex, to: $1.range, in: text)
        })?.reference
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
