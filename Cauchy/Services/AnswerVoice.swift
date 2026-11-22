import Foundation

/// Turns a model's reply into the voice a reader actually sees.
///
/// The prompt already asks for a tutor's opening. This is the backstop for
/// when the model still narrates the pipeline: those sentences are dropped,
/// and any citation marker on them moves onto a sentence that stays, so the
/// page pills are not lost with the meta-talk.
enum AnswerVoice {
    /// Phrases that describe Cauchy's prompt instead of the mathematics.
    static let bannedPhrases = [
        "extracted text",
        "extraction artifact",
        "supplied excerpt",
        "surrounding context",
        "selected passage",
        "separating what appears",
        "check the original page",
        "written without the summation",
    ]

    static func containsBannedMeta(_ text: String) -> Bool {
        let lowered = text.lowercased()
        return bannedPhrases.contains { lowered.contains($0) }
    }

    static func shape(_ text: String) -> String {
        let paragraphs = text.components(separatedBy: "\n\n")
        let shaped = paragraphs.map(shapeParagraph).filter { !$0.isEmpty }
        return shaped.joined(separator: "\n\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func shapeParagraph(_ paragraph: String) -> String {
        let pieces = sentences(in: paragraph)
        var kept: [String] = []
        var rescuedMarkers: [String] = []
        for piece in pieces {
            if containsBannedMeta(piece) {
                rescuedMarkers.append(contentsOf: sourceMarkers(in: piece))
                continue
            }
            kept.append(piece)
        }
        guard !rescuedMarkers.isEmpty else {
            return kept.joined(separator: " ")
        }
        let unique = rescuedMarkers.reduce(into: [String]()) { list, marker in
            if !list.contains(marker) { list.append(marker) }
        }
        if kept.isEmpty {
            return unique.joined(separator: " ")
        }
        var last = kept.removeLast()
        for marker in unique where !last.contains(marker) {
            last += " " + marker
        }
        kept.append(last)
        return kept.joined(separator: " ")
    }

    /// Splits on sentence boundaries outside `$...$`. A partial with no
    /// terminator is one sentence, so a streaming opener can be dropped whole.
    private static func sentences(in text: String) -> [String] {
        var pieces: [String] = []
        var current = ""
        var math = false
        var index = text.startIndex
        while index < text.endIndex {
            let character = text[index]
            if character == "$" {
                math.toggle()
                current.append(character)
                index = text.index(after: index)
                continue
            }
            current.append(character)
            if !math, ".!?".contains(character) {
                let next = text.index(after: index)
                if next == text.endIndex || text[next].isWhitespace {
                    let sentence = current.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !sentence.isEmpty { pieces.append(sentence) }
                    current = ""
                }
            }
            index = text.index(after: index)
        }
        let tail = current.trimmingCharacters(in: .whitespacesAndNewlines)
        if !tail.isEmpty { pieces.append(tail) }
        return pieces
    }

    private static let markerPattern = try! NSRegularExpression(
        pattern: #"\[[A-Z]\d+\]"#,
        options: [.caseInsensitive]
    )

    private static func sourceMarkers(in text: String) -> [String] {
        let range = NSRange(text.startIndex..., in: text)
        return markerPattern.matches(in: text, range: range).compactMap { match in
            Range(match.range, in: text).map { String(text[$0]) }
        }
    }
}
