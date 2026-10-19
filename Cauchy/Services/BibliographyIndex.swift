import Foundation

/// A citation of another paper. The named result, when there is one, lives in
/// that paper and must not open a statement in this one.
struct ExternalCitation: Equatable, Sendable {
    /// Bracket key such as "12" or "IK99". Nil for an author–year citation.
    var key: String?
    /// Family name in "(Smith 2019)" or "Smith et al. [2019]".
    var author: String?
    var year: String?
    /// Printed result inside the citation, such as "Lemma 1.15".
    var qualifier: String?
    var range: Range<String.Index>
}

struct BibliographyEntry: Equatable, Sendable {
    var key: String?
    var authors: String
    var title: String
    var year: String?

    /// Title on the first line, then "Authors, Year".
    var hoverBody: String {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanAuthors = authors.trimmingCharacters(in: .whitespacesAndNewlines)
        var byline = cleanAuthors
        if let year, !year.isEmpty {
            byline = byline.isEmpty ? year : "\(byline), \(year)"
        }
        return [cleanTitle, byline].filter { !$0.isEmpty }.joined(separator: "\n")
    }
}

enum BibliographyIndex {
    /// Hover text for one citation, or nil when this document has no matching
    /// entry. Several matches show nothing: a wrong entry is worse than none.
    static func hoverText(for citation: ExternalCitation, in entries: [BibliographyEntry]) -> String? {
        let matches = matching(citation, in: entries)
        let body = matches.count == 1 ? matches[0].hoverBody : ""
        guard !body.isEmpty else { return nil }
        guard let qualifier = citation.qualifier?.trimmingCharacters(in: .whitespacesAndNewlines),
              !qualifier.isEmpty else {
            return body
        }
        return "\(body)\n\(qualifier) in the cited paper"
    }

    static func entries(in documentText: String) -> [BibliographyEntry] {
        guard let body = referencesBody(in: documentText) else { return [] }
        var entries = bracketEntries(in: body)
        entries.append(contentsOf: authorYearEntries(in: body))
        return entries
    }

    private static func matching(
        _ citation: ExternalCitation,
        in entries: [BibliographyEntry]
    ) -> [BibliographyEntry] {
        if let author = citation.author, let year = citation.year {
            return entries.filter { entry in
                entry.year == year && authorAppears(author, in: entry.authors)
            }
        }
        if let key = citation.key {
            return entries.filter { $0.key?.caseInsensitiveCompare(key) == .orderedSame }
        }
        return []
    }

    private static func authorAppears(_ author: String, in authors: String) -> Bool {
        authors.range(of: #"\b\#(NSRegularExpression.escapedPattern(for: author))\b"#, options: .regularExpression) != nil
    }

    private static func referencesBody(in text: String) -> String? {
        let pattern = #"(?im)^[ \t]*(?:\d+(?:\.\d+)*\.?[ \t]+)?(?:references|bibliography)[ \t]*$"#
        guard let range = text.range(of: pattern, options: .regularExpression) else { return nil }
        let body = text[range.upperBound...]
        return body.isEmpty ? nil : String(body)
    }

    private static func bracketEntries(in body: String) -> [BibliographyEntry] {
        guard let regex = try? NSRegularExpression(
            pattern: #"(?m)^[ \t]*\[(\#(ReferenceParsing.bibliographyKey))\][ \t]*"#
        ) else { return [] }
        let ns = body as NSString
        let matches = regex.matches(in: body, range: NSRange(location: 0, length: ns.length))
        return matches.compactMap { match in
            guard let keyRange = Range(match.range(at: 1), in: body) else { return nil }
            let start = match.range.location + match.range.length
            let end = nextBracketStart(after: match, matches: matches) ?? ns.length
            guard end >= start else { return nil }
            let raw = ns.substring(with: NSRange(location: start, length: end - start))
            return describe(raw, key: String(body[keyRange]))
        }
    }

    private static func nextBracketStart(after match: NSTextCheckingResult, matches: [NSTextCheckingResult]) -> Int? {
        matches.first { $0.range.location > match.range.location }?.range.location
    }

    private static func authorYearEntries(in body: String) -> [BibliographyEntry] {
        guard let regex = try? NSRegularExpression(
            pattern: #"(?m)^([A-Z][^(\n]{1,120}?)\s*\(((?:19|20)\d{2})\)\.?\s*([^\n]+)"#
        ) else { return [] }
        let ns = body as NSString
        return regex.matches(in: body, range: NSRange(location: 0, length: ns.length)).compactMap { match in
            guard let authorRange = Range(match.range(at: 1), in: body),
                  let yearRange = Range(match.range(at: 2), in: body),
                  let titleRange = Range(match.range(at: 3), in: body) else { return nil }
            let authors = String(body[authorRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            let title = String(body[titleRange])
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "."))
            guard !authors.isEmpty, !title.isEmpty else { return nil }
            return BibliographyEntry(
                key: nil,
                authors: authors,
                title: title,
                year: String(body[yearRange])
            )
        }
    }

    private static let quotationMarks: [(open: Character, close: Character)] = [
        ("“", "”"),
        ("\"", "\""),
        ("«", "»"),
    ]

    private static func describe(_ raw: String, key: String) -> BibliographyEntry {
        let flat = raw
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let year = flat.range(of: #"(?:19|20)\d{2}"#, options: .regularExpression).map { String(flat[$0]) }
        if let quoted = quotedTitle(in: flat) {
            return BibliographyEntry(
                key: key,
                authors: authorsBefore(quoted.authorEnd, in: flat),
                title: quoted.title,
                year: year
            )
        }
        if let split = oxfordAuthorSplit(in: flat) {
            return BibliographyEntry(key: key, authors: split.authors, title: split.title, year: year)
        }
        let parts = flat.components(separatedBy: ", ")
        let authors = parts.first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let title = titleBeforeJournal(parts.dropFirst().first ?? "")
        if authors.isEmpty && title.isEmpty {
            return BibliographyEntry(key: key, authors: "", title: flat, year: year)
        }
        return BibliographyEntry(key: key, authors: authors, title: title, year: year)
    }

    /// A title in quotation marks stays intact when the author list itself contains commas.
    private static func quotedTitle(in text: String) -> (title: String, authorEnd: String.Index)? {
        for (open, close) in quotationMarks {
            guard let start = text.firstIndex(of: open) else { continue }
            let contentStart = text.index(after: start)
            guard contentStart < text.endIndex,
                  let end = text[contentStart...].firstIndex(of: close),
                  end > contentStart else { continue }
            var title = text[contentStart..<end].trimmingCharacters(in: .whitespacesAndNewlines)
            if title.hasSuffix("."), !title.hasSuffix("...") {
                title.removeLast()
            }
            guard !title.isEmpty else { continue }
            return (title, start)
        }
        return nil
    }

    private static func authorsBefore(_ index: String.Index, in text: String) -> String {
        text[..<index]
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: ".,;:"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// "A. One, B. Two, and C. Three. Title of the note. Journal …"
    /// The period after the last author is not a comma between authors.
    private static func oxfordAuthorSplit(in text: String) -> (authors: String, title: String)? {
        guard let regex = try? NSRegularExpression(
            pattern: #"^(.+,\s+and\s+(?:[A-Z]\.\s+)*[A-Z][\p{L}'’\-]+)\.\s+([A-Z].+)$"#
        ) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              let authorRange = Range(match.range(at: 1), in: text),
              let titleRange = Range(match.range(at: 2), in: text) else { return nil }
        let authors = String(text[authorRange]).trimmingCharacters(in: .whitespacesAndNewlines)
        let title = titleBeforeJournal(String(text[titleRange]))
        guard !authors.isEmpty, !title.isEmpty else { return nil }
        return (authors, title)
    }

    /// "Sample title. Sample J. 4 (2023)" keeps the title and drops the journal tail.
    private static func titleBeforeJournal(_ fragment: String) -> String {
        let trimmed = fragment.trimmingCharacters(in: .whitespacesAndNewlines)
        if let separator = trimmed.range(of: ". ") {
            let head = trimmed[..<separator.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
            if head.contains(where: \.isLetter) {
                return head
            }
        }
        return trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "."))
    }
}
