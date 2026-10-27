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

    /// Delimits math that `wrapBareMath` leaves as prose.
    ///
    /// `wrapBareMath` skips a line as soon as it contains `$`, so
    /// `where $n$ satisfies \frac{1}{2}` draws the fraction as `Text`. A lone
    /// `\gamma` is one weak command, so it is not a "bare line" either.
    /// `\begin{align}` split across lines is wrapped one line at a time and
    /// SwiftMath then rejects the fragment. Those runs are delimited here,
    /// outside existing `$` / `$$`, before the whole-line pass.
    static func delimitLooseMath(_ text: String) -> String {
        guard text.contains("\\") else { return text }
        return wrapLooseCommands(wrapEnvironments(text))
    }

    // MARK: - Environments

    private static func wrapEnvironments(_ text: String) -> String {
        var output = ""
        var index = text.startIndex
        while index < text.endIndex {
            if text[index] == "$" {
                let end = endOfDollarSpan(in: text, from: index) ?? text.endIndex
                output.append(contentsOf: text[index..<end])
                index = end
                continue
            }
            if let environment = environmentSpan(in: text, from: index) {
                output.append("$$")
                output.append(contentsOf: text[environment])
                output.append("$$")
                index = environment.upperBound
                continue
            }
            output.append(text[index])
            index = text.index(after: index)
        }
        return output
    }

    /// `\begin{name} … \end{name}` starting at `index`, when `index` is the backslash.
    private static func environmentSpan(in text: String, from index: String.Index) -> Range<String.Index>? {
        guard text[index...].hasPrefix("\\begin{") else { return nil }
        let nameStart = text.index(index, offsetBy: "\\begin{".count)
        guard let nameEnd = text[nameStart...].firstIndex(of: "}") else { return nil }
        let name = String(text[nameStart..<nameEnd])
        guard isEnvironmentName(name) else { return nil }
        var depth = 1
        var cursor = text.index(after: nameEnd)
        let beginToken = "\\begin{\(name)}"
        let endToken = "\\end{\(name)}"
        while cursor < text.endIndex {
            if text[cursor...].hasPrefix(beginToken) {
                depth += 1
                cursor = text.index(cursor, offsetBy: beginToken.count)
                continue
            }
            if text[cursor...].hasPrefix(endToken) {
                depth -= 1
                let end = text.index(cursor, offsetBy: endToken.count)
                if depth == 0 { return index..<end }
                cursor = end
                continue
            }
            cursor = text.index(after: cursor)
        }
        return nil
    }

    private static func isEnvironmentName(_ name: String) -> Bool {
        guard !name.isEmpty else { return false }
        return name.allSatisfy { $0.isLetter || $0 == "*" }
    }

    // MARK: - Loose commands

    private static func wrapLooseCommands(_ text: String) -> String {
        let protected = dollarRanges(in: text)
        var spans: [LooseCommandSpan] = []
        var index = text.startIndex
        while index < text.endIndex {
            if rangeContains(protected, index) {
                index = text.index(after: index)
                continue
            }
            if text[index] == "\\", let span = looseSpan(in: text, at: index, protected: protected) {
                spans.append(span)
                index = span.range.upperBound
                continue
            }
            index = text.index(after: index)
        }
        let math = mergeConnectors(spans, in: text).filter(\.seed)
        return apply(math.map(\.range), to: text)
    }

    /// A command SwiftMath should see. A lone `\gamma` qualifies. `C:\Users`
    /// does not: an uppercase word with no brace is prose, unless it sits in
    /// the same expression as a real math command (`\Bigl( \frac{1}{2} \Bigr)`).
    private struct LooseCommandSpan {
        var range: Range<String.Index>
        var seed: Bool
    }

    private static let uppercaseMathCommands: Set<String> = [
        "Gamma", "Delta", "Theta", "Lambda", "Xi", "Pi", "Sigma", "Upsilon", "Phi", "Psi", "Omega",
        "Re", "Im", "Pr",
        "Leftarrow", "Rightarrow", "Leftrightarrow",
        "Longleftarrow", "Longrightarrow", "Longleftrightarrow",
        "Big", "Bigg", "Bigl", "Bigr", "Biggl", "Biggr",
    ]

    private static func isMathSeed(name: String, atom: Substring) -> Bool {
        if atom.contains("{") || atom.contains("^") || atom.contains("_") { return true }
        if uppercaseMathCommands.contains(name) { return true }
        return name.allSatisfy { $0.isLetter && $0.isLowercase }
    }

    private static func looseSpan(
        in text: String,
        at index: String.Index,
        protected: [Range<String.Index>]
    ) -> LooseCommandSpan? {
        guard let commandEnd = endOfCommand(in: text, from: index) else { return nil }
        let name = String(text[text.index(after: index)..<commandEnd])
        // `\n` / `\t` are statement-unescape leftovers, not math commands.
        // `\begin` / `\end` are handled with their environment, or left alone
        // when the environment never closed. `\\` is a row break, not an atom.
        if name == "n" || name == "t" || name == "begin" || name == "end" || name == "\\"
            || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return nil
        }
        let atomEnd = endOfAtom(in: text, from: index, protected: protected)
        let seed = isMathSeed(name: name, atom: text[index..<atomEnd])
        var end = atomEnd
        let start = expandBackward(in: text, from: index, protected: protected)
        end = extendThroughOpenGroups(in: text, start: start, end: end, protected: protected)
        guard start < end else { return nil }
        return LooseCommandSpan(range: start..<end, seed: seed)
    }

    private static func endOfCommand(in text: String, from index: String.Index) -> String.Index? {
        guard text[index] == "\\" else { return nil }
        var cursor = text.index(after: index)
        guard cursor < text.endIndex else { return nil }
        if text[cursor].isLetter {
            var previous = text[cursor]
            cursor = text.index(after: cursor)
            while cursor < text.endIndex, text[cursor].isLetter {
                // `\nMoreover` is a newline escape plus a word, not a command.
                if previous.isLowercase && text[cursor].isUppercase { break }
                previous = text[cursor]
                cursor = text.index(after: cursor)
            }
            return cursor
        }
        return text.index(after: cursor)
    }

    private static func endOfAtom(
        in text: String,
        from index: String.Index,
        protected: [Range<String.Index>]
    ) -> String.Index {
        guard let commandEnd = endOfCommand(in: text, from: index) else {
            return text.index(after: index)
        }
        let name = String(text[text.index(after: index)..<commandEnd])
        if name == "left" {
            return endAfterMatchingRight(in: text, from: commandEnd, protected: protected)
        }
        var cursor = commandEnd
        while cursor < text.endIndex, !rangeContains(protected, cursor) {
            if text[cursor] == "{" {
                cursor = endOfGroup(in: text, open: cursor)
                continue
            }
            if text[cursor] == "^" || text[cursor] == "_" {
                cursor = text.index(after: cursor)
                guard cursor < text.endIndex else { break }
                if text[cursor] == "{" {
                    cursor = endOfGroup(in: text, open: cursor)
                } else if text[cursor] == "\\" {
                    cursor = endOfAtom(in: text, from: cursor, protected: protected)
                } else {
                    cursor = text.index(after: cursor)
                }
                continue
            }
            break
        }
        return cursor
    }

    private static func endAfterMatchingRight(
        in text: String,
        from index: String.Index,
        protected: [Range<String.Index>]
    ) -> String.Index {
        var depth = 1
        var cursor = index
        while cursor < text.endIndex, !rangeContains(protected, cursor) {
            if text[cursor] == "\\", let commandEnd = endOfCommand(in: text, from: cursor) {
                let name = String(text[text.index(after: cursor)..<commandEnd])
                if name == "left" {
                    depth += 1
                    cursor = commandEnd
                    continue
                }
                if name == "right" {
                    depth -= 1
                    cursor = commandEnd
                    if depth == 0 {
                        if cursor < text.endIndex, text[cursor] == "\\" {
                            return endOfCommand(in: text, from: cursor) ?? text.index(after: cursor)
                        }
                        if cursor < text.endIndex { return text.index(after: cursor) }
                        return cursor
                    }
                    continue
                }
                cursor = commandEnd
                continue
            }
            if text[cursor] == "\n" { return cursor }
            cursor = text.index(after: cursor)
        }
        return cursor
    }

    private static func expandBackward(
        in text: String,
        from index: String.Index,
        protected: [Range<String.Index>]
    ) -> String.Index {
        var start = index
        while start > text.startIndex {
            let previous = text.index(before: start)
            if text[previous] == "\n" || text[previous] == "$" || rangeContains(protected, previous) {
                break
            }
            if text[previous] == "{" {
                var groupStart = previous
                if groupStart > text.startIndex {
                    let before = text.index(before: groupStart)
                    if text[before] == "^" || text[before] == "_" {
                        groupStart = before
                        groupStart = includeAdjacentBase(in: text, before: groupStart, protected: protected)
                    }
                }
                start = groupStart
                continue
            }
            if text[previous] == "}" {
                guard let open = matchingOpenBrace(in: text, closing: previous) else { break }
                if rangeContains(protected, open) { break }
                var groupStart = open
                if groupStart > text.startIndex {
                    let before = text.index(before: groupStart)
                    if text[before] == "^" || text[before] == "_" {
                        groupStart = before
                        groupStart = includeAdjacentBase(in: text, before: groupStart, protected: protected)
                    }
                }
                start = groupStart
                continue
            }
            if "^_0123456789()|=+-*/<>.,".contains(text[previous]) {
                start = previous
                continue
            }
            if text[previous].isLetter || text[previous].isNumber {
                let base = includeAdjacentBase(in: text, before: start, protected: protected)
                if base >= start { break }
                start = base
                continue
            }
            break
        }
        return start
    }

    /// The letter/number run touching `before` (the index just after the run).
    private static func includeAdjacentBase(
        in text: String,
        before index: String.Index,
        protected: [Range<String.Index>]
    ) -> String.Index {
        var start = index
        while start > text.startIndex {
            let previous = text.index(before: start)
            if text[previous] == "\n" || rangeContains(protected, previous) { break }
            if text[previous].isLetter || text[previous].isNumber {
                start = previous
                continue
            }
            break
        }
        return start
    }

    private static func extendThroughOpenGroups(
        in text: String,
        start: String.Index,
        end: String.Index,
        protected: [Range<String.Index>]
    ) -> String.Index {
        var depth = 0
        var cursor = start
        var end = end
        while cursor < end {
            if text[cursor] == "{" { depth += 1 }
            if text[cursor] == "}" { depth = max(0, depth - 1) }
            cursor = text.index(after: cursor)
        }
        while depth > 0, end < text.endIndex, text[end] != "\n", !rangeContains(protected, end) {
            if text[end] == "{" { depth += 1 }
            if text[end] == "}" { depth -= 1 }
            end = text.index(after: end)
        }
        return end
    }

    private static func mergeConnectors(
        _ spans: [LooseCommandSpan],
        in text: String
    ) -> [LooseCommandSpan] {
        var merged: [LooseCommandSpan] = []
        for span in spans {
            guard let last = merged.last else {
                merged.append(span)
                continue
            }
            if span.range.lowerBound < last.range.upperBound {
                merged[merged.count - 1] = LooseCommandSpan(
                    range: last.range.lowerBound..<max(last.range.upperBound, span.range.upperBound),
                    seed: last.seed || span.seed
                )
                continue
            }
            let gap = text[last.range.upperBound..<span.range.lowerBound]
            if isMathConnector(gap) {
                merged[merged.count - 1] = LooseCommandSpan(
                    range: last.range.lowerBound..<span.range.upperBound,
                    seed: last.seed || span.seed
                )
            } else {
                merged.append(span)
            }
        }
        return merged
    }

    private static func isMathConnector(_ gap: Substring) -> Bool {
        guard !gap.isEmpty, !gap.contains("\n") else { return gap.isEmpty }
        return gap.allSatisfy { character in
            character.isWhitespace || "=+-*/<>|&(),.".contains(character)
        }
    }

    private static func apply(_ spans: [Range<String.Index>], to text: String) -> String {
        var output = ""
        var index = text.startIndex
        for span in spans {
            guard span.lowerBound >= index else { continue }
            output.append(contentsOf: text[index..<span.lowerBound])
            let chunk = String(text[span])
            if chunk.hasPrefix("\\begin") || shouldRenderAsDisplayMath(chunk) {
                output.append("$$")
                output.append(chunk)
                output.append("$$")
            } else {
                output.append("$")
                output.append(chunk)
                output.append("$")
            }
            index = span.upperBound
        }
        output.append(contentsOf: text[index...])
        return output
    }

    // MARK: - Dollars and braces

    private static func dollarRanges(in text: String) -> [Range<String.Index>] {
        var ranges: [Range<String.Index>] = []
        var index = text.startIndex
        while index < text.endIndex {
            guard text[index] == "$" else {
                index = text.index(after: index)
                continue
            }
            guard let end = endOfDollarSpan(in: text, from: index) else {
                index = text.index(after: index)
                continue
            }
            ranges.append(index..<end)
            index = end
        }
        return ranges
    }

    private static func endOfDollarSpan(in text: String, from index: String.Index) -> String.Index? {
        guard text[index] == "$" else { return nil }
        let next = text.index(after: index)
        let display = next < text.endIndex && text[next] == "$"
        let tokenCount = display ? 2 : 1
        let search = text.index(index, offsetBy: tokenCount)
        guard search <= text.endIndex else { return nil }
        let token = display ? "$$" : "$"
        guard let close = text[search...].range(of: token) else { return nil }
        return text.index(close.lowerBound, offsetBy: tokenCount)
    }

    private static func rangeContains(_ ranges: [Range<String.Index>], _ index: String.Index) -> Bool {
        ranges.contains { $0.contains(index) }
    }

    private static func endOfGroup(in text: String, open: String.Index) -> String.Index {
        guard open < text.endIndex, text[open] == "{" else { return open }
        var depth = 0
        var cursor = open
        while cursor < text.endIndex {
            if text[cursor] == "{" { depth += 1 }
            if text[cursor] == "}" {
                depth -= 1
                if depth == 0 { return text.index(after: cursor) }
            }
            if text[cursor] == "\n", depth > 8 { break }
            cursor = text.index(after: cursor)
        }
        return cursor
    }

    private static func matchingOpenBrace(in text: String, closing: String.Index) -> String.Index? {
        guard text[closing] == "}" else { return nil }
        var depth = 0
        var cursor = closing
        while true {
            if text[cursor] == "}" { depth += 1 }
            if text[cursor] == "{" {
                depth -= 1
                if depth == 0 { return cursor }
            }
            if cursor == text.startIndex { return nil }
            cursor = text.index(before: cursor)
        }
    }
}
