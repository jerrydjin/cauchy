import Foundation

/// Lookup for printed statements and section headings.
///
/// Cmd-F is a plain text search. Cmd-K jumps through this index. A kind-and-number
/// query such as "Lemma 2" is answered from the index only, and the set of hits
/// is the same one `search` has always returned.
enum DocumentFind {
    struct Entry: Equatable, Sendable {
        var kind: ReferenceKind
        var number: String
        var name: String?
        var body: String
        var pageIndex: Int
        var anchor: String
        /// PDF text layer for the statement. Previews fall back to it when the
        /// stored body is LaTeX or other markup.
        var sourceExcerpt: String? = nil
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
        /// Kind, number, and the longest real name. Sorting and tests use this.
        var label: String
        /// Kind and number, never truncated and never repeated in parentheses.
        var title: String
        /// Real names, longest first, then shorter alternatives and word prefixes.
        var nameCandidates: [String]
        /// Printed name, including one that repeats the label, for filtering.
        var jumpName: String
        var number: String
        var firstLine: String
        var pageIndex: Int
        var anchor: String
    }

    /// Names the jump row may draw. A cut-off phrase is omitted; indexing is unchanged.
    struct VisibleNames: Equatable, Sendable {
        var names: [String]
        /// A later candidate ended mid-phrase and was not included.
        var stoppedBeforeCutOff: Bool
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
        /// Changes when the document or the reference index changes.
        /// The jump palette reuses one built catalogue while this stays put.
        var catalogueID: Int = 0
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

    /// Every indexed statement, or the subset whose label, printed name, or
    /// one-line preview contains `query` as a case-insensitive substring.
    /// A kind-and-number query uses `search` unchanged. A bare number keeps
    /// the dotted-number rule (`2` matches `2.1`, not `20`).
    ///
    /// `catalogue`, when present, is the full sorted list from an empty query.
    /// Filtering that list reuses the rows already built — it does not parse
    /// previews again and it does not re-sort. `localizedStandardCompare` on
    /// every keystroke was the expensive part of an already-sorted catalogue.
    static func jumpHits(
        query: String,
        entries: [Entry],
        sections: [Section],
        catalogue: [Hit]? = nil
    ) -> [Hit] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if let catalogue {
            if trimmed.isEmpty { return catalogue }
            return filterCatalogue(catalogue, query: trimmed)
        }
        if trimmed.isEmpty {
            return sort(entries.map(hit(for:)) + sections.map(sectionHit))
        }
        if numberedQuery(in: trimmed) != nil {
            return search(query: trimmed, entries: entries, sections: sections).hits
        }
        let all = entries.map(hit(for:)) + sections.map(sectionHit)
        return sort(all.filter { matchesJump($0, query: trimmed) })
    }

    /// Folded fields for one catalogue row. Built once with the catalogue so a
    /// keystroke is a substring check, not a case-insensitive scan and a sort.
    struct JumpFilterKey: Equatable, Sendable {
        var group: String
        var number: String
        var label: String
        var jumpName: String
        var title: String
        var firstLine: String
    }

    /// Keys line up with `hits`. Group and number stay as indexed; the text
    /// fields are lowercased the same way the query is folded at match time.
    static func jumpFilterKeys(for hits: [Hit]) -> [JumpFilterKey] {
        hits.map { hit in
            JumpFilterKey(
                group: hit.group,
                number: hit.number,
                label: hit.label.lowercased(),
                jumpName: hit.jumpName.lowercased(),
                title: hit.title.lowercased(),
                firstLine: hit.firstLine.lowercased()
            )
        }
    }

    /// Rows of an already-sorted catalogue that match `query`, in that same
    /// order. Kind-and-number queries use the numbered rule (`2` matches `2.1`,
    /// not `20`) instead of rebuilding hits from the entry bodies.
    static func filterCatalogue(
        _ catalogue: [Hit],
        query: String,
        keys: [JumpFilterKey]? = nil
    ) -> [Hit] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return catalogue }
        if let numbered = numberedQuery(in: trimmed) {
            return catalogue.filter { matchesNumbered($0, query: numbered) }
        }
        if let keys, keys.count == catalogue.count {
            return filterFolded(catalogue, keys: keys, query: trimmed)
        }
        return catalogue.filter { matchesJump($0, query: trimmed) }
    }

    /// Cmd-F's count. "232 matches in the text", never a named-result count.
    static func textMatchLabel(count: Int, isSearching: Bool) -> String {
        if isSearching { return "Searching…" }
        if count <= 0 { return "Not found" }
        if count == 1 { return "1 match in the text" }
        return "\(count) matches in the text"
    }

    /// Names worth showing after the label. Empty when the parenthetical only
    /// repeats the label. Longest real name first, then shorter alternatives,
    /// then word prefixes of the longest name.
    static func displayNames(kind: ReferenceKind, number: String, name: String?) -> [String] {
        guard let raw = name?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return [] }
        let leaves = nameLeaves(raw)
        let anyLeafRepeatsLabel = leaves.contains { repeatsLabel($0, kind: kind, number: number) }
        var pieces = leaves
        if !anyLeafRepeatsLabel {
            pieces.append(raw)
        }
        var kept: [String] = []
        for piece in pieces {
            let trimmed = piece.trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: " .,:;"))
            guard trimmed.count >= 2 else { continue }
            guard !repeatsLabel(trimmed, kind: kind, number: number) else { continue }
            guard !kept.contains(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame }) else { continue }
            kept.append(trimmed)
        }
        kept.sort { lhs, rhs in
            if lhs.count != rhs.count { return lhs.count > rhs.count }
            return lhs.localizedStandardCompare(rhs) == .orderedAscending
        }
        guard let longest = kept.first else { return [] }
        let words = longest.split(separator: " ").map(String.init)
        if words.count > 1 {
            for end in stride(from: words.count - 1, through: 1, by: -1) {
                let prefix = words.prefix(end).joined(separator: " ")
                guard prefix.count >= 2 else { continue }
                guard !kept.contains(where: { $0.caseInsensitiveCompare(prefix) == .orderedSame }) else { continue }
                kept.append(prefix)
            }
        }
        return kept
    }

    /// Names the jump row may draw. Display only: `nameCandidates`, `label`,
    /// and `jumpName` stay as indexed so search and sorting are unchanged.
    ///
    /// A spacing accent the PDF text layer drew before its letter is composed
    /// here, so `Rouch´e` (U+00B4 before e) draws as Rouché. The indexed
    /// strings are left alone, including catalogues already on disk.
    ///
    /// A candidate that ends on a function word ("Homotopy Version of") is a
    /// phrase cut off mid-way. It is left out, and so is anything shorter,
    /// so the row shows the kind and number alone.
    static func namesForDisplay(_ names: [String]) -> VisibleNames {
        var kept: [String] = []
        for name in names {
            let decoded = DisplayAccentDecoding.compose(name)
            if nameEndsMidPhrase(decoded) {
                return VisibleNames(names: kept, stoppedBeforeCutOff: true)
            }
            if kept.contains(where: { $0.caseInsensitiveCompare(decoded) == .orderedSame }) {
                continue
            }
            kept.append(decoded)
        }
        return VisibleNames(names: kept, stoppedBeforeCutOff: false)
    }

    /// One caption line in the jump list, including the ellipsis when cut.
    static let previewCharacterLimit = 64

    static func firstLine(of body: String, sourceExcerpt: String? = nil) -> String {
        for source in [body, sourceExcerpt ?? ""] where !source.isEmpty {
            for line in source.split(whereSeparator: \.isNewline) {
                let collapsed = line.split(whereSeparator: \.isWhitespace).joined(separator: " ")
                guard !collapsed.isEmpty else { continue }
                let repaired = TextLayerRepairs.apply(collapsed)
                guard let plain = PreviewPlainText.readableLine(repaired) else { continue }
                return truncatePreview(plain)
            }
        }
        return ""
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
    private static let orSeparator = try! NSRegularExpression(pattern: #"(?i)\s+or\s+"#)
    private static let groupOrder = [
        "Theorems", "Lemmas", "Definitions", "Sections",
        "Propositions", "Corollaries", "Remarks", "Examples",
        "Exercises", "Proofs", "Figures", "Equations",
    ]

    private static func truncatePreview(_ repaired: String) -> String {
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
                return sectionHit(section)
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

    private static func sectionHit(_ section: Section) -> Hit {
        let title = "Section \(section.number)"
        return Hit(
            id: "section-\(section.number)-\(section.pageIndex)",
            group: "Sections",
            label: title,
            title: title,
            nameCandidates: [],
            jumpName: section.title,
            number: section.number,
            firstLine: firstLine(of: section.title),
            pageIndex: section.pageIndex,
            anchor: section.anchor
        )
    }

    private static func hit(for entry: Entry) -> Hit {
        let title = "\(entry.kind.displayName) \(entry.number)"
        let names = displayNames(kind: entry.kind, number: entry.number, name: entry.name)
        let label = names.first.map { "\(title) (\($0))" } ?? title
        let anchor = entry.anchor.isEmpty ? label : entry.anchor
        return Hit(
            id: "\(entry.kind.rawValue)-\(entry.number)-\(entry.pageIndex)",
            group: groupName(for: entry.kind),
            label: label,
            title: title,
            nameCandidates: names,
            jumpName: entry.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
            number: entry.number,
            firstLine: firstLine(of: entry.body, sourceExcerpt: entry.sourceExcerpt),
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

    /// Same rows `search` would rebuild for a kind-and-number query, read off
    /// the catalogue so the preview text is not parsed again.
    private static func matchesNumbered(_ hit: Hit, query: NumberedQuery) -> Bool {
        if let kind = query.kind {
            guard hit.group == groupName(for: kind) else { return false }
        } else {
            guard hit.group == "Sections" else { return false }
        }
        guard number(hit.number, extends: query.number) else { return false }
        if let name = query.name, !name.isEmpty {
            guard nameMatches(hit.jumpName, query: name) else { return false }
        }
        return true
    }

    /// `matchesJump` for text, against fields folded once when the catalogue
    /// was built. Kind and section words are decided once per keystroke.
    private static func filterFolded(
        _ catalogue: [Hit],
        keys: [JumpFilterKey],
        query: String
    ) -> [Hit] {
        let folded = query.lowercased()
        let kindGroup = ReferenceKind.fromKeyword(folded).map { groupName(for: $0) }
        let sectionWord = folded == "section" || folded == "sections"
        let numeric = isNumberToken(query)
        var matched: [Hit] = []
        matched.reserveCapacity(min(catalogue.count, 64))
        for (hit, key) in zip(catalogue, keys) {
            if let kindGroup, key.group == kindGroup {
                matched.append(hit)
                continue
            }
            if sectionWord, key.group == "Sections" {
                matched.append(hit)
                continue
            }
            if numeric {
                if containsWord(key.label, word: folded)
                    || containsWord(key.jumpName, word: folded)
                    || containsWord(key.title, word: folded)
                    || number(key.number, extends: query) {
                    matched.append(hit)
                }
                continue
            }
            guard folded.count >= 2 else { continue }
            if key.label.contains(folded)
                || key.jumpName.contains(folded)
                || key.title.contains(folded)
                || key.firstLine.contains(folded) {
                matched.append(hit)
            }
        }
        return matched
    }

    /// ASCII word boundary, matching the `\b` `nameMatches` uses for a number
    /// token. The field and the word are already lowercased.
    private static func containsWord(_ field: String, word: String) -> Bool {
        guard word.count >= 2, !field.isEmpty else { return false }
        var search = field.startIndex
        while let found = field.range(of: word, range: search..<field.endIndex) {
            let startsAtBoundary = found.lowerBound == field.startIndex
                || !isRegexWord(field[field.index(before: found.lowerBound)])
            let endsAtBoundary = found.upperBound == field.endIndex
                || !isRegexWord(field[found.upperBound])
            if startsAtBoundary && endsAtBoundary { return true }
            guard let next = field.index(found.lowerBound, offsetBy: 1, limitedBy: field.endIndex) else { break }
            search = next
        }
        return false
    }

    /// ICU `\w` without Unicode mode: ASCII letters, digits, and underscore.
    private static func isRegexWord(_ character: Character) -> Bool {
        guard character.unicodeScalars.count == 1, let value = character.unicodeScalars.first?.value else {
            return false
        }
        if value == 95 { return true }
        return (48...57).contains(value) || (65...90).contains(value) || (97...122).contains(value)
    }

    private static func matchesJump(_ hit: Hit, query: String) -> Bool {
        let token = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if let kind = ReferenceKind.fromKeyword(token.lowercased()), hit.group == groupName(for: kind) {
            return true
        }
        if token.compare("section", options: .caseInsensitive) == .orderedSame
            || token.compare("sections", options: .caseInsensitive) == .orderedSame {
            return hit.group == "Sections"
        }
        // A dotted number stays a prefix match. A substring would treat
        // 1.2.70 as a hit for 1.2.7, including when that string sits in a preview.
        if isNumberToken(token) {
            if nameMatches(hit.label, query: token) { return true }
            if nameMatches(hit.jumpName, query: token) { return true }
            if nameMatches(hit.title, query: token) { return true }
            return number(hit.number, extends: token)
        }
        if containsQuery(hit.label, query: token) { return true }
        if containsQuery(hit.jumpName, query: token) { return true }
        if containsQuery(hit.title, query: token) { return true }
        if containsQuery(hit.firstLine, query: token) { return true }
        return false
    }

    /// Case-insensitive substring against one visible field. One letter is
    /// too small: it would light up every English preview.
    private static func containsQuery(_ field: String, query: String) -> Bool {
        guard query.count >= 2, !field.isEmpty else { return false }
        return field.range(of: query, options: .caseInsensitive) != nil
    }

    private static let midPhraseWords: Set<String> = [
        "of", "the", "a", "an", "and", "for", "to", "in", "on", "with",
    ]

    /// The last word is a function word, so the phrase stops mid-way.
    private static func nameEndsMidPhrase(_ name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let last = trimmed.split(whereSeparator: \.isWhitespace).last else { return false }
        let word = last.trimmingCharacters(in: CharacterSet(charactersIn: ".,:;!?'\"“”"))
        guard !word.isEmpty else { return false }
        return midPhraseWords.contains(word.lowercased())
    }

    private static func isNumberToken(_ token: String) -> Bool {
        token.contains(where: \.isNumber) && token.allSatisfy { $0.isNumber || $0 == "." }
    }

    private static func nameMatches(_ name: String, query: String) -> Bool {
        let token = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard token.count >= 2 else { return false }
        let pattern = "\\b\(NSRegularExpression.escapedPattern(for: token))\\b"
        return name.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }

    /// The parenthetical repeats the label when, ignoring case and punctuation,
    /// it is the kind (or an abbreviation) plus the number, or the number alone.
    private static func repeatsLabel(_ name: String, kind: ReferenceKind, number: String) -> Bool {
        let key = alnum(name)
        guard !key.isEmpty else { return true }
        let numberKey = alnum(number)
        if key == numberKey { return true }
        for alias in kindAliases(kind) {
            let aliasKey = alnum(alias)
            if key == aliasKey || key == aliasKey + numberKey { return true }
        }
        return false
    }

    private static func kindAliases(_ kind: ReferenceKind) -> [String] {
        switch kind {
        case .theorem: ["theorem", "thm", "th"]
        case .lemma: ["lemma", "lem"]
        case .proposition: ["proposition", "prop"]
        case .corollary: ["corollary", "cor"]
        case .definition: ["definition", "defn", "def"]
        case .exercise: ["exercise", "exer"]
        case .example: ["example", "ex"]
        case .remark: ["remark", "rem"]
        case .proof: ["proof"]
        case .figure: ["figure", "fig"]
        case .equation: ["equation", "eq"]
        }
    }

    private static func alnum(_ text: String) -> String {
        String(text.lowercased().filter { $0.isLetter || $0.isNumber })
    }

    private static func nameLeaves(_ name: String) -> [String] {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        if let open = trimmed.firstIndex(of: "("),
           let close = trimmed[open...].lastIndex(of: ")"),
           trimmed.index(after: open) <= close {
            let outer = String(trimmed[..<open])
            let innerStart = trimmed.index(after: open)
            let inner = innerStart < close ? String(trimmed[innerStart..<close]) : ""
            return nameLeaves(outer) + nameLeaves(inner)
        }
        let parts = splitOr(trimmed)
        if parts.count > 1 {
            return parts.flatMap { nameLeaves($0) }
        }
        return [trimmed]
    }

    private static func splitOr(_ text: String) -> [String] {
        let range = NSRange(text.startIndex..., in: text)
        let matches = orSeparator.matches(in: text, range: range)
        guard !matches.isEmpty else { return [text] }
        var parts: [String] = []
        var cursor = text.startIndex
        for match in matches {
            guard let matchRange = Range(match.range, in: text) else { continue }
            parts.append(String(text[cursor..<matchRange.lowerBound]))
            cursor = matchRange.upperBound
        }
        parts.append(String(text[cursor...]))
        return parts
    }
}

/// Spacing accents a PDF text layer emits as their own character, in front of
/// the letter they belong on. TeX draws the accent glyph first; PDFKit then
/// returns "Rouch´e" instead of "Rouché". Composition is for drawing only.
enum DisplayAccentDecoding {
    static func compose(_ text: String) -> String {
        let scalars = Array(text.unicodeScalars)
        var composed: [Unicode.Scalar] = []
        composed.reserveCapacity(scalars.count)
        var index = 0
        while index < scalars.count {
            if let mark = combiningMark(forSpacing: scalars[index]),
               index + 1 < scalars.count,
               Character(scalars[index + 1]).isLetter {
                composed.append(contentsOf: precomposed(base: scalars[index + 1], mark: mark))
                index += 2
                continue
            }
            composed.append(scalars[index])
            index += 1
        }
        return String(String.UnicodeScalarView(composed)).precomposedStringWithCanonicalMapping
    }

    /// Spacing forms of the accents TeX constructs as a separate glyph.
    /// Already-combining marks are left where the text layer attached them.
    private static func combiningMark(forSpacing scalar: Unicode.Scalar) -> Unicode.Scalar? {
        switch scalar.value {
        case 0x00B4, 0x02CA: return Unicode.Scalar(0x0301) // ´ acute, ˊ modifier acute
        case 0x02CB: return Unicode.Scalar(0x0300) // ˋ modifier grave
        case 0x02C6: return Unicode.Scalar(0x0302) // ˆ modifier circumflex
        case 0x02DC: return Unicode.Scalar(0x0303) // ˜ small tilde
        case 0x00A8: return Unicode.Scalar(0x0308) // ¨ diaeresis
        case 0x02DA: return Unicode.Scalar(0x030A) // ˚ ring above
        case 0x02DD: return Unicode.Scalar(0x030B) // ˝ double acute
        case 0x02C7: return Unicode.Scalar(0x030C) // ˇ caron
        case 0x02D8: return Unicode.Scalar(0x0306) // ˘ breve
        case 0x00B8: return Unicode.Scalar(0x0327) // ¸ cedilla
        default: return nil
        }
    }

    private static func precomposed(base: Unicode.Scalar, mark: Unicode.Scalar) -> [Unicode.Scalar] {
        let pair = String(String.UnicodeScalarView([base, mark]))
        return Array(pair.precomposedStringWithCanonicalMapping.unicodeScalars)
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

/// Turns a statement line into plain text for the jump list.
///
/// `formattedBody` is often the model's LaTeX (`$\subset$`, `\gamma`, `\left`).
/// `JSONDecoder` also reads `\b` in `\boldsymbol` as a backspace, so the stored
/// body can contain `$oldsymbol{`. Lines that stay unreadable are skipped; the
/// caller then tries the next line and the PDF text layer.
enum PreviewPlainText {
    private static let symbols: [(String, String)] = [
        ("\\subseteq", "⊆"), ("\\supseteq", "⊇"), ("\\subset", "⊂"), ("\\supset", "⊃"),
        ("\\notin", "∉"), ("\\infty", "∞"), ("\\rightarrow", "→"), ("\\leftarrow", "←"),
        ("\\Rightarrow", "⇒"), ("\\Leftarrow", "⇐"), ("\\mapsto", "↦"),
        ("\\varepsilon", "ε"), ("\\varphi", "φ"), ("\\emptyset", "∅"),
        ("\\gamma", "γ"), ("\\Gamma", "Γ"), ("\\alpha", "α"), ("\\beta", "β"),
        ("\\delta", "δ"), ("\\epsilon", "ε"), ("\\lambda", "λ"), ("\\mu", "μ"),
        ("\\nu", "ν"), ("\\pi", "π"), ("\\rho", "ρ"), ("\\sigma", "σ"),
        ("\\tau", "τ"), ("\\phi", "φ"), ("\\omega", "ω"), ("\\Omega", "Ω"),
        ("\\theta", "θ"), ("\\to", "→"), ("\\leq", "≤"), ("\\geq", "≥"),
        ("\\neq", "≠"), ("\\approx", "≈"), ("\\equiv", "≡"), ("\\cdot", "·"),
        ("\\times", "×"), ("\\pm", "±"), ("\\partial", "∂"), ("\\forall", "∀"),
        ("\\exists", "∃"), ("\\cup", "∪"), ("\\cap", "∩"), ("\\nabla", "∇"),
        ("\\sum", "∑"), ("\\prod", "∏"), ("\\int", "∫"), ("\\in", "∈"),
        ("\\ldots", "…"), ("\\cdots", "⋯"), ("\\dots", "…"),
        ("\\le", "≤"), ("\\ge", "≥"), ("\\ne", "≠"),
    ]

    private static let sizing = [
        "\\Biggl", "\\Biggr", "\\biggl", "\\biggr", "\\Bigl", "\\Bigr",
        "\\bigl", "\\bigr", "\\left", "\\right", "\\Bigg", "\\bigg", "\\Big", "\\big",
    ]

    private static let fontUnwrap = try! NSRegularExpression(
        pattern: #"\\(?:boldsymbol|mathbf|mathrm|mathbb|mathcal|mathfrak|operatorname|textbf|textit|text|emph)\{([^{}]*)\}"#
    )

    static func readableLine(_ raw: String) -> String? {
        var text = raw.replacingOccurrences(of: "\u{8}oldsymbol", with: "\\boldsymbol")
        if text.contains("oldsymbol") && !text.contains("\\boldsymbol") {
            return nil
        }
        if text.unicodeScalars.contains(where: { value in
            let scalar = value.value
            return scalar < 32 && scalar != 9 && scalar != 10 && scalar != 13
        }) {
            return nil
        }

        for (command, symbol) in symbols.sorted(by: { $0.0.count > $1.0.count }) {
            let pattern = NSRegularExpression.escapedPattern(for: command) + "(?![A-Za-z])"
            text = text.replacingOccurrences(of: pattern, with: symbol, options: .regularExpression)
        }
        for _ in 0..<6 {
            let range = NSRange(text.startIndex..., in: text)
            let next = fontUnwrap.stringByReplacingMatches(in: text, range: range, withTemplate: "$1")
            if next == text { break }
            text = next
        }
        for command in sizing {
            let pattern = NSRegularExpression.escapedPattern(for: command) + "(?![A-Za-z])"
            text = text.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
        }
        for command in ["\\displaystyle", "\\textstyle", "\\scriptstyle", "\\scriptscriptstyle", "\\quad", "\\qquad"] {
            text = text.replacingOccurrences(of: command, with: " ")
        }
        for token in ["\\,", "\\;", "\\:", "\\!", "\\ ", "\\[", "\\]", "\\(", "\\)"] {
            text = text.replacingOccurrences(of: token, with: token == "\\!" ? "" : " ")
        }
        text = text.replacingOccurrences(of: "\\{", with: "{")
        text = text.replacingOccurrences(of: "\\}", with: "}")
        text = text.replacingOccurrences(of: "$$", with: "")
        text = text.replacingOccurrences(of: "$", with: "")

        if text.contains("\\") || text.contains("$") || text.contains("oldsymbol") || !bracesBalanced(text) {
            return nil
        }
        let collapsed = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard isReadable(collapsed) else { return nil }
        return collapsed
    }

    private static func bracesBalanced(_ text: String) -> Bool {
        var depth = 0
        for character in text {
            if character == "{" {
                depth += 1
            } else if character == "}" {
                depth -= 1
                if depth < 0 { return false }
            }
        }
        return depth == 0
    }

    private static func isReadable(_ text: String) -> Bool {
        guard !text.isEmpty, text != "$$", text != "$" else { return false }
        let letters = text.filter(\.isLetter).count
        guard letters >= 3 else { return false }
        let dense = text.filter { !$0.isWhitespace }.count
        return letters * 3 >= dense
    }
}
