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

    /// Named results in `text` that exist in the open document. A cited number
    /// with no indexed result is omitted, so the reader never gets a link to a
    /// theorem the notes do not contain. Detection itself stays in
    /// `ReferenceDetector`; this only decides which matches may be linked.
    static func linkableReferences(in text: String, known: Set<ReferenceKey>) -> [DetectedReferenceMatch] {
        guard !known.isEmpty else { return [] }
        var accepted: [DetectedReferenceMatch] = []
        var covered: [Range<String.Index>] = []
        for match in ReferenceDetector.allReferences(in: text) {
            guard known.contains(match.reference.key) else { continue }
            if covered.contains(where: { rangesOverlap($0, match.range) }) { continue }
            accepted.append(match)
            covered.append(match.range)
        }
        return accepted
    }

    /// Citations the model named that are not results in the document. These
    /// stay ordinary prose.
    static func unlinkableReferences(in text: String, known: Set<ReferenceKey>) -> [DetectedReference] {
        var rejected: [DetectedReference] = []
        var seen = Set<ReferenceKey>()
        for match in ReferenceDetector.allReferences(in: text) {
            let key = match.reference.key
            guard !known.contains(key), seen.insert(key).inserted else { continue }
            rejected.append(match.reference)
        }
        return rejected
    }

    private static func rangesOverlap(_ lhs: Range<String.Index>, _ rhs: Range<String.Index>) -> Bool {
        lhs.lowerBound < rhs.upperBound && rhs.lowerBound < lhs.upperBound
    }

    private static func hasLaTeXCommand(at index: String.Index, in text: String) -> Bool {
        guard index < text.endIndex, text[index] == "\\" else { return false }
        let after = text.index(after: index)
        guard after < text.endIndex else { return false }
        return text[after].isLetter || text[after] == "|" || text[after] == "(" || text[after] == "["
    }
}
