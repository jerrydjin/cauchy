import Foundation

/// Deterministic normalization for model output.
enum AssistantResponseNormalizer {
    static func normalize(_ content: String) -> String {
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
        guard let regex = try? NSRegularExpression(pattern: #"\\\((.+?)\\\)"#, options: [.dotMatchesLineSeparators]) else {
            return text
        }
        return replaceMatches(in: text, regex: regex) { match, source in
            guard let range = Range(match.range(at: 1), in: source) else { return nil }
            return "$\(source[range].trimmingCharacters(in: .whitespacesAndNewlines))$"
        }
    }

    private static func replaceDisplayDelimiters(_ text: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: #"\\\[(.+?)\\\]"#, options: [.dotMatchesLineSeparators]) else {
            return text
        }
        return replaceMatches(in: text, regex: regex) { match, source in
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
