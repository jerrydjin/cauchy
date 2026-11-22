import Foundation

/// A narrow backstop for when a model still narrates Cauchy's pipeline.
///
/// The system prompt is what makes the reply sound like a professor. This
/// only removes a clause that is about the text layer ("in the extracted
/// text", "check the original page"). A formula that shares the sentence
/// stays. A sentence is dropped only when nothing but that narration is left,
/// and a citation marker on it is moved onto a sentence that remains.
enum AnswerVoice {
    /// Phrases that describe the prompt instead of the mathematics.
    static let bannedPhrases = [
        "extracted text",
        "extraction artifact",
        "supplied excerpts",
        "supplied excerpt",
        "surrounding context",
        "selected passage",
        "separating what appears",
        "check the original page",
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
        var kept: [String] = []
        var rescuedMarkers: [String] = []
        for piece in sentences(in: paragraph) {
            let stripped = stripMetaClauses(piece)
            if !hasContent(stripped) {
                rescuedMarkers.append(contentsOf: sourceMarkers(in: piece))
                continue
            }
            kept.append(stripped)
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

    /// Drops a comma-separated clause that is only pipeline talk. A clause
    /// that also names a formula keeps the formula and loses the talk.
    static func stripMetaClauses(_ sentence: String) -> String {
        let clauses = clauses(in: sentence)
        var kept: [String] = []
        for clause in clauses {
            guard containsBannedMeta(clause) else {
                kept.append(clause)
                continue
            }
            if carriesMathematics(clause) {
                let cleaned = removingBannedPhrases(clause)
                if hasContent(cleaned) { kept.append(cleaned) }
            }
        }
        var joined = kept.joined(separator: ", ")
        joined = joined.replacingOccurrences(
            of: #"\s{2,}"#,
            with: " ",
            options: .regularExpression
        )
        joined = joined.trimmingCharacters(in: .whitespacesAndNewlines)
        joined = joined.trimmingCharacters(in: CharacterSet(charactersIn: ",;"))
        joined = joined.trimmingCharacters(in: .whitespacesAndNewlines)
        if joined.isEmpty { return "" }
        if let first = joined.first, first.isLowercase {
            joined.replaceSubrange(joined.startIndex...joined.startIndex, with: String(first).uppercased())
        }
        let ended = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
        if let last = ended.last, ".!?".contains(last), joined.last.map({ !".!?".contains($0) }) ?? false {
            joined.append(last)
        }
        return joined
    }

    private static func removingBannedPhrases(_ text: String) -> String {
        var result = text
        let phrases = bannedPhrases.sorted { $0.count > $1.count }
        for phrase in phrases {
            while let range = result.range(of: phrase, options: .caseInsensitive) {
                var start = range.lowerBound
                let prefixes = [" in the ", " from the ", " of the ", " the "]
                for prefix in prefixes {
                    let startOffset = result.distance(from: result.startIndex, to: start)
                    guard startOffset >= prefix.count else { continue }
                    let prefixStart = result.index(start, offsetBy: -prefix.count)
                    if result[prefixStart..<start].lowercased() == prefix {
                        start = prefixStart
                        break
                    }
                }
                result.removeSubrange(start..<range.upperBound)
            }
        }
        result = result.replacingOccurrences(
            of: #"\s+([,.;:!?])"#,
            with: "$1",
            options: .regularExpression
        )
        result = result.replacingOccurrences(
            of: #"\s{2,}"#,
            with: " ",
            options: .regularExpression
        )
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// A formula, an equation, or a symbol with a digit. A citation marker
    /// such as [S1] is not mathematics, and neither is "the selected passage".
    private static func carriesMathematics(_ text: String) -> Bool {
        let withoutMarkers = text.replacingOccurrences(
            of: #"\[[A-Za-z]\d+\]"#,
            with: "",
            options: .regularExpression
        )
        if withoutMarkers.contains("$") || withoutMarkers.contains("\\") || withoutMarkers.contains("=") {
            return true
        }
        if withoutMarkers.range(of: #"\d"#, options: .regularExpression) != nil { return true }
        if withoutMarkers.range(of: #"[A-Za-z]\([^)]*\)"#, options: .regularExpression) != nil { return true }
        return false
    }

    private static func hasContent(_ text: String) -> Bool {
        text.contains { $0.isLetter || $0.isNumber }
    }

    /// Comma-separated pieces outside `$...$` and outside parentheses, so a
    /// comma inside B(z0, r) stays put. "so" after a comma starts its own
    /// piece, which is how "so check the original page" detaches.
    private static func clauses(in sentence: String) -> [String] {
        var pieces: [String] = []
        var current = ""
        var math = false
        var depth = 0
        var escaped = false
        var index = sentence.startIndex
        while index < sentence.endIndex {
            let character = sentence[index]
            if escaped {
                current.append(character)
                escaped = false
                index = sentence.index(after: index)
                continue
            }
            if character == "\\" {
                current.append(character)
                escaped = true
                index = sentence.index(after: index)
                continue
            }
            if character == "$" {
                math.toggle()
                current.append(character)
                index = sentence.index(after: index)
                continue
            }
            if !math {
                if character == "(" || character == "{" || character == "[" {
                    depth += 1
                } else if character == ")" || character == "}" || character == "]" {
                    depth = max(0, depth - 1)
                } else if depth == 0, character == "," || character == ";" {
                    let trimmed = current.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty { pieces.append(trimmed) }
                    current = ""
                    index = sentence.index(after: index)
                    continue
                }
            }
            current.append(character)
            index = sentence.index(after: index)
        }
        let tail = current.trimmingCharacters(in: .whitespacesAndNewlines)
        if !tail.isEmpty { pieces.append(tail) }
        return pieces
    }

    /// Splits on sentence boundaries outside `$...$`.
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
