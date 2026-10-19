import Foundation

/// Cmd-F lookup for printed statements and section headings.
///
/// A kind-and-number query such as "Lemma 2" is answered from the index only.
/// Several matches stay listed; the reader jumps only when there is exactly one.
enum DocumentFind {
    struct Entry: Equatable, Sendable {
        var kind: ReferenceKind
        var number: String
        var name: String?
        var body: String
        var pageIndex: Int
        var anchor: String
    }

    struct Section: Equatable, Sendable {
        var number: String
        var title: String
        var pageIndex: Int
        var anchor: String
    }

    struct Hit: Equatable, Identifiable, Sendable {
        var id: String
        var group: String
        var label: String
        var firstLine: String
        var pageIndex: Int
        var anchor: String
    }

    struct Outcome: Equatable, Sendable {
        var hits: [Hit]
        var message: String?
        /// Kind-and-number queries do not fall through to a plain text search.
        var suppressesTextSearch: Bool

        var jumpsImmediately: Bool {
            suppressesTextSearch && message == nil && hits.count == 1
        }
    }

    struct Source: Sendable {
        var entries: [Entry]
        var pages: [String]
    }

    /// `2` matches `2` and `2.1`, and does not match `20` or `12`.
    static func number(_ number: String, extends query: String) -> Bool {
        number == query || number.hasPrefix(query + ".")
    }

    static func sections(in pages: [String]) -> [Section] {
        var found: [Section] = []
        for (index, page) in pages.enumerated() {
            if LLMReferenceIndexSupport.isLikelyTableOfContents(page) { continue }
            let nsPage = page as NSString
            for match in headingRegex.matches(in: page, range: NSRange(location: 0, length: nsPage.length)) {
                guard let numberRange = Range(match.range(at: 1), in: page),
                      let titleRange = Range(match.range(at: 2), in: page) else { continue }
                var title = String(page[titleRange]).trimmingCharacters(in: .whitespacesAndNewlines)
                if title.hasSuffix(".") {
                    title.removeLast()
                    title = title.trimmingCharacters(in: .whitespacesAndNewlines)
                }
                let words = title.split(whereSeparator: \.isWhitespace)
                guard (1...8).contains(words.count), title.contains(where: \.isLetter) else { continue }
                let number = String(page[numberRange])
                guard !found.contains(where: { $0.number == number }) else { continue }
                let anchor = nsPage.substring(with: match.range).trimmingCharacters(in: .whitespacesAndNewlines)
                found.append(Section(number: number, title: title, pageIndex: index, anchor: anchor))
            }
        }
        return found
    }

    static func search(query: String, entries: [Entry], sections: [Section]) -> Outcome {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return Outcome(hits: [], message: nil, suppressesTextSearch: false)
        }
        if let numbered = numberedQuery(in: trimmed) {
            let hits = hits(for: numbered, entries: entries, sections: sections)
            if hits.isEmpty {
                return Outcome(
                    hits: [],
                    message: "No \"\(numbered.display)\" in this document",
                    suppressesTextSearch: true
                )
            }
            return Outcome(hits: sort(hits), message: nil, suppressesTextSearch: true)
        }

        let named = entries.compactMap { entry -> Hit? in
            guard let name = entry.name, nameMatches(name, query: trimmed) else { return nil }
            return hit(for: entry)
        }
        return Outcome(hits: sort(named), message: nil, suppressesTextSearch: false)
    }

    /// One caption line in the find-results list, including the ellipsis when cut.
    static let previewCharacterLimit = 64

    static func firstLine(of body: String) -> String {
        let line = body.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        let collapsed = line.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        let repaired = TextLayerRepairs.apply(collapsed)
        guard repaired.count > previewCharacterLimit else { return repaired }
        let budget = previewCharacterLimit - 1
        var end = repaired.index(repaired.startIndex, offsetBy: budget)
        let head = repaired[..<end]
        if let space = head.lastIndex(of: " "),
           repaired.distance(from: repaired.startIndex, to: space) >= budget / 2 {
            end = space
        }
        return repaired[..<end].trimmingCharacters(in: .whitespaces) + "…"
    }

    // MARK: - Private

    private struct NumberedQuery {
        var kind: ReferenceKind?
        var number: String
        var name: String?
        var display: String
    }

    private static let headingRegex = try! NSRegularExpression(
        pattern: #"(?m)^[ \t]*(\d+(?:\.\d+)*)\.\s+(\S[^\n]*)$"#
    )
    private static let numberedRegex = try! NSRegularExpression(
        pattern: #"(?i)^\s*(theorems?|lemmas?|propositions?|corollaries|corollary|definitions?|exercises?|examples?|remarks?|proofs?|sections?)\s+(\d+(?:\.\d+)*)(?:\s*\(([^)]{1,80})\))?\s*$"#
    )
    private static let groupOrder = [
        "Theorems", "Lemmas", "Definitions", "Sections",
        "Propositions", "Corollaries", "Remarks", "Examples",
        "Exercises", "Proofs", "Figures", "Equations",
    ]

    private static func numberedQuery(in query: String) -> NumberedQuery? {
        let range = NSRange(query.startIndex..., in: query)
        guard let match = numberedRegex.firstMatch(in: query, range: range),
              let keywordRange = Range(match.range(at: 1), in: query),
              let numberRange = Range(match.range(at: 2), in: query) else { return nil }
        let keyword = String(query[keywordRange]).lowercased()
        let number = String(query[numberRange])
        let name: String?
        if match.range(at: 3).location != NSNotFound, let nameRange = Range(match.range(at: 3), in: query) {
            name = String(query[nameRange]).trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            name = nil
        }
        if keyword.hasPrefix("section") {
            let display = name.map { "Section \(number) (\($0))" } ?? "Section \(number)"
            return NumberedQuery(kind: nil, number: number, name: name, display: display)
        }
        guard let kind = ReferenceKind.fromKeyword(keyword) else { return nil }
        var display = "\(kind.displayName) \(number)"
        if let name, !name.isEmpty {
            display += " (\(name))"
        }
        return NumberedQuery(kind: kind, number: number, name: name, display: display)
    }

    private static func hits(for query: NumberedQuery, entries: [Entry], sections: [Section]) -> [Hit] {
        if query.kind == nil {
            return sections.compactMap { section in
                guard number(section.number, extends: query.number) else { return nil }
                if let name = query.name, !nameMatches(section.title, query: name) { return nil }
                return Hit(
                    id: "section-\(section.number)-\(section.pageIndex)",
                    group: "Sections",
                    label: "Section \(section.number)",
                    firstLine: firstLine(of: section.title),
                    pageIndex: section.pageIndex,
                    anchor: section.anchor
                )
            }
        }
        return entries.compactMap { entry in
            guard entry.kind == query.kind, number(entry.number, extends: query.number) else { return nil }
            if let name = query.name {
                guard let printed = entry.name, nameMatches(printed, query: name) else { return nil }
            }
            return hit(for: entry)
        }
    }

    private static func hit(for entry: Entry) -> Hit {
        var label = "\(entry.kind.displayName) \(entry.number)"
        if let name = entry.name, !name.isEmpty {
            label += " (\(name))"
        }
        let anchor = entry.anchor.isEmpty ? label : entry.anchor
        return Hit(
            id: "\(entry.kind.rawValue)-\(entry.number)-\(entry.pageIndex)",
            group: groupName(for: entry.kind),
            label: label,
            firstLine: firstLine(of: entry.body),
            pageIndex: entry.pageIndex,
            anchor: anchor
        )
    }

    private static func groupName(for kind: ReferenceKind) -> String {
        switch kind {
        case .theorem: "Theorems"
        case .lemma: "Lemmas"
        case .definition: "Definitions"
        case .proposition: "Propositions"
        case .corollary: "Corollaries"
        case .remark: "Remarks"
        case .example: "Examples"
        case .exercise: "Exercises"
        case .proof: "Proofs"
        case .figure: "Figures"
        case .equation: "Equations"
        }
    }

    private static func sort(_ hits: [Hit]) -> [Hit] {
        hits.sorted { lhs, rhs in
            let left = groupOrder.firstIndex(of: lhs.group) ?? groupOrder.count
            let right = groupOrder.firstIndex(of: rhs.group) ?? groupOrder.count
            if left != right { return left < right }
            let order = lhs.label.localizedStandardCompare(rhs.label)
            if order != .orderedSame { return order == .orderedAscending }
            return lhs.pageIndex < rhs.pageIndex
        }
    }

    private static func nameMatches(_ name: String, query: String) -> Bool {
        let token = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard token.count >= 2 else { return false }
        let pattern = "\\b\(NSRegularExpression.escapedPattern(for: token))\\b"
        return name.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }
}

/// Broken sequences the PDF text layer emits for ordinary math glyphs.
/// Literal rows run before regular expressions, longest literal first.
enum TextLayerRepairs {
    struct Substitution: Equatable {
        var broken: String
        var repaired: String
        var regularExpression: Bool = false
    }

    static let table: [Substitution] = [
        Substitution(broken: "7→", repaired: "↦"),
        Substitution(broken: #"∈(?=\S)"#, repaired: "∈ ", regularExpression: true),
    ]

    static func apply(_ text: String) -> String {
        let literals = table
            .filter { !$0.regularExpression }
            .sorted { $0.broken.count > $1.broken.count }
        let patterns = table.filter(\.regularExpression)
        var result = text
        for row in literals {
            result = result.replacingOccurrences(of: row.broken, with: row.repaired)
        }
        for row in patterns {
            result = result.replacingOccurrences(
                of: row.broken,
                with: row.repaired,
                options: .regularExpression
            )
        }
        return result
    }
}
