import Foundation

enum AssistantResponseValidator {
    static func isDisplayReady(_ text: String) -> Bool {
        !hasUndelimitedLaTeX(text) && ReferenceFormattingHeuristics.isMostlyValidLaTeX(text)
    }

    /// True when a LaTeX command appears outside $...$ / $$...$$ blocks.
    static func hasUndelimitedLaTeX(_ text: String) -> Bool {
        var index = text.startIndex
        var inInline = false
        var inDisplay = false

        while index < text.endIndex {
            if text[index] == "$" {
                let next = text.index(after: index)
                if next < text.endIndex, text[next] == "$" {
                    inDisplay.toggle()
                    inInline = false
                    index = text.index(index, offsetBy: 2)
                    continue
                }
                if !inDisplay {
                    inInline.toggle()
                }
                index = next
                continue
            }

            if !inInline && !inDisplay && text[index] == "\\" {
                if hasLaTeXCommand(at: index, in: text) {
                    return true
                }
            }

            index = text.index(after: index)
        }

        return false
    }

    private static func hasLaTeXCommand(at index: String.Index, in text: String) -> Bool {
        guard index < text.endIndex, text[index] == "\\" else { return false }
        let after = text.index(after: index)
        guard after < text.endIndex else { return false }
        return text[after].isLetter || text[after] == "|" || text[after] == "(" || text[after] == "["
    }
}
