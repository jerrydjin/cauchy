import Foundation
import PDFKit

/// One outline entry. `pageIndex` is a PDF page index, or -1 when the bookmark
/// has no destination.
struct AskOutlineNode: Equatable, Sendable {
    var title: String
    var pageIndex: Int
    var children: [AskOutlineNode]
}

struct AskPageSnapshot: Equatable, Sendable {
    var pageIndex: Int
    var text: String
}

struct AskDocumentStructure: Equatable, Sendable {
    var outline: [AskOutlineNode]
    var pages: [AskPageSnapshot]
    var pageCount: Int
}

struct AskHeading: Equatable, Sendable {
    var title: String
    var pageIndex: Int
    /// What the sources list shows, for example "§2.1 Groups".
    var label: String
}

struct AskDocumentSpan: Equatable, Sendable {
    var label: String
    var startPage: Int
    var endPage: Int
    var headings: [AskHeading]

    var pageRange: Range<Int> { startPage..<endPage }

    var promptNote: String {
        let first = startPage + 1
        let last = max(first, endPage)
        let pages = first == last ? "PDF page \(first)" : "PDF pages \(first)–\(last)"
        return """
        DOCUMENT UNIT: \(label), \(pages). The excerpts are this unit's opening pages, its headings, and statements from the notes that fall inside it. The reader asked about this unit, so describe what it contains. That is not a request to summarize the entire document. Do not ask the reader for a page or a contents page.
        """
    }
}

/// A chapter, section, or part named in a question.
struct StructuralQuery: Equatable, Sendable {
    enum Kind: String, Equatable, Sendable {
        case chapter
        case section
        case part
    }

    var kind: Kind
    /// The number as the reader wrote it, such as "II" or "3.4".
    var number: String
    /// Arabic form used for matching: "II" and "2" both become "2".
    var canonical: String

    var displayName: String {
        switch kind {
        case .chapter: "Chapter \(number)"
        case .section: "Section \(number)"
        case .part: "Part \(number)"
        }
    }
}

enum AskStructureLookup: Equatable, Sendable {
    case found(AskDocumentSpan)
    case missing(String)
}

/// Finds a chapter, section, or part in the outline, then in detected headings,
/// then on a contents page. Matching is pure text so tests do not need a PDF.
enum AskStructureLocator {
    static func query(in text: String) -> StructuralQuery? {
        let patterns: [(StructuralQuery.Kind, String)] = [
            (.section, #"(?i)(?:§\s*|(?:section|sec\.?)\s+)(\d+(?:\.\d+)*)(?!\.\d)"#),
            (.chapter, #"(?i)\b(?:chapter|chap\.?|ch\.?)\s+([0-9]+|[IVXLCDM]+)(?!\.\d)\b"#),
            (.part, #"(?i)\bpart\s+([0-9]+|[IVXLCDM]+)\b"#),
            (.section, #"(?i)\bsection\s+(\d+)(?!\.\d)\b"#),
        ]
        var best: (location: Int, query: StructuralQuery)?
        let ns = text as NSString
        for (kind, pattern) in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(location: 0, length: ns.length)
            guard let match = regex.firstMatch(in: text, range: range),
                  let numberRange = Range(match.range(at: 1), in: text) else { continue }
            let raw = String(text[numberRange])
            guard let canonical = canonicalNumber(raw),
                  best == nil || match.range.location < best!.location else { continue }
            best = (match.range.location, StructuralQuery(kind: kind, number: raw, canonical: canonical))
        }
        return best?.query
    }

    static func notFoundMessage(for query: StructuralQuery) -> String {
        "\(query.displayName) was not found in the outline, headings, or contents. Highlight a passage or rephrase the question."
    }

    static func locate(_ query: StructuralQuery, in structure: AskDocumentStructure) -> AskStructureLookup {
        if let span = span(in: structure.outline, query: query, pageCount: structure.pageCount) {
            return .found(span)
        }
        let detected = headings(in: structure.pages)
        if let span = span(from: detected, query: query, pageCount: structure.pageCount) {
            return .found(span)
        }
        if let span = spanFromContents(structure.pages, query: query, pageCount: structure.pageCount) {
            return .found(span)
        }
        return .missing(notFoundMessage(for: query))
    }

    /// Opening pages of the unit, then a short heading list, clipped to the
    /// provider's passage budget.
    static func passages(
        for span: AskDocumentSpan,
        in structure: AskDocumentStructure,
        characterBudget: Int,
        limit: Int
    ) -> [DocumentPassage] {
        guard characterBudget > 0, limit > 0 else { return [] }
        let bodyPages = structure.pages
            .filter { span.pageRange.contains($0.pageIndex) }
            .filter { !LLMReferenceIndexSupport.isLikelyTableOfContents($0.text) }
            .sorted { $0.pageIndex < $1.pageIndex }

        let headingSlots = span.headings.isEmpty || limit < 2 ? 0 : 1
        let openingSlots = max(1, limit - headingSlots)
        let headingBudget = headingSlots == 0 ? 0 : min(320, characterBudget / 3)
        var remaining = characterBudget - headingBudget
        var records: [DocumentPassage] = []

        for page in bodyPages.prefix(openingSlots) {
            guard remaining >= 40 else { break }
            let body = clipped(prose(page.text), to: remaining - 24)
            guard body.count >= 20 else { continue }
            let label = page.pageIndex == span.startPage
                ? span.label
                : (span.headings.first { $0.pageIndex == page.pageIndex }?.label ?? span.label)
            let text = "[p. \(page.pageIndex + 1)] \(label)\n\(body)"
            records.append(DocumentPassage(
                text: text,
                location: LexicalDocumentIndex.sourceLocation(
                    for: String(body.prefix(180)),
                    in: page.text,
                    pageIndex: page.pageIndex,
                    after: 0
                )
            ))
            remaining -= text.count
        }

        if headingSlots == 1, !span.headings.isEmpty {
            var lines = ["[p. \(span.startPage + 1)] Headings in \(span.label):"]
            for heading in span.headings.prefix(8) {
                lines.append("\(heading.label) (p. \(heading.pageIndex + 1))")
            }
            let text = lines.joined(separator: "\n")
            let clippedText = text.count > headingBudget && headingBudget >= 40
                ? String(text.prefix(headingBudget))
                : text
            let anchor = span.headings[0]
            let pageText = structure.pages.first { $0.pageIndex == anchor.pageIndex }?.text ?? ""
            records.append(DocumentPassage(
                text: clippedText,
                location: LexicalDocumentIndex.sourceLocation(
                    for: anchor.title,
                    in: pageText,
                    pageIndex: anchor.pageIndex,
                    after: 0
                )
            ))
        }
        return records
    }

    static func headings(in outline: [AskOutlineNode]) -> [AskHeading] {
        var result: [AskHeading] = []
        func walk(_ nodes: [AskOutlineNode]) {
            for node in nodes {
                if node.pageIndex >= 0, let label = displayLabel(node.title) {
                    result.append(AskHeading(title: node.title, pageIndex: node.pageIndex, label: label))
                }
                walk(node.children)
            }
        }
        walk(outline)
        return result.sorted { $0.pageIndex < $1.pageIndex }
    }

    static func nearestHeading(onOrBefore pageIndex: Int, in headings: [AskHeading]) -> String? {
        headings.filter { $0.pageIndex <= pageIndex }.max { $0.pageIndex < $1.pageIndex }?.label
    }

    static func statementLabel(_ entry: IndexedReference) -> String {
        let name = entry.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if name.isEmpty { return entry.reference.displayName }
        return "\(entry.reference.displayName) \(name)"
    }

    // MARK: - Outline and page text

    @MainActor
    static func structure(from document: PDFDocument) -> AskDocumentStructure {
        AskDocumentStructure(
            outline: outlineNodes(document.outlineRoot, document: document),
            pages: (0..<document.pageCount).compactMap { index in
                guard let text = document.page(at: index)?.string, !text.isEmpty else { return nil }
                return AskPageSnapshot(pageIndex: index, text: text)
            },
            pageCount: document.pageCount
        )
    }

    @MainActor
    static func outlineHeadings(in document: PDFDocument) -> [AskHeading] {
        headings(in: outlineNodes(document.outlineRoot, document: document))
    }

    // MARK: - Matching

    private static func span(
        in outline: [AskOutlineNode],
        query: StructuralQuery,
        pageCount: Int
    ) -> AskDocumentSpan? {
        let flat = flatten(outline)
        let match: FlatOutline?
        if query.kind == .section {
            let numbered = numberedOutline(outline)
            match = numbered
                .filter { $0.number == query.canonical || matches($0.title, query: query) }
                .min { lhs, rhs in
                    let leftKind = lhs.title.lowercased().contains(query.kind.rawValue)
                    let rightKind = rhs.title.lowercased().contains(query.kind.rawValue)
                    if leftKind != rightKind { return leftKind }
                    if lhs.depth != rhs.depth { return lhs.depth < rhs.depth }
                    return lhs.pageIndex < rhs.pageIndex
                }
                .map { FlatOutline(title: $0.title, pageIndex: $0.pageIndex, depth: $0.depth) }
        } else {
            match = best(in: flat, query: query)
        }
        guard let match else { return nil }
        let end = flat.first {
            $0.depth <= match.depth && $0.pageIndex > match.pageIndex
        }?.pageIndex ?? pageCount
        let headings = flat.filter {
            $0.depth > match.depth && $0.pageIndex >= match.pageIndex && $0.pageIndex < max(end, match.pageIndex + 1)
        }.map { AskHeading(title: $0.title, pageIndex: $0.pageIndex, label: displayLabel($0.title) ?? $0.title) }
        return makeSpan(
            title: match.title,
            kind: query.kind,
            start: match.pageIndex,
            end: end,
            pageCount: pageCount,
            headings: headings
        )
    }

    private static func headings(in pages: [AskPageSnapshot]) -> [AskHeading] {
        var found: [AskHeading] = []
        for page in pages where !LLMReferenceIndexSupport.isLikelyTableOfContents(page.text) {
            for raw in page.text.split(separator: "\n", omittingEmptySubsequences: false) {
                let line = raw.trimmingCharacters(in: .whitespaces)
                guard (3...120).contains(line.count), line.split(separator: " ").count <= 14 else { continue }
                guard matchesHeadingLine(line) else { continue }
                found.append(AskHeading(
                    title: line,
                    pageIndex: page.pageIndex,
                    label: displayLabel(line) ?? line
                ))
            }
        }
        return found
    }

    private static func span(
        from headings: [AskHeading],
        query: StructuralQuery,
        pageCount: Int
    ) -> AskDocumentSpan? {
        guard let match = headings.enumerated().first(where: { matches($0.element.title, query: query) }) else {
            return nil
        }
        let rank = headingRank(match.element.title)
        let later = headings[(match.offset + 1)...]
        let end = later.first { headingRank($0.title) <= rank }?.pageIndex ?? pageCount
        let nested = later.filter { $0.pageIndex < max(end, match.element.pageIndex + 1) && headingRank($0.title) > rank }
        return makeSpan(
            title: match.element.title,
            kind: query.kind,
            start: match.element.pageIndex,
            end: end,
            pageCount: pageCount,
            headings: nested
        )
    }

    private static func spanFromContents(
        _ pages: [AskPageSnapshot],
        query: StructuralQuery,
        pageCount: Int
    ) -> AskDocumentSpan? {
        var entries: [(title: String, printedPage: Int)] = []
        for page in pages where LLMReferenceIndexSupport.isLikelyTableOfContents(page.text) {
            for raw in page.text.split(separator: "\n") {
                guard let entry = contentsEntry(String(raw)) else { continue }
                entries.append(entry)
            }
        }
        guard let index = entries.firstIndex(where: { matches($0.title, query: query) }) else { return nil }
        let entry = entries[index]
        let start = min(max(entry.printedPage - 1, 0), max(pageCount - 1, 0))
        let rank = headingRank(entry.title)
        let end: Int
        if let next = entries.dropFirst(index + 1).first(where: { headingRank($0.title) <= rank }) {
            // The next contents line is often a section of this same unit.
            end = max(start + 1, next.printedPage - 1)
        } else {
            end = min(pageCount, start + 8)
        }
        return makeSpan(
            title: entry.title,
            kind: query.kind,
            start: start,
            end: end,
            pageCount: pageCount,
            headings: []
        )
    }

    private struct FlatOutline {
        var title: String
        var pageIndex: Int
        var depth: Int
    }

    private struct NumberedOutline {
        var title: String
        var number: String
        var pageIndex: Int
        var depth: Int
    }

    private static let nonSectionTitle = #"(?i)^\s*(?:abstract|references|bibliography|acknowledgements?|acknowledgments?|contents|table of contents|index|notation)\s*\.?\s*$"#
    private static let structuralLabel = #"(?i)^\s*(?:chapter|chap\.?|ch\.?|part)\b"#

    private static func explicitSectionNumber(_ title: String) -> String? {
        if let section = number(in: title, pattern: sectionKeyword) { return section }
        if let dotted = leadingNumber(in: title, dotted: true) { return dotted }
        return leadingNumber(in: title, dotted: false)
    }

    private static func matchesWhole(_ title: String, pattern: String) -> Bool {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return false }
        let ns = title as NSString
        let range = NSRange(location: 0, length: ns.length)
        return regex.firstMatch(in: title, range: range)?.range.length == ns.length
    }

    /// Bookmarks often read "Introduction" rather than "1. Introduction".
    /// Number those in sibling order. A sibling that already prints "1. Preliminaries"
    /// keeps that number, and the bare "Introduction" beside it is front matter.
    private static func numberedOutline(
        _ nodes: [AskOutlineNode],
        prefix: String? = nil,
        depth: Int = 0
    ) -> [NumberedOutline] {
        let prepared = nodes.map { node -> (AskOutlineNode, String, String?) in
            let title = node.title.trimmingCharacters(in: .whitespacesAndNewlines)
            return (node, title, title.isEmpty ? nil : explicitSectionNumber(title))
        }
        let anyExplicit = prepared.contains { $0.2 != nil }
        var entries: [NumberedOutline] = []
        var counter = 0
        for (node, title, explicit) in prepared {
            if node.pageIndex < 0 || title.isEmpty {
                entries.append(contentsOf: numberedOutline(node.children, prefix: prefix, depth: depth + 1))
                continue
            }
            let skipped = explicit == nil && (
                anyExplicit
                    || matchesWhole(title, pattern: nonSectionTitle)
                    || (try? NSRegularExpression(pattern: structuralLabel))?.firstMatch(
                        in: title,
                        range: NSRange(location: 0, length: (title as NSString).length)
                    ) != nil
            )
            if skipped {
                entries.append(contentsOf: numberedOutline(node.children, prefix: prefix, depth: depth + 1))
                continue
            }
            let number: String
            if let explicit {
                number = explicit
                if let tail = explicit.split(separator: ".").last, let value = Int(tail) {
                    counter = max(counter, value)
                }
            } else {
                counter += 1
                number = prefix.map { "\($0).\(counter)" } ?? String(counter)
            }
            entries.append(NumberedOutline(title: title, number: number, pageIndex: node.pageIndex, depth: depth))
            entries.append(contentsOf: numberedOutline(node.children, prefix: number, depth: depth + 1))
        }
        return entries
    }

    private static func flatten(_ nodes: [AskOutlineNode], depth: Int = 0) -> [FlatOutline] {
        var result: [FlatOutline] = []
        for node in nodes {
            if node.pageIndex >= 0, !node.title.trimmingCharacters(in: .whitespaces).isEmpty {
                result.append(FlatOutline(title: node.title, pageIndex: node.pageIndex, depth: depth))
            }
            result.append(contentsOf: flatten(node.children, depth: depth + 1))
        }
        return result
    }

    private static func best(in nodes: [FlatOutline], query: StructuralQuery) -> FlatOutline? {
        nodes
            .filter { matches($0.title, query: query) }
            .min { lhs, rhs in
                let leftKind = lhs.title.lowercased().contains(query.kind.rawValue)
                let rightKind = rhs.title.lowercased().contains(query.kind.rawValue)
                if leftKind != rightKind { return leftKind }
                if lhs.depth != rhs.depth { return lhs.depth < rhs.depth }
                return lhs.pageIndex < rhs.pageIndex
            }
    }

    private static func makeSpan(
        title: String,
        kind: StructuralQuery.Kind,
        start: Int,
        end: Int,
        pageCount: Int,
        headings: [AskHeading]
    ) -> AskDocumentSpan? {
        guard pageCount > 0, start >= 0, start < pageCount else { return nil }
        let boundedEnd = min(max(end, start + 1), pageCount)
        return AskDocumentSpan(
            label: displayLabel(title, kind: kind) ?? title,
            startPage: start,
            endPage: boundedEnd,
            headings: headings
        )
    }

    private static let chapterKeyword = #"(?i)^\s*(?:chapter|chap\.?|ch\.?)\s+([0-9]+|[IVXLCDM]+)(?!\.\d)\b"#
    private static let partKeyword = #"(?i)^\s*part\s+([0-9]+|[IVXLCDM]+)\b"#
    private static let sectionKeyword = #"(?i)^\s*(?:§\s*|(?:section|sec\.?)\s+)(\d+(?:\.\d+)*)(?!\.\d)"#

    private static func matches(_ title: String, query: StructuralQuery) -> Bool {
        switch query.kind {
        case .chapter:
            if number(in: title, pattern: chapterKeyword) == query.canonical {
                return true
            }
            if title.lowercased().hasPrefix("part") { return false }
            return leadingNumber(in: title, dotted: false) == query.canonical
                || leadingRoman(in: title) == query.canonical
        case .part:
            if number(in: title, pattern: partKeyword) == query.canonical {
                return true
            }
            return leadingRoman(in: title) == query.canonical
        case .section:
            if number(in: title, pattern: sectionKeyword) == query.canonical {
                return true
            }
            // "9.2 Groups" is section 9.2. "1. Introduction" is section 1.
            // A dotted heading must not satisfy an undotted query: "2.1 Title"
            // is not section 2. `leadingNumber(dotted: false)` already rejects
            // a following digit, so both forms can be tried.
            return leadingNumber(in: title, dotted: true) == query.canonical
                || leadingNumber(in: title, dotted: false) == query.canonical
        }
    }

    /// A body line is a heading only when it opens with a unit label or a short
    /// title. A numbered sentence ("2 Integrals appear here.") is not one, nor
    /// is a math fragment ("4 be the", "1 + z") or a prose sentence
    /// ("Section 4 constructs the metric.").
    private static func matchesHeadingLine(_ line: String) -> Bool {
        guard isTitleLine(line), !line.lowercased().hasPrefix("part") else { return false }
        if number(in: line, pattern: chapterKeyword) != nil { return true }
        if number(in: line, pattern: partKeyword) != nil { return true }
        if number(in: line, pattern: sectionKeyword) != nil { return true }
        if let dotted = leadingNumber(in: line, dotted: true) {
            return titleTextFollows(line, number: dotted)
        }
        if let arabic = leadingNumber(in: line, dotted: false),
           let value = Int(arabic),
           (1...40).contains(value) {
            return titleTextFollows(line, number: arabic)
        }
        return leadingRoman(in: line) != nil
    }

    /// The text after the number has to open with a capital. "4. Block-sum"
    /// does. "4 be the" and "1 + z" do not.
    private static func titleTextFollows(_ line: String, number: String) -> Bool {
        var rest = line.trimmingCharacters(in: .whitespaces)
        if rest.hasPrefix("§") {
            rest = String(rest.dropFirst()).trimmingCharacters(in: .whitespaces)
        }
        guard rest.hasPrefix(number) else { return false }
        rest = String(rest.dropFirst(number.count))
        if rest.hasPrefix(".") {
            rest = String(rest.dropFirst())
        }
        rest = rest.trimmingCharacters(in: .whitespaces)
        guard let first = rest.first else { return false }
        return first.isLetter && first.isUppercase
    }

    private static func isTitleLine(_ line: String) -> Bool {
        let words = line.split(whereSeparator: \.isWhitespace)
        guard (1...8).contains(words.count) else { return false }
        let stripped = line.trimmingCharacters(in: .whitespaces)
        if stripped.hasSuffix("?") || stripped.hasSuffix("!") { return false }
        // amsart prints "3.1. From somewhere." The period closes the heading.
        // "2 Integrals appear here." has no period after the opening number.
        if stripped.hasSuffix(".") {
            return line.range(
                of: #"^\s*\d+(?:\.\d+)*\.\s+\S"#,
                options: .regularExpression
            ) != nil
        }
        return true
    }

    private static func headingRank(_ title: String) -> Int {
        let lower = title.lowercased()
        if lower.range(of: #"(?i)\bpart\b"#, options: .regularExpression) != nil { return 0 }
        if lower.range(of: #"(?i)\b(?:chapter|chap\.?|ch\.?)\b"#, options: .regularExpression) != nil { return 1 }
        if let number = leadingNumber(in: title, dotted: true) ?? leadingNumber(in: title, dotted: false) {
            return number.split(separator: ".").count + 1
        }
        return 6
    }

    private static func displayLabel(_ title: String, kind: StructuralQuery.Kind? = nil) -> String? {
        var cleaned = title.trimmingCharacters(in: .whitespacesAndNewlines)
        cleaned = cleaned.replacingOccurrences(of: #"\s*\.{2,}\s*\d*$"#, with: "", options: .regularExpression)
        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return nil }
        if cleaned.hasPrefix("§") { return cleaned }
        let treatAsSection = kind == .section || leadingNumber(in: cleaned, dotted: true) != nil
        if treatAsSection, cleaned.first?.isNumber == true {
            return "§\(cleaned)"
        }
        return cleaned
    }

    private static func contentsEntry(_ line: String) -> (title: String, printedPage: Int)? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard let regex = try? NSRegularExpression(pattern: #"^(.{3,90}?)(?:\s*\.{2,}|\s{2,})\s*(\d{1,4})\s*$"#) else {
            return nil
        }
        let ns = trimmed as NSString
        guard let match = regex.firstMatch(in: trimmed, range: NSRange(location: 0, length: ns.length)),
              let titleRange = Range(match.range(at: 1), in: trimmed),
              let pageRange = Range(match.range(at: 2), in: trimmed),
              let page = Int(trimmed[pageRange]) else { return nil }
        let title = trimmed[titleRange].trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else { return nil }
        return (title, page)
    }

    private static func number(in title: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let ns = title as NSString
        guard let match = regex.firstMatch(in: title, range: NSRange(location: 0, length: ns.length)),
              let range = Range(match.range(at: 1), in: title) else { return nil }
        return canonicalNumber(String(title[range]))
    }

    private static func leadingNumber(in title: String, dotted: Bool) -> String? {
        let pattern = dotted
            ? #"^\s*§?\s*(\d+(?:\.\d+)+)(?!\.\d)\b"#
            : #"^\s*(\d+)(?!\.\d)(?:\s|\.(?!\d)|$)"#
        return number(in: title, pattern: pattern)
    }

    private static func leadingRoman(in title: String) -> String? {
        number(in: title, pattern: #"^\s*([IVXLCDM]+)(?=\s|\.|$)"#)
    }

    private static func canonicalNumber(_ raw: String) -> String? {
        let token = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
        if token.range(of: #"^\d+(?:\.\d+)*$"#, options: .regularExpression) != nil {
            return token
        }
        if let value = romanValue(token) {
            return String(value)
        }
        return nil
    }

    private static func romanValue(_ token: String) -> Int? {
        let map: [Character: Int] = ["I": 1, "V": 5, "X": 10, "L": 50, "C": 100, "D": 500, "M": 1000]
        let letters = token.uppercased()
        guard !letters.isEmpty, letters.allSatisfy({ map[$0] != nil }) else { return nil }
        var total = 0
        var previous = 0
        for character in letters.reversed() {
            let value = map[character] ?? 0
            if value < previous {
                total -= value
            } else {
                total += value
                previous = value
            }
        }
        return (1...40).contains(total) ? total : nil
    }

    private static func prose(_ text: String) -> String {
        text.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private static func clipped(_ text: String, to budget: Int) -> String {
        guard text.count > budget else { return text }
        return String(text.prefix(max(0, budget)))
    }

    @MainActor
    private static func outlineNodes(_ outline: PDFOutline?, document: PDFDocument) -> [AskOutlineNode] {
        guard let outline else { return [] }
        return (0..<outline.numberOfChildren).compactMap { index in
            guard let child = outline.child(at: index) else { return nil }
            return AskOutlineNode(
                title: child.label ?? "",
                pageIndex: pageIndex(of: child, in: document),
                children: outlineNodes(child, document: document)
            )
        }
    }

    @MainActor
    private static func pageIndex(of outline: PDFOutline, in document: PDFDocument) -> Int {
        let destination = outline.destination ?? (outline.action as? PDFActionGoTo)?.destination
        guard let page = destination?.page else { return -1 }
        let index = document.index(for: page)
        return index == NSNotFound ? -1 : index
    }
}
