import Foundation

enum MessageSegment: Equatable {
    case text(String)
    case inlineMath(String)
    case displayMath(String)
    case bold(String)
    case italic(String)
    case code(String)
}

enum MessageBlock: Equatable {
    case text(String)
    case inlineLine([MessageSegment])
    case displayMath(String)
}

enum MessageContentParser {
    static func parse(_ content: String) -> [MessageSegment] {
        parseNormalized(LaTeXNormalizer.normalizeForDisplay(content))
    }

    /// Parses content that has already been through `LaTeXNormalizer.normalizeForDisplay`,
    /// so callers that normalize for other reasons don't pay for it twice.
    static func parseNormalized(_ normalized: String) -> [MessageSegment] {
        var segments: [MessageSegment] = []
        var remaining = normalized[...]

        let delimiters = ["$$", "$", "**", "*", "_", "`"]
        // Next-occurrence memo per delimiter: a found range stays the first
        // occurrence until the parser advances past it, and a delimiter absent
        // from the current suffix is absent from every later suffix. This keeps
        // the scan linear instead of re-searching the whole tail per segment.
        var nextOccurrence = [OccurrenceMemo](repeating: .unknown, count: delimiters.count)

        while !remaining.isEmpty {
            var earliest: String.Index?
            var earliestDelimiter: String = ""

            for (memoIndex, delimiter) in delimiters.enumerated() {
                let range: Range<String.Index>?
                switch nextOccurrence[memoIndex] {
                case .found(let cached) where cached.lowerBound >= remaining.startIndex:
                    range = cached
                case .absent:
                    range = nil
                default:
                    range = remaining.range(of: delimiter)
                    nextOccurrence[memoIndex] = range.map(OccurrenceMemo.found) ?? .absent
                }

                if let range {
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

    private enum OccurrenceMemo {
        case unknown
        case absent
        case found(Range<String.Index>)
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

/// Memoizes the full normalize → parse → blocks pipeline per message content.
/// SwiftUI re-evaluates `MessageContentView.body` on every observable change
/// (and on every streamed partial), so without this each visible bubble
/// re-parses its whole text per frame.
@MainActor
enum MessageRenderCache {
    struct Parsed {
        let needsRichRendering: Bool
        let blocks: [MessageBlock]
    }

    private static var cache: [String: Parsed] = [:]
    private static var insertionOrder: [String] = []
    private static let capacity = 128

    static func parsed(for content: String) -> Parsed {
        if let hit = cache[content] {
            return hit
        }

        let normalized = LaTeXNormalizer.normalizeForDisplay(content)
        let parsed: Parsed
        if normalized.contains("$") {
            let segments = MessageContentParser.parseNormalized(normalized)
            parsed = Parsed(needsRichRendering: true, blocks: MessageContentParser.blocks(from: segments))
        } else {
            parsed = Parsed(needsRichRendering: false, blocks: [])
        }

        cache[content] = parsed
        insertionOrder.append(content)
        if insertionOrder.count > capacity {
            cache.removeValue(forKey: insertionOrder.removeFirst())
        }
        return parsed
    }
}
