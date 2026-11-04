import SwiftUI

/// The reference card uses the answer bubble's fill, corner radius, and
/// padding. The statement column and a figure block both go through this,
/// and the designer snapshot renders the column.
enum ReferencePreviewBlockChrome {
    static func padded<Content: View>(_ content: Content) -> some View {
        content
            .padding(.horizontal, ConversationChrome.answerPaddingH)
            .padding(.vertical, ConversationChrome.answerPaddingV)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                ContentSurface.bubble,
                in: RoundedRectangle(cornerRadius: ConversationChrome.bubbleCornerRadius)
            )
    }
}

/// Secondary heading on the reference card. Kind and number, plus a
/// parenthetical name only when that name is not a repeat of the label.
struct ReferencePreviewHeading: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Typeset statement for one reference. The card scrolls this. The designer
/// snapshot renders it directly, because ImageRenderer skips a ScrollView.
struct ReferencePreviewStatementColumn: View {
    let heading: String
    let statement: String
    var pageIndexes: [Int] = []
    var onOpenPage: (Int) -> Void = { _ in }

    var body: some View {
        ReferencePreviewBlockChrome.padded(
            VStack(alignment: .leading, spacing: ConversationChrome.answerSourcesGap) {
                ReferencePreviewHeading(text: heading)
                ReadingBlockCard(displayBody: statement)
                if !pageIndexes.isEmpty {
                    ReferenceSourcePills(pageIndexes: pageIndexes, onOpen: onOpenPage)
                }
            }
        )
    }
}

/// One source page under the statement. Outlined like a follow-up pill, with
/// the page number in the link tint. Tapping jumps to that page.
struct ReferenceSourcePills: View {
    var pageIndexes: [Int]
    var onOpen: (Int) -> Void

    var body: some View {
        HStack(alignment: .center, spacing: ConversationChrome.answerFollowUpSpacing) {
            ForEach(pageIndexes, id: \.self) { pageIndex in
                ReferenceSourcePill(pageIndex: pageIndex) {
                    onOpen(pageIndex)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ReferenceSourcePill: View {
    var pageIndex: Int
    var onOpen: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: onOpen) {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                CitationLinkText.tinted("\(pageIndex + 1)", underlined: isHovered)
                Text(Image(systemName: "arrow.up.right"))
                    .font(.caption)
                    .foregroundStyle(CitationChrome.tint)
                    .accessibilityHidden(true)
            }
            .font(.caption)
            .padding(.horizontal, ConversationChrome.answerFollowUpPaddingH)
            .padding(.vertical, ConversationChrome.answerFollowUpPaddingV)
            .frame(minHeight: 28)
            .background {
                Capsule()
                    .strokeBorder(Color.primary.opacity(0.22), lineWidth: 1)
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .fixedSize()
        .citationLinkHover($isHovered)
        .accessibilityLabel(CitationPageLabel.voiceOver(
            firstPageIndex: pageIndex,
            lastPageIndex: pageIndex
        ))
    }
}

/// Plain-text maths in a reference statement, turned into the `$…$` the
/// answer renderer already typesets. Delimited maths is left alone. A
/// superscript becomes a real superscript, and an arrow keeps the space
/// TeX puts around `\to`.
enum ReferenceCardMath {
    static func typeset(_ text: String) -> String {
        guard !text.isEmpty else { return text }
        var output = ""
        var index = text.startIndex
        while index < text.endIndex {
            if text[index] == "$",
               let end = endOfDollarSpan(in: text, from: index),
               end > text.index(after: index) {
                output.append(contentsOf: text[index..<end])
                index = end
                continue
            }
            var plainEnd = index
            while plainEnd < text.endIndex {
                if text[plainEnd] == "$", endOfDollarSpan(in: text, from: plainEnd) != nil {
                    break
                }
                plainEnd = text.index(after: plainEnd)
            }
            if plainEnd > index {
                output.append(typesetPlain(String(text[index..<plainEnd])))
            }
            index = plainEnd
        }
        return output
    }

    private static func typesetPlain(_ text: String) -> String {
        replaceArrows(replaceScripts(replaceInverses(text)))
    }

    private static let inversePattern = try! NSRegularExpression(
        pattern: #"(?<![A-Za-z])([A-Za-z])[−\-–](\d+)(\([A-Za-z0-9,]+\))"#
    )

    private static func replaceInverses(_ text: String) -> String {
        let matches = inversePattern.matches(
            in: text,
            range: NSRange(text.startIndex..., in: text)
        )
        var result = text
        for match in matches.reversed() {
            guard match.numberOfRanges == 4,
                  let full = Range(match.range, in: result),
                  let letter = Range(match.range(at: 1), in: result),
                  let digits = Range(match.range(at: 2), in: result),
                  let paren = Range(match.range(at: 3), in: result) else { continue }
            let replacement = "$\(result[letter])^{-\(result[digits])}\(result[paren])$"
            result.replaceSubrange(full, with: replacement)
        }
        return result
    }

    private static let superscripts: [Character: Character] = [
        "⁰": "0", "¹": "1", "²": "2", "³": "3", "⁴": "4",
        "⁵": "5", "⁶": "6", "⁷": "7", "⁸": "8", "⁹": "9",
        "⁺": "+", "⁻": "-", "⁼": "=", "⁽": "(", "⁾": ")",
        "ⁿ": "n", "ⁱ": "i",
    ]

    private static let subscripts: [Character: Character] = [
        "₀": "0", "₁": "1", "₂": "2", "₃": "3", "₄": "4",
        "₅": "5", "₆": "6", "₇": "7", "₈": "8", "₉": "9",
        "₊": "+", "₋": "-", "₌": "=", "₍": "(", "₎": ")",
    ]

    private static func replaceScripts(_ text: String) -> String {
        var output = ""
        var index = text.startIndex
        while index < text.endIndex {
            if text[index] == "$", let end = endOfDollarSpan(in: text, from: index) {
                output.append(contentsOf: text[index..<end])
                index = end
                continue
            }
            let character = text[index]
            let isSuper = superscripts[character] != nil
            let isSub = subscripts[character] != nil
            guard isSuper || isSub else {
                output.append(character)
                index = text.index(after: index)
                continue
            }

            var superscript = ""
            var subscriptRun = ""
            var cursor = index
            if isSuper {
                while cursor < text.endIndex, let mapped = superscripts[text[cursor]] {
                    superscript.append(mapped)
                    cursor = text.index(after: cursor)
                }
            } else {
                while cursor < text.endIndex, let mapped = subscripts[text[cursor]] {
                    subscriptRun.append(mapped)
                    cursor = text.index(after: cursor)
                }
            }

            let (base, baseCount) = trailingBase(of: output)
            if baseCount > 0 {
                output.removeLast(baseCount)
            }
            var group = base
            if !subscriptRun.isEmpty { group += "_{\(subscriptRun)}" }
            if !superscript.isEmpty { group += "^{\(superscript)}" }
            if let paren = simpleParen(in: text, at: cursor) {
                group += String(text[paren])
                cursor = paren.upperBound
            }
            output.append("$\(group)$")
            index = cursor
        }
        return output
    }

    private static func trailingBase(of output: String) -> (String, Int) {
        guard !output.hasSuffix("$") else { return ("", 0) }
        var count = 0
        for character in output.reversed() {
            if character.isLetter || character.isNumber {
                count += 1
            } else {
                break
            }
        }
        guard count > 0 else { return ("", 0) }
        return (String(output.suffix(count)), count)
    }

    private static func simpleParen(in text: String, at index: String.Index) -> Range<String.Index>? {
        guard index < text.endIndex, text[index] == "(" else { return nil }
        var cursor = text.index(after: index)
        while cursor < text.endIndex, text[cursor] != ")" {
            let character = text[cursor]
            if !(character.isLetter || character.isNumber || character == ",") { return nil }
            cursor = text.index(after: cursor)
        }
        guard cursor < text.endIndex, text[cursor] == ")" else { return nil }
        return index..<text.index(after: cursor)
    }

    private static let arrows: [Character: String] = [
        "→": "\\to",
        "←": "\\leftarrow",
        "↔": "\\leftrightarrow",
        "⇒": "\\Rightarrow",
        "⇐": "\\Leftarrow",
        "↦": "\\mapsto",
    ]

    private static let symbols: [Character: String] = [
        "∫": "\\int", "∑": "\\sum", "√": "\\sqrt", "∞": "\\infty",
        "≤": "\\leq", "≥": "\\geq", "≠": "\\neq", "±": "\\pm",
        "×": "\\times", "÷": "\\div", "∈": "\\in", "∉": "\\notin",
        "⊂": "\\subset", "⊃": "\\supset", "∀": "\\forall", "∃": "\\exists",
        "α": "\\alpha", "β": "\\beta", "γ": "\\gamma", "δ": "\\delta",
        "ε": "\\epsilon", "θ": "\\theta", "λ": "\\lambda", "μ": "\\mu",
        "π": "\\pi", "σ": "\\sigma", "φ": "\\phi", "ω": "\\omega",
        "Δ": "\\Delta", "Σ": "\\Sigma", "Ω": "\\Omega",
    ]

    private static let blackboard: [Character: String] = [
        "ℂ": "\\mathbb{C}", "ℝ": "\\mathbb{R}", "ℕ": "\\mathbb{N}",
        "ℤ": "\\mathbb{Z}", "ℚ": "\\mathbb{Q}", "ℍ": "\\mathbb{H}",
    ]

    private static func replaceArrows(_ text: String) -> String {
        var output = ""
        var index = text.startIndex
        while index < text.endIndex {
            if text[index] == "$", let end = endOfDollarSpan(in: text, from: index) {
                output.append(contentsOf: text[index..<end])
                index = end
                continue
            }
            guard let arrow = arrows[text[index]],
                  let phrase = arrowPhrase(in: text, arrowAt: index, command: arrow),
                  output.hasSuffix(String(text[phrase.left])) else {
                output.append(text[index])
                index = text.index(after: index)
                continue
            }
            output.removeLast(text[phrase.left].count)
            output.append(phrase.latex)
            index = phrase.right
        }
        return output
    }

    private struct ArrowPhrase {
        var left: Range<String.Index>
        var right: String.Index
        var latex: String
    }

    private static func arrowPhrase(
        in text: String,
        arrowAt arrow: String.Index,
        command: String
    ) -> ArrowPhrase? {
        let nearEnd = skipSpaceBackward(text, from: arrow)
        guard let near = tokenEnding(at: nearEnd, in: text) else { return nil }
        var start = near.lowerBound
        var pieces = [latex(of: text[near])]

        let colonEnd = skipSpaceBackward(text, from: near.lowerBound)
        if colonEnd > text.startIndex {
            let colonIndex = text.index(before: colonEnd)
            if text[colonIndex] == ":" || text[colonIndex] == "∶" {
                let farEnd = skipSpaceBackward(text, from: colonIndex)
                if let far = tokenEnding(at: farEnd, in: text) {
                    start = far.lowerBound
                    pieces.insert(":", at: 0)
                    pieces.insert(latex(of: text[far]), at: 0)
                }
            }
        }

        let afterArrow = text.index(after: arrow)
        guard let right = tokenStarting(at: afterArrow, in: text) else { return nil }
        pieces.append(command)
        pieces.append(latex(of: text[right]))
        return ArrowPhrase(
            left: start..<arrow,
            right: right.upperBound,
            latex: "$\(pieces.joined(separator: " "))$"
        )
    }

    private static func latex(of token: Substring) -> String {
        let raw = String(token).trimmingCharacters(in: .whitespacesAndNewlines)
        if raw.hasPrefix("$$"), raw.hasSuffix("$$"), raw.count >= 4 {
            return String(raw.dropFirst(2).dropLast(2)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if raw.hasPrefix("$"), raw.hasSuffix("$"), raw.count >= 2 {
            return String(raw.dropFirst().dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return raw.map { character -> String in
            if let symbol = symbols[character] { return symbol }
            if let board = blackboard[character] { return board }
            return String(character)
        }.joined()
    }

    private static func isTokenCharacter(_ character: Character) -> Bool {
        character.isLetter || character.isNumber
            || symbols[character] != nil
            || blackboard[character] != nil
    }

    private static func tokenEnding(at end: String.Index, in text: String) -> Range<String.Index>? {
        guard end > text.startIndex else { return nil }
        let last = text.index(before: end)
        let character = text[last]
        if character == "$" {
            var opener = last
            while opener > text.startIndex {
                opener = text.index(before: opener)
                if text[opener] == "$" {
                    let range = opener..<end
                    return text.distance(from: range.lowerBound, to: range.upperBound) >= 2 ? range : nil
                }
            }
            return nil
        }
        if character == ")" || character == "]" {
            return bracketEnding(at: end, in: text, close: character)
        }
        guard isTokenCharacter(character) else { return nil }
        var start = last
        while start > text.startIndex {
            let previous = text.index(before: start)
            if isTokenCharacter(text[previous]) {
                start = previous
            } else {
                break
            }
        }
        let range = start..<end
        return text.distance(from: range.lowerBound, to: range.upperBound) <= 24 ? range : nil
    }

    private static func tokenStarting(at index: String.Index, in text: String) -> Range<String.Index>? {
        let start = skipSpaceForward(text, from: index)
        guard start < text.endIndex else { return nil }
        let character = text[start]
        if character == "$" {
            guard let end = endOfDollarSpan(in: text, from: start) else { return nil }
            return start..<end
        }
        if character == "(" || character == "[" {
            return bracketStarting(at: start, in: text)
        }
        guard isTokenCharacter(character) else { return nil }
        var end = text.index(after: start)
        while end < text.endIndex, isTokenCharacter(text[end]) {
            end = text.index(after: end)
        }
        let range = start..<end
        return text.distance(from: range.lowerBound, to: range.upperBound) <= 24 ? range : nil
    }

    private static func bracketEnding(
        at end: String.Index,
        in text: String,
        close: Character
    ) -> Range<String.Index>? {
        let open: Character = close == ")" ? "(" : "["
        var depth = 0
        var index = end
        var walked = 0
        while index > text.startIndex, walked < 40 {
            index = text.index(before: index)
            walked += 1
            let character = text[index]
            if character == close { depth += 1 }
            if character == open {
                depth -= 1
                if depth == 0 { return index..<end }
            }
        }
        return nil
    }

    private static func bracketStarting(at start: String.Index, in text: String) -> Range<String.Index>? {
        let open = text[start]
        let close: Character = open == "(" ? ")" : "]"
        var depth = 0
        var index = start
        var walked = 0
        while index < text.endIndex, walked < 40 {
            let character = text[index]
            if character == open { depth += 1 }
            if character == close {
                depth -= 1
                if depth == 0 { return start..<text.index(after: index) }
            }
            index = text.index(after: index)
            walked += 1
        }
        return nil
    }

    private static func skipSpaceBackward(_ text: String, from index: String.Index) -> String.Index {
        var cursor = index
        while cursor > text.startIndex {
            let previous = text.index(before: cursor)
            if text[previous] == " " || text[previous] == "\t" {
                cursor = previous
            } else {
                break
            }
        }
        return cursor
    }

    private static func skipSpaceForward(_ text: String, from index: String.Index) -> String.Index {
        var cursor = index
        while cursor < text.endIndex, text[cursor] == " " || text[cursor] == "\t" {
            cursor = text.index(after: cursor)
        }
        return cursor
    }

    private static func endOfDollarSpan(in text: String, from start: String.Index) -> String.Index? {
        guard start < text.endIndex, text[start] == "$" else { return nil }
        let display = text[start...].hasPrefix("$$")
        let marker = display ? 2 : 1
        guard let content = text.index(start, offsetBy: marker, limitedBy: text.endIndex),
              content < text.endIndex else { return nil }
        var index = content
        while index < text.endIndex {
            if text[index] == "$" {
                if display {
                    let next = text.index(after: index)
                    if next < text.endIndex, text[next] == "$" {
                        return text.index(after: next)
                    }
                } else {
                    return text.index(after: index)
                }
            }
            index = text.index(after: index)
        }
        return nil
    }
}

/// Citation hover for a string that contains math. Plain bibliography stays
/// on the system tooltip; this is the same statement renderer as the card,
/// so inline and display math are not drawn as source text.
struct ReferenceHoverLabel: View {
    var text: String
    var width: CGFloat = 420

    var body: some View {
        MessageContentView(content: text, font: .callout, allowsMonospace: false)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(width: width, alignment: .leading)
    }
}

/// "Source", collapsed until the reader opens the verbatim page text.
struct ReferencePreviewSourceDisclosure<Content: View>: View {
    @Binding var isExpanded: Bool
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            DisclosureGroup(isExpanded: $isExpanded) {
                content()
            } label: {
                Text("Source")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
        }
    }
}
