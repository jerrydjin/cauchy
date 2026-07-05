import Foundation

enum LaTeXNormalizer {
    static func normalizeForDisplay(_ content: String) -> String {
        AssistantResponseNormalizer.normalize(content)
    }

    static func needsRichRendering(_ content: String) -> Bool {
        let normalized = normalizeForDisplay(content)
        if normalized.contains("$$") || normalized.contains("$") {
            return true
        }
        return normalized
            .split(separator: "\n", omittingEmptySubsequences: false)
            .contains { isLikelyMathLine(String($0)) }
    }

    static func isLikelyMathLine(_ line: String) -> Bool {
        isBareLaTeXLine(line) || isBareLaTeXContent(line)
    }

    /// A line that is entirely undelimited LaTeX (no prose, no $ delimiters).
    static func isBareLaTeXLine(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !trimmed.contains("$") else { return false }
        return isBareLaTeXContent(trimmed)
    }

    /// Undelimited content that is clearly LaTeX rather than prose.
    static func isBareLaTeXContent(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains("$") else { return false }

        let commandCount = countLaTeXCommands(in: trimmed)
        guard commandCount > 0 else { return false }

        let strongSignals = [
            "\\left", "\\right", "\\frac", "\\leq", "\\geq", "\\le", "\\ge",
            "\\epsilon", "\\varepsilon", "\\delta", "\\lambda", "\\sum", "\\int",
            "\\cdot", "\\times", "\\infty", "\\in", "\\subset",
        ]
        if strongSignals.contains(where: trimmed.contains) {
            return true
        }

        return commandCount >= 2
    }

    /// Wrap undelimited LaTeX lines and trailing math spans in $ / $$ delimiters.
    static func wrapBareMath(_ text: String) -> String {
        text
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { wrapBareMathInLine(String($0)) }
            .joined(separator: "\n")
    }

    static func wrapBareMathInLine(_ line: String) -> String {
        guard !line.contains("$") else { return line }

        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return line }

        if isBareLaTeXLine(trimmed) {
            return wrapAsMath(trimmed, display: shouldRenderAsDisplayMath(trimmed))
        }

        guard let mathStart = bareMathStart(in: line) else { return line }
        let prefix = line[..<mathStart]
        let suffix = line[mathStart...].trimmingCharacters(in: .whitespaces)
        guard isBareLaTeXContent(suffix) else { return line }

        let wrapped = wrapAsMath(suffix, display: shouldRenderAsDisplayMath(suffix))
        return String(prefix) + wrapped
    }

    static func shouldRenderAsDisplayMath(_ latex: String) -> Bool {
        let trimmed = latex.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        let displayCommands = [
            "\\frac", "\\dfrac", "\\tfrac", "\\sum", "\\int", "\\prod", "\\lim",
            "\\left", "\\right", "\\begin", "\\end", "\\matrix", "\\cases", "\\aligned",
        ]
        if displayCommands.contains(where: { trimmed.contains($0) }) {
            return true
        }
        if trimmed.count > 56 { return true }
        if trimmed.filter({ $0 == "=" }).count >= 2 { return true }
        return trimmed.contains("\\\\")
    }

    private static func wrapAsMath(_ latex: String, display: Bool) -> String {
        display ? "$$\(latex)$$" : "$\(latex)$"
    }

    private static func bareMathStart(in line: String) -> String.Index? {
        let strong = [
            "\\left", "\\frac", "\\leq", "\\geq", "\\le", "\\ge",
            "\\epsilon", "\\varepsilon", "\\delta", "\\sum", "\\int",
        ]
        var earliest: String.Index?
        for command in strong {
            if let range = line.range(of: command) {
                if earliest == nil || range.lowerBound < earliest! {
                    earliest = range.lowerBound
                }
            }
        }
        if let earliest { return earliest }

        var index = line.startIndex
        while index < line.endIndex {
            if line[index] == "\\", hasLaTeXCommand(at: index, in: line) {
                return index
            }
            index = line.index(after: index)
        }
        return nil
    }

    private static func countLaTeXCommands(in text: String) -> Int {
        var count = 0
        var index = text.startIndex
        while index < text.endIndex {
            if text[index] == "\\", hasLaTeXCommand(at: index, in: text) {
                count += 1
            }
            index = text.index(after: index)
        }
        return count
    }

    private static func hasLaTeXCommand(at index: String.Index, in text: String) -> Bool {
        guard index < text.endIndex, text[index] == "\\" else { return false }
        let after = text.index(after: index)
        guard after < text.endIndex else { return false }
        return text[after].isLetter || text[after] == "|" || text[after] == "(" || text[after] == "["
    }
}
