import Foundation

enum LaTeXNormalizer {
    static func normalizeForDisplay(_ content: String) -> String {
        AssistantResponseNormalizer.normalize(content)
    }

    /// True when a line is entirely undelimited LaTeX — no prose, no `$`.
    static func isBareLaTeXLine(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !trimmed.contains("$") else { return false }
        return isBareLaTeXContent(trimmed)
    }

    /// Undelimited content that is clearly maths rather than prose. One strong
    /// command is enough; otherwise two commands, so an ordinary sentence that
    /// happens to contain a stray backslash is left alone.
    static func isBareLaTeXContent(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains("$") else { return false }

        let commandCount = countLaTeXCommands(in: trimmed)
        guard commandCount > 0 else { return false }

        if strongSignals.contains(where: trimmed.contains) { return true }
        return commandCount >= 2
    }

    /// Wraps undelimited LaTeX in `$`/`$$` so the math engine renders it
    /// instead of the reader seeing raw commands. Models are asked to delimit
    /// their own maths, but they do not always do it, and an unwrapped line is
    /// the one failure the reader cannot work around.
    static func wrapBareMath(_ text: String) -> String {
        guard text.contains("\\") else { return text }
        return text
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

        // A line that starts as prose and runs into maths — "so we get
        // \left| x \right| < \epsilon" — keeps its prose and wraps the rest.
        guard let mathStart = bareMathStart(in: line) else { return line }
        let prefix = line[..<mathStart]
        let suffix = line[mathStart...].trimmingCharacters(in: .whitespaces)
        guard isBareLaTeXContent(suffix) else { return line }

        return String(prefix) + wrapAsMath(suffix, display: shouldRenderAsDisplayMath(suffix))
    }

    private static let strongSignals = [
        "\\left", "\\right", "\\frac", "\\leq", "\\geq", "\\le", "\\ge",
        "\\epsilon", "\\varepsilon", "\\delta", "\\lambda", "\\sum", "\\int",
        "\\cdot", "\\times", "\\infty", "\\in", "\\subset",
    ]

    private static func wrapAsMath(_ latex: String, display: Bool) -> String {
        display ? "$$\(latex)$$" : "$\(latex)$"
    }

    private static func bareMathStart(in line: String) -> String.Index? {
        var earliest: String.Index?
        for command in strongSignals {
            if let range = line.range(of: command),
               earliest == nil || range.lowerBound < earliest! {
                earliest = range.lowerBound
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
}
