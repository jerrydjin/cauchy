import CoreGraphics
import Foundation

/// Shared opacities for citation chrome. Links, page tags, the sources
/// disclosure, and the passage wash all use these so a tap and its highlight
/// read as the same quiet accent. The link tint is one step under a full
/// accent so it sits nearer the body text than the blue it replaced.
enum CitationChrome {
    static let tintOpacity: CGFloat = 0.50
    static let washOpacity: CGFloat = 0.28
}

/// `[R1]` / `[P1]` / `[S1]` markers the model places after a claim.
enum AnswerSourceMarkers {
    struct Chip: Equatable, Sendable {
        var sourceID: String
        var pageIndex: Int
        var pageLabel: String
    }

    private static let pattern = try! NSRegularExpression(pattern: #"\[([A-Za-z]\d+)\]"#)

    static func containsMarker(in text: String) -> Bool {
        let range = NSRange(text.startIndex..., in: text)
        return pattern.firstMatch(in: text, range: range) != nil
    }

    static func markerRanges(in text: String) -> [(range: Range<String.Index>, id: String)] {
        let ns = text as NSString
        return pattern.matches(in: text, range: NSRange(location: 0, length: ns.length)).compactMap { match in
            guard let full = Range(match.range, in: text),
                  let idRange = Range(match.range(at: 1), in: text) else { return nil }
            return (full, String(text[idRange]).uppercased())
        }
    }
}

/// Short page text for a tag. One page is "p. 39"; a span is "pp. 37–39".
enum CitationPageLabel {
    static func short(firstPageIndex: Int, lastPageIndex: Int) -> String {
        let lower = min(firstPageIndex, lastPageIndex) + 1
        let upper = max(firstPageIndex, lastPageIndex) + 1
        if lower == upper { return "p. \(lower)" }
        return "pp. \(lower)–\(upper)"
    }

    static func voiceOver(firstPageIndex: Int, lastPageIndex: Int) -> String {
        let lower = min(firstPageIndex, lastPageIndex) + 1
        let upper = max(firstPageIndex, lastPageIndex) + 1
        if lower == upper { return "Open page \(lower)" }
        return "Open pages \(lower) to \(upper)"
    }
}

struct CitedSourcePage: Equatable, Sendable, Identifiable {
    var pageIndex: Int
    var anchor: AnswerSourceAnchor

    var id: Int { pageIndex }
    var pageLabel: String {
        CitationPageLabel.short(firstPageIndex: pageIndex, lastPageIndex: pageIndex)
    }
}

enum CitedSourceSummary {
    /// Pages the answer actually cites, in page order, one entry per page.
    /// A retrieved page the prose never marks is left out, and a page cited
    /// twice (the same proposition listed as two anchors) appears once.
    static func pages(in content: String, anchors: [AnswerSourceAnchor]) -> [CitedSourcePage] {
        var byID: [String: AnswerSourceAnchor] = [:]
        for anchor in anchors {
            guard let id = anchor.sourceID?.uppercased(), byID[id] == nil else { continue }
            byID[id] = anchor
        }
        var seenPages = Set<Int>()
        var found: [CitedSourcePage] = []
        for (_, id) in AnswerSourceMarkers.markerRanges(in: content) {
            guard let anchor = byID[id] else { continue }
            guard seenPages.insert(anchor.pageIndex).inserted else { continue }
            found.append(CitedSourcePage(pageIndex: anchor.pageIndex, anchor: anchor))
        }
        return found.sorted { $0.pageIndex < $1.pageIndex }
    }

    static func disclosureLabel(pageCount: Int) -> String {
        pageCount == 1 ? "Sources · 1 page" : "Sources · \(pageCount) pages"
    }
}

enum AnswerSourceNavigation: Equatable, Sendable {
    /// The exact passage was measured. Paint that rect, not the whole page.
    case highlighted(pageIndex: Int, region: NormalizedRect)
    /// The page is real, but the passage was not. Open the page and paint nothing.
    case pageOnly(pageIndex: Int)

    static func resolve(_ source: AnswerSourceAnchor, pageCount: Int) -> AnswerSourceNavigation? {
        guard pageCount > 0, source.pageIndex >= 0, source.pageIndex < pageCount else { return nil }
        if isLocatablePassage(source.region) {
            return .highlighted(pageIndex: source.pageIndex, region: source.region)
        }
        return .pageOnly(pageIndex: source.pageIndex)
    }

    /// Empty, non-finite, or off-page rects are not a passage. Callers must
    /// not invent a highlight when this returns false.
    static func isLocatablePassage(_ region: NormalizedRect) -> Bool {
        guard region.x.isFinite, region.y.isFinite,
              region.width.isFinite, region.height.isFinite,
              region.width > 0, region.height > 0,
              region.x >= 0, region.y >= 0,
              region.x + region.width <= 1.001,
              region.y + region.height <= 1.001 else { return false }
        return true
    }
}

struct CitationPassageHighlight: Equatable, Sendable {
    var pageIndex: Int
    var region: NormalizedRect
}

enum CitationPassageVisibility {
    static func remainsVisible(_ highlight: CitationPassageHighlight, in viewport: ViewportState) -> Bool {
        guard viewport.pageIndex == highlight.pageIndex else { return false }
        guard let visible = viewport.visibleRectNormalized else { return true }
        return visible.intersects(highlight.region)
    }
}

/// The wash stays until the reader scrolls the passage away. Viewport events
/// from the jump itself arrive before the passage is on screen; those do not
/// clear it, and nothing here fades the wash on a timer.
struct CitationHighlightSession: Equatable, Sendable {
    var highlight: CitationPassageHighlight?
    var armed = false

    mutating func show(_ highlight: CitationPassageHighlight) {
        self.highlight = highlight
        armed = false
    }

    mutating func clear() {
        highlight = nil
        armed = false
    }

    mutating func userMoved(to viewport: ViewportState) {
        guard let highlight else { return }
        if CitationPassageVisibility.remainsVisible(highlight, in: viewport) {
            armed = true
        } else if armed {
            clear()
        }
    }
}

enum AnswerCitationLayout {
    struct ClaimLine: Equatable, Sendable {
        var text: String
        var chips: [AnswerSourceMarkers.Chip]
    }

    /// One row per claim. Markers are removed from the middle of the sentence
    /// and the page tag is carried at the end of that claim.
    static func claimLines(in text: String, anchors: [AnswerSourceAnchor]) -> [ClaimLine] {
        var byID: [String: AnswerSourceAnchor] = [:]
        for anchor in anchors {
            guard let id = anchor.sourceID?.uppercased(), byID[id] == nil else { continue }
            byID[id] = anchor
        }

        let marks = AnswerSourceMarkers.markerRanges(in: text)
        guard !marks.isEmpty else {
            let cleaned = tidy(text)
            return cleaned.isEmpty ? [] : [ClaimLine(text: cleaned, chips: [])]
        }

        let ranges = marks.map(\.range)
        let math = mathRanges(in: text)
        var insertions: [String.Index: [AnswerSourceMarkers.Chip]] = [:]
        var insertionOrder: [String.Index] = []

        for mark in marks {
            guard !math.contains(where: { $0.overlaps(mark.range) }) else { continue }
            guard let anchor = byID[mark.id] else { continue }
            let chip = AnswerSourceMarkers.Chip(
                sourceID: mark.id,
                pageIndex: anchor.pageIndex,
                pageLabel: CitationPageLabel.short(
                    firstPageIndex: anchor.pageIndex,
                    lastPageIndex: anchor.pageIndex
                )
            )
            let insertAt = sentenceEnd(for: mark.range, in: text, math: math, markerRanges: ranges)
            if insertions[insertAt] == nil {
                insertionOrder.append(insertAt)
            }
            insertions[insertAt, default: []].append(chip)
        }

        guard !insertionOrder.isEmpty else {
            let cleaned = tidy(copying(text, from: text.startIndex, to: text.endIndex, skipping: ranges))
            return cleaned.isEmpty ? [] : [ClaimLine(text: cleaned, chips: [])]
        }

        var lines: [ClaimLine] = []
        var cursor = text.startIndex
        for insertAt in insertionOrder.sorted(by: { $0 < $1 }) {
            let raw = copying(text, from: cursor, to: insertAt, skipping: ranges)
            let cleaned = tidy(raw)
            let chips = deduped(insertions[insertAt] ?? [])
            if !cleaned.isEmpty || !chips.isEmpty {
                lines.append(ClaimLine(text: cleaned, chips: chips))
            }
            cursor = insertAt
        }
        let tail = tidy(copying(text, from: cursor, to: text.endIndex, skipping: ranges))
        if !tail.isEmpty {
            lines.append(ClaimLine(text: tail, chips: []))
        }
        return lines
    }

    private static func deduped(_ chips: [AnswerSourceMarkers.Chip]) -> [AnswerSourceMarkers.Chip] {
        var seen = Set<Int>()
        return chips.filter { seen.insert($0.pageIndex).inserted }
    }

    private static func sentenceEnd(
        for marker: Range<String.Index>,
        in text: String,
        math: [Range<String.Index>],
        markerRanges: [Range<String.Index>]
    ) -> String.Index {
        var index = marker.lowerBound
        while index > text.startIndex {
            let previous = text.index(before: index)
            if text[previous].isWhitespace {
                index = previous
                continue
            }
            if let covering = markerRanges.first(where: { $0.contains(previous) }) {
                index = covering.lowerBound
                continue
            }
            break
        }
        if index > text.startIndex {
            let previous = text.index(before: index)
            if isTerminator(at: previous, in: text), !math.contains(where: { $0.contains(previous) }) {
                return text.index(after: previous)
            }
        }

        var cursor = marker.upperBound
        while cursor < text.endIndex {
            if let span = math.first(where: { $0.contains(cursor) }) {
                cursor = span.upperBound
                continue
            }
            if let covering = markerRanges.first(where: { $0.contains(cursor) }) {
                cursor = covering.upperBound
                continue
            }
            if isTerminator(at: cursor, in: text) {
                return text.index(after: cursor)
            }
            cursor = text.index(after: cursor)
        }
        return text.endIndex
    }

    private static func isTerminator(at index: String.Index, in text: String) -> Bool {
        let character = text[index]
        guard character == "." || character == "!" || character == "?" else { return false }
        if character == "." {
            let previous: Character? = index > text.startIndex ? text[text.index(before: index)] : nil
            let nextIndex = text.index(after: index)
            let next: Character? = nextIndex < text.endIndex ? text[nextIndex] : nil
            if let previous, let next, previous.isNumber, next.isNumber { return false }
        }
        let nextIndex = text.index(after: index)
        if nextIndex >= text.endIndex { return true }
        let next = text[nextIndex]
        return next.isWhitespace || next == "[" || next == "$"
    }

    private static func mathRanges(in text: String) -> [Range<String.Index>] {
        var ranges: [Range<String.Index>] = []
        var cursor = text.startIndex
        while cursor < text.endIndex {
            guard let open = text[cursor...].firstIndex(of: "$") else { break }
            let after = text.index(after: open)
            let display = after < text.endIndex && text[after] == "$"
            let contentStart = display ? text.index(after: after) : after
            let delimiter = display ? "$$" : "$"
            guard let close = text[contentStart...].range(of: delimiter) else { break }
            ranges.append(open..<close.upperBound)
            cursor = close.upperBound
        }
        return ranges
    }

    private static func copying(
        _ text: String,
        from start: String.Index,
        to end: String.Index,
        skipping ranges: [Range<String.Index>]
    ) -> String {
        guard start < end else { return "" }
        var result = ""
        var cursor = start
        let relevant = ranges
            .filter { $0.upperBound > start && $0.lowerBound < end }
            .sorted { $0.lowerBound < $1.lowerBound }
        for range in relevant {
            let clipStart = max(range.lowerBound, cursor)
            let clipEnd = min(range.upperBound, end)
            if cursor < clipStart {
                result += text[cursor..<clipStart]
            }
            cursor = max(cursor, clipEnd)
            if cursor >= end { break }
        }
        if cursor < end {
            result += text[cursor..<end]
        }
        return result
    }

    private static func tidy(_ text: String) -> String {
        var result = text
        result = result.replacingOccurrences(
            of: #"\s+([,.;:!?])"#,
            with: "$1",
            options: .regularExpression
        )
        result = result.replacingOccurrences(
            of: #"[ \t]{2,}"#,
            with: " ",
            options: .regularExpression
        )
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// Word-level pieces so a cited result stays in the sentence. The whole
/// "Proposition 5.3.1" is not one unbreakable token, and the comma that
/// follows it rides on the last word instead of wrapping onto its own line.
enum InlineReferenceFlow {
    enum Piece: Equatable, Sendable {
        case text(String)
        /// `suffix` is the punctuation and space that must travel with the
        /// last word. It stays in the body colour; only `label` is a link.
        case link(label: String, suffix: String, reference: DetectedReference)
    }

    static func pieces(in text: String, matches: [DetectedReferenceMatch]) -> [Piece] {
        let matches = matches.sorted { $0.range.lowerBound < $1.range.lowerBound }
        guard !matches.isEmpty else {
            return wordPieces(text).map { .text($0) }
        }

        var pieces: [Piece] = []
        var cursor = text.startIndex
        for match in matches {
            if match.range.upperBound <= cursor { continue }
            let start = max(match.range.lowerBound, cursor)
            if cursor < start {
                pieces.append(contentsOf: wordPieces(String(text[cursor..<start])).map { .text($0) })
            }
            var end = match.range.upperBound
            while end < text.endIndex, isGluePunctuation(text[end]) {
                end = text.index(after: end)
            }
            if end < text.endIndex, text[end] == " " {
                end = text.index(after: end)
            }
            let bodyEnd = min(match.range.upperBound, end)
            let linkBody = start < bodyEnd ? String(text[start..<bodyEnd]) : ""
            let suffix = bodyEnd < end ? String(text[bodyEnd..<end]) : ""
            let words = wordPieces(linkBody)
            if words.isEmpty {
                if !suffix.isEmpty { pieces.append(.text(suffix)) }
            } else {
                for (index, word) in words.enumerated() {
                    pieces.append(.link(
                        label: word,
                        suffix: index == words.count - 1 ? suffix : "",
                        reference: match.reference
                    ))
                }
            }
            cursor = end
        }
        if cursor < text.endIndex {
            pieces.append(contentsOf: wordPieces(String(text[cursor...])).map { .text($0) })
        }
        return pieces.filter { piece in
            switch piece {
            case .text(let value):
                return !value.isEmpty
            case .link(let label, let suffix, _):
                return !label.isEmpty || !suffix.isEmpty
            }
        }
    }

    private static func isGluePunctuation(_ character: Character) -> Bool {
        character == "," || character == "." || character == ";" || character == ":"
            || character == ")" || character == "]"
    }

    /// Trailing whitespace stays on the word, matching `MessageContentParser`
    /// so a flow with spacing 0 does not double the gap.
    static func wordPieces(_ text: String) -> [String] {
        guard !text.isEmpty else { return [] }
        var tokens: [String] = []
        var index = text.startIndex
        while index < text.endIndex {
            if text[index].isWhitespace {
                let start = index
                while index < text.endIndex, text[index].isWhitespace {
                    index = text.index(after: index)
                }
                tokens.append(String(text[start..<index]))
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
            tokens.append(word)
        }
        return tokens.filter { !$0.isEmpty }
    }
}
