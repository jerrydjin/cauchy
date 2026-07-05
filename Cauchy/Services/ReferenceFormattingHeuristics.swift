import Foundation

enum ReferenceFormattingHeuristics {
    /// Minimal cleanup for PDF-extracted text. Does not attempt LaTeX conversion.
    static func lightClean(_ rawBody: String) -> String {
        var text = rawBody.replacingOccurrences(of: "\r\n", with: "\n")
        if let regex = try? NSRegularExpression(pattern: #"[ \t]+"#) {
            text = regex.stringByReplacingMatches(
                in: text,
                range: NSRange(text.startIndex..., in: text),
                withTemplate: " "
            )
        }

        let lines = text
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }

        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Aggressive unicode-to-LaTeX conversion. Only for OCR paths — not reference previews.
    static func format(_ rawBody: String) -> String {
        let withSymbols = LaTeXFormatter.format(rawBody)
        return LaTeXNormalizer.normalizeForDisplay(withSymbols)
    }

    static func mathSegmentValidationScore(for text: String) -> (valid: Int, total: Int) {
        let segments = MessageContentParser.parse(text)
        var valid = 0
        var total = 0

        for segment in segments {
            switch segment {
            case .inlineMath(let latex), .displayMath(let latex):
                total += 1
                if LaTeXValidator.isValid(latex) {
                    valid += 1
                }
            case .text:
                continue
            }
        }

        return (valid, total)
    }

    static func isMostlyValidLaTeX(_ text: String) -> Bool {
        let score = mathSegmentValidationScore(for: text)
        guard score.total > 0 else { return true }
        return Double(score.valid) / Double(score.total) >= 0.5
    }
}
