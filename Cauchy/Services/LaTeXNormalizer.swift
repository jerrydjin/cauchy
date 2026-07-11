import Foundation

enum LaTeXNormalizer {
    static func normalizeForDisplay(_ content: String) -> String {
        AssistantResponseNormalizer.normalize(content)
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
