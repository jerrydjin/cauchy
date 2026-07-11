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
        // This runs on every streamed partial; skip the regex passes unless the
        // text can actually contain something the rules below rewrite.
        guard content.contains("\r") || content.contains("```")
            || content.contains("\\(") || content.contains("\\[") else {
            return content
        }

        var text = content
            .replacingOccurrences(of: "\r\n", with: "\n")

        text = stripCodeFences(text)
        text = replaceInlineDelimiters(text)
        text = replaceDisplayDelimiters(text)
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
