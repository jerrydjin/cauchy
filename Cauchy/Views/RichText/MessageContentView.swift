import SwiftUI

enum MessageSegment: Equatable {
    case text(String)
    case inlineMath(String)
    case displayMath(String)
    case bold(String)
    case italic(String)
    case code(String)
}

enum MessageContentParser {
    static func parse(_ content: String) -> [MessageSegment] {
        let normalized = LaTeXNormalizer.normalizeForDisplay(content)
        var segments: [MessageSegment] = []
        var remaining = normalized[...]

        let delimiters = ["$$", "$", "**", "*", "_", "`"]

        while !remaining.isEmpty {
            var earliest: String.Index?
            var earliestDelimiter: String = ""

            for delimiter in delimiters {
                if let range = remaining.range(of: delimiter) {
                    if earliest == nil || range.lowerBound < earliest! {
                        earliest = range.lowerBound
                        earliestDelimiter = delimiter
                    } else if earliest == range.lowerBound && delimiter.count > earliestDelimiter.count {
                        earliestDelimiter = delimiter
                    }
                }
            }

            guard let start = earliest else {
                segments.append(.text(String(remaining)))
                break
            }

            if start > remaining.startIndex {
                segments.append(.text(String(remaining[..<start])))
            }

            let searchStart = remaining.index(start, offsetBy: earliestDelimiter.count)
            // For markdown delimiters, don't match across paragraphs
            let paragraphEnd = remaining[searchStart...].range(of: "\n\n")?.lowerBound ?? remaining.endIndex
            
            let closingSearchRange = (earliestDelimiter == "$$" || earliestDelimiter == "$") ? 
                remaining[searchStart...] : remaining[searchStart..<paragraphEnd]

            if let closingRange = closingSearchRange.range(of: earliestDelimiter) {
                let innerText = String(remaining[searchStart..<closingRange.lowerBound])
                
                switch earliestDelimiter {
                case "$$":
                    if !innerText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        segments.append(.displayMath(innerText.trimmingCharacters(in: .whitespacesAndNewlines)))
                    }
                case "$":
                    if !innerText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        let latex = innerText.trimmingCharacters(in: .whitespacesAndNewlines)
                        if LaTeXNormalizer.shouldRenderAsDisplayMath(latex) {
                            segments.append(.displayMath(latex))
                        } else {
                            segments.append(.inlineMath(latex))
                        }
                    }
                case "**":
                    segments.append(.bold(innerText))
                case "*", "_":
                    segments.append(.italic(innerText))
                case "`":
                    segments.append(.code(innerText))
                default:
                    break
                }
                
                remaining = remaining[closingRange.upperBound...]
            } else {
                segments.append(.text(earliestDelimiter))
                remaining = remaining[searchStart...]
            }
        }

        return segments.filter {
            switch $0 {
            case .text(let value):
                return !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || value.contains("\n")
            default:
                return true
            }
        }
    }

    static func flowTokens(from segments: [MessageSegment]) -> [MessageSegment] {
        segments.flatMap { segment -> [MessageSegment] in
            switch segment {
            case .text(let value):
                return wordTokens(from: value) { .text($0) }
            case .bold(let value):
                return wordTokens(from: value) { .bold($0) }
            case .italic(let value):
                return wordTokens(from: value) { .italic($0) }
            case .code(let value):
                return wordTokens(from: value) { .code($0) }
            case .inlineMath, .displayMath:
                return [segment]
            }
        }
    }

    private static func wordTokens(from text: String, map: (String) -> MessageSegment) -> [MessageSegment] {
        guard !text.isEmpty else { return [] }

        var tokens: [MessageSegment] = []
        var index = text.startIndex

        while index < text.endIndex {
            if text[index].isWhitespace {
                let start = index
                while index < text.endIndex, text[index].isWhitespace {
                    index = text.index(after: index)
                }
                tokens.append(map(String(text[start..<index])))
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
            tokens.append(map(word))
        }

        return tokens.filter {
            switch $0 {
            case .text(let value), .bold(let value), .italic(let value), .code(let value):
                return !value.isEmpty
            default:
                return true
            }
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
            case .bold, .italic, .code, .inlineMath, .displayMath:
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
                    
                    if !trimmed.isEmpty {
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
            case .bold(let value), .italic(let value), .code(let value):
                let normalized = normalizeSoftLineBreaks(value)
                let trimmed = normalized.trimmingCharacters(in: .whitespaces)
                if !trimmed.isEmpty {
                    switch segment {
                    case .bold: currentLine.append(.bold(trimmed))
                    case .italic: currentLine.append(.italic(trimmed))
                    case .code: currentLine.append(.code(trimmed))
                    default: break
                    }
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
            case .bold(let value):
                plainText(value).bold()
                    .frame(maxWidth: .infinity, alignment: .leading)
            case .italic(let value):
                plainText(value).italic()
                    .frame(maxWidth: .infinity, alignment: .leading)
            case .code(let value):
                codeText(value)
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
        case .bold(let value):
            Text(value)
                .font(font)
                .bold()
                .foregroundStyle(textColor)
                .textSelection(.enabled)
                .fixedSize(horizontal: true, vertical: true)
        case .italic(let value):
            Text(value)
                .font(font)
                .italic()
                .foregroundStyle(textColor)
                .textSelection(.enabled)
                .fixedSize(horizontal: true, vertical: true)
        case .code(let value):
            Text(value)
                .font(.system(.body, design: .monospaced))
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(Color.secondary.opacity(0.2))
                .cornerRadius(4)
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

    private func codeText(_ value: String) -> some View {
        Text(value)
            .font(.system(.body, design: .monospaced))
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .background(Color.secondary.opacity(0.2))
            .cornerRadius(4)
            .foregroundStyle(textColor)
            .textSelection(.enabled)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
    }
}
