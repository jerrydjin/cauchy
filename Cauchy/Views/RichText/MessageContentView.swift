import SwiftUI

enum MessageSegment: Equatable {
    case text(String)
    case inlineMath(String)
    case displayMath(String)
}

enum MessageContentParser {
    static func parse(_ content: String) -> [MessageSegment] {
        let normalized = LaTeXNormalizer.normalizeForDisplay(content)
        var segments: [MessageSegment] = []
        var remaining = normalized[...]

        while !remaining.isEmpty {
            if remaining.hasPrefix("$$"),
               let end = remaining[remaining.index(remaining.startIndex, offsetBy: 2)...].range(of: "$$") {
                let start = remaining.index(remaining.startIndex, offsetBy: 2)
                let latex = String(remaining[start..<end.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                if !latex.isEmpty {
                    segments.append(.displayMath(latex))
                }
                remaining = remaining[end.upperBound...]
                continue
            }

            if let dollar = remaining.firstIndex(of: "$") {
                if dollar > remaining.startIndex {
                    segments.append(.text(String(remaining[..<dollar])))
                }

                let afterDollar = remaining.index(after: dollar)
                if afterDollar < remaining.endIndex,
                   let closing = remaining[afterDollar...].firstIndex(of: "$") {
                    let latex = String(remaining[afterDollar..<closing]).trimmingCharacters(in: .whitespacesAndNewlines)
                    if !latex.isEmpty {
                        let segment: MessageSegment = LaTeXNormalizer.shouldRenderAsDisplayMath(latex)
                            ? .displayMath(latex)
                            : .inlineMath(latex)
                        segments.append(segment)
                    }
                    remaining = remaining[remaining.index(after: closing)...]
                    continue
                }

                segments.append(.text(String(remaining[dollar...])))
                break
            }

            segments.append(.text(String(remaining)))
            break
        }

        return segments.filter {
            switch $0 {
            case .text(let value):
                return !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            default:
                return true
            }
        }
    }

    static func flowTokens(from segments: [MessageSegment]) -> [MessageSegment] {
        segments.flatMap { segment -> [MessageSegment] in
            switch segment {
            case .text(let value):
                return wordTokens(from: value)
            case .inlineMath, .displayMath:
                return [segment]
            }
        }
    }

    private static func wordTokens(from text: String) -> [MessageSegment] {
        guard !text.isEmpty else { return [] }

        var tokens: [MessageSegment] = []
        var index = text.startIndex

        while index < text.endIndex {
            if text[index].isWhitespace {
                let start = index
                while index < text.endIndex, text[index].isWhitespace {
                    index = text.index(after: index)
                }
                tokens.append(.text(String(text[start..<index])))
                continue
            }

            let start = index
            while index < text.endIndex, !text[index].isWhitespace {
                index = text.index(after: index)
            }

            var word = String(text[start..<index])
            if index < text.endIndex, text[index].isWhitespace {
                word.append(text[index])
                index = text.index(after: index)
            }
            tokens.append(.text(word))
        }

        return tokens.filter {
            if case .text(let value) = $0 {
                return !value.isEmpty
            }
            return true
        }
    }

    static func mergeAdjacentText(_ segments: [MessageSegment]) -> [MessageSegment] {
        var merged: [MessageSegment] = []
        var textBuffer = ""

        func flushText() {
            guard !textBuffer.isEmpty else { return }
            merged.append(.text(textBuffer))
            textBuffer = ""
        }

        for segment in segments {
            switch segment {
            case .text(let value):
                textBuffer += value
            case .inlineMath, .displayMath:
                flushText()
                merged.append(segment)
            }
        }
        flushText()
        return merged
    }

    static func blocks(from segments: [MessageSegment]) -> [MessageBlock] {
        let merged = mergeAdjacentText(segments)
        var blocks: [MessageBlock] = []
        var currentLine: [MessageSegment] = []

        func flushLine() {
            guard !currentLine.isEmpty else { return }
            if currentLine.count == 1, case .text(let value) = currentLine[0] {
                let trimmed = value.trimmingCharacters(in: .whitespaces)
                if !trimmed.isEmpty {
                    blocks.append(.text(trimmed))
                }
            } else {
                blocks.append(.inlineLine(currentLine))
            }
            currentLine = []
        }

        for segment in merged {
            switch segment {
            case .displayMath(let latex):
                flushLine()
                blocks.append(.displayMath(latex))
            case .text(let value):
                let paragraphs = splitParagraphs(value)
                for (paragraphIndex, paragraph) in paragraphs.enumerated() {
                    let normalized = normalizeSoftLineBreaks(paragraph)
                    let trimmed = normalized.trimmingCharacters(in: .whitespaces)
                    guard !trimmed.isEmpty else { continue }

                    if LaTeXNormalizer.isBareLaTeXLine(trimmed) {
                        flushLine()
                        blocks.append(.displayMath(trimmed))
                    } else {
                        currentLine.append(.text(trimmed))
                    }

                    if paragraphIndex < paragraphs.count - 1 {
                        flushLine()
                    }
                }
            case .inlineMath(let latex):
                if LaTeXNormalizer.shouldRenderAsDisplayMath(latex) {
                    flushLine()
                    blocks.append(.displayMath(latex))
                } else {
                    currentLine.append(.inlineMath(latex))
                }
            }
        }

        flushLine()
        return blocks
    }

    private static func splitParagraphs(_ text: String) -> [String] {
        text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: "\n\n")
    }

    /// Single newlines mid-sentence become spaces so inline math stays in flow with prose.
    private static func normalizeSoftLineBreaks(_ text: String) -> String {
        text
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}

enum MessageBlock: Equatable {
    case text(String)
    case inlineLine([MessageSegment])
    case displayMath(String)
}

struct MessageContentView: View {
    let content: String
    var font: Font = .body
    var textColor: Color = .primary

    var body: some View {
        if !LaTeXNormalizer.needsRichRendering(content) {
            plainText(content)
        } else {
            richContent
        }
    }

    private var richContent: some View {
        let segments = MessageContentParser.parse(content)
        let blocks = MessageContentParser.blocks(from: segments)

        return VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                blockView(block)
            }
        }
    }

    @ViewBuilder
    private func blockView(_ block: MessageBlock) -> some View {
        switch block {
        case .text(let value):
            plainText(value)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .displayMath(let latex):
            MathSegmentView(latex: latex, mode: .display, fontSize: 17, textColor: textColor)
                .frame(maxWidth: .infinity, alignment: .center)
        case .inlineLine(let segments):
            inlineLineView(segments)
        }
    }

    @ViewBuilder
    private func inlineLineView(_ segments: [MessageSegment]) -> some View {
        let merged = MessageContentParser.mergeAdjacentText(segments)

        if merged.count == 1 {
            switch merged[0] {
            case .text(let value):
                plainText(value)
                    .frame(maxWidth: .infinity, alignment: .leading)
            case .inlineMath(let latex):
                MathSegmentView(latex: latex, mode: .inline, fontSize: 15, textColor: textColor)
                    .frame(maxWidth: .infinity, alignment: .leading)
            case .displayMath(let latex):
                MathSegmentView(latex: latex, mode: .display, fontSize: 17, textColor: textColor)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        } else if let mergedText = mergedText(from: merged) {
            plainText(mergedText)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            let flowTokens = MessageContentParser.flowTokens(from: merged)
            InlineFlowLayout(horizontalSpacing: 3, verticalSpacing: 4) {
                ForEach(Array(flowTokens.enumerated()), id: \.offset) { _, segment in
                    flowSegmentView(segment)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func mergedText(from segments: [MessageSegment]) -> String? {
        guard !segments.isEmpty else { return nil }
        guard segments.allSatisfy({ if case .text = $0 { true } else { false } }) else { return nil }
        return segments.compactMap { if case .text(let value) = $0 { value } else { nil } }.joined()
    }

    @ViewBuilder
    private func flowSegmentView(_ segment: MessageSegment) -> some View {
        switch segment {
        case .text(let value):
            Text(value)
                .font(font)
                .foregroundStyle(textColor)
                .textSelection(.enabled)
                .fixedSize(horizontal: true, vertical: true)
        case .inlineMath(let latex):
            MathSegmentView(latex: latex, mode: .inline, fontSize: 15, textColor: textColor)
        case .displayMath(let latex):
            MathSegmentView(latex: latex, mode: .display, fontSize: 17, textColor: textColor)
        }
    }

    private func plainText(_ value: String) -> some View {
        Text(value)
            .font(font)
            .foregroundStyle(textColor)
            .textSelection(.enabled)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
    }
}
