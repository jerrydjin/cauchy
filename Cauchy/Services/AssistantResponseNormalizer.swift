import Foundation

/// Deterministic normalization for model output.
enum AssistantResponseNormalizer {
    private static let inlineDelimiterRegex = try! NSRegularExpression(
        pattern: #"\\\((.+?)\\\)"#,
        options: [.dotMatchesLineSeparators]
    )
    private static let displayDelimiterRegex = try! NSRegularExpression(
        pattern: #"\\\[(.+?)\\\]"#,
        options: [.dotMatchesLineSeparators]
    )

    static func normalize(_ content: String) -> String {
        // This runs on every streamed partial; skip the passes below unless the
        // text can actually contain something they rewrite. A lone backslash is
        // the cheapest test that covers both the \( \[ delimiters and any bare
        // LaTeX command that needs wrapping.
        guard content.contains("\r") || content.contains("```") || content.contains("\\") else {
            return content
        }

        var text = content
            .replacingOccurrences(of: "\r\n", with: "\n")

        text = stripCodeFences(text)
        text = replaceInlineDelimiters(text)
        text = replaceDisplayDelimiters(text)
        // Last, so it only ever sees what the delimiter passes left behind.
        text = LaTeXNormalizer.wrapBareMath(text)
        return text
    }

    private static func stripCodeFences(_ text: String) -> String {
        text
            .replacingOccurrences(of: "```latex", with: "")
            .replacingOccurrences(of: "```math", with: "")
            .replacingOccurrences(of: "```", with: "")
    }

    private static func replaceInlineDelimiters(_ text: String) -> String {
        replaceMatches(in: text, regex: inlineDelimiterRegex) { match, source in
            guard let range = Range(match.range(at: 1), in: source) else { return nil }
            return "$\(source[range].trimmingCharacters(in: .whitespacesAndNewlines))$"
        }
    }

    private static func replaceDisplayDelimiters(_ text: String) -> String {
        replaceMatches(in: text, regex: displayDelimiterRegex) { match, source in
            guard let range = Range(match.range(at: 1), in: source) else { return nil }
            return "\n$$\(source[range].trimmingCharacters(in: .whitespacesAndNewlines))$$\n"
        }
    }

    private static func replaceMatches(
        in text: String,
        regex: NSRegularExpression,
        transform: (NSTextCheckingResult, String) -> String?
    ) -> String {
        let nsRange = NSRange(text.startIndex..., in: text)
        let matches = regex.matches(in: text, range: nsRange).reversed()
        var output = text
        for match in matches {
            guard let fullRange = Range(match.range, in: output),
                  let replacement = transform(match, output) else { continue }
            output.replaceSubrange(fullRange, with: replacement)
        }
        return output
    }
}

/// Parses the hidden evidence-boundary trailer required by the reading prompt.
/// Invalid or missing trailers never inherit a trustworthy-looking default.
enum AssistantAnswerBoundary {
    struct Parsed: Equatable, Sendable {
        let content: String
        let basis: AnswerBasis
    }

    private static let validTrailer = try! NSRegularExpression(
        pattern: #"(?is)\s*\[\[CAUCHY_BASIS:\s*(PDF|MIXED|INSUFFICIENT)\s*\]\]\s*$"#
    )

    static func parse(_ text: String) -> Parsed {
        let fullRange = NSRange(text.startIndex..., in: text)
        if let match = validTrailer.firstMatch(in: text, range: fullRange),
           let markerRange = Range(match.range, in: text),
           let valueRange = Range(match.range(at: 1), in: text),
           let basis = AnswerBasis(rawValue: text[valueRange].lowercased()) {
            return Parsed(
                content: String(text[..<markerRange.lowerBound])
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                basis: basis
            )
        }
        return Parsed(content: displayContent(text), basis: .unverified)
    }

    /// Hides a complete or still-streaming control trailer from the reader.
    /// The final parser still requires the exact closed marker before trusting
    /// its value.
    static func displayContent(_ text: String) -> String {
        guard let range = text.range(
            of: "[[CAUCHY_BASIS:",
            options: [.caseInsensitive]
        ) else { return text }
        return String(text[..<range.lowerBound])
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// Checks only that answer citation IDs exist in the PDF locations Cauchy
/// actually supplied. A valid ID is not semantic entailment or full coverage.
enum AnswerCitationAudit {
    struct Result: Equatable, Sendable {
        let status: AnswerCitationStatus
        let citedSourceIDs: [String]
    }

    private static let sourceIDPattern = try! NSRegularExpression(
        pattern: #"\[([A-Z]\d+)\]"#,
        options: [.caseInsensitive]
    )

    private static let numberedHeading = try! NSRegularExpression(
        pattern: #"^\d+(?:\.\d+)*\.\s+[^.!?]{1,80}$"#
    )

    static func evaluate(_ content: String, sources: [AnswerSourceAnchor]) -> Result {
        let allowed = Set(sources.compactMap(\.sourceID))
        let range = NSRange(content.startIndex..., in: content)
        let ids = sourceIDPattern.matches(in: content, range: range).compactMap { match -> String? in
            guard let valueRange = Range(match.range(at: 1), in: content) else { return nil }
            return content[valueRange].uppercased()
        }
        var cited: [String] = []
        var seen: Set<String> = []
        var invalid = false
        for id in ids {
            guard allowed.contains(id) else {
                invalid = true
                continue
            }
            if seen.insert(id).inserted { cited.append(id) }
        }
        let status: AnswerCitationStatus
        if invalid {
            status = .invalidID
        } else if cited.isEmpty {
            status = .noResolvableCitation
        } else if materialSpans(in: content).contains(where: { span in
            let spanRange = NSRange(span.startIndex..., in: span)
            return !sourceIDPattern.matches(in: span, range: spanRange).contains { match in
                guard let valueRange = Range(match.range(at: 1), in: span) else { return false }
                return allowed.contains(span[valueRange].uppercased())
            }
        }) {
            status = .uncitedPassage
        } else {
            status = .idsResolve
        }
        return Result(status: status, citedSourceIDs: cited)
    }

    /// A conservative format check: each prose paragraph (or separate list
    /// item) must have a valid link. It is not a semantic claim segmenter.
    private static func materialSpans(in content: String) -> [String] {
        content.components(separatedBy: "\n\n").flatMap { paragraph -> [String] in
            let trimmed = paragraph.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return [] }
            let lines = trimmed.components(separatedBy: .newlines)
            let hasListItems = lines.contains { line in
                let start = line.trimmingCharacters(in: .whitespaces)
                return start.hasPrefix("- ") || start.hasPrefix("• ")
            }
            return hasListItems ? lines : [trimmed]
        }.filter { span in
            let trimmed = span.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return false }
            if trimmed.hasSuffix(":"), trimmed.count < 80 { return false }
            if numberedHeading.firstMatch(
                in: trimmed,
                range: NSRange(trimmed.startIndex..., in: trimmed)
            ) != nil { return false }
            return trimmed.contains { $0.isLetter || $0.isNumber }
        }
    }
}
