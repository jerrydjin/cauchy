import Foundation

/// One painted line of a highlight, carrying the page it falls on. A selection
/// dragged across a page break puts its lines on more than one page, so a line
/// cannot inherit the highlight's anchor page.
struct HighlightLine: Codable, Equatable, Sendable {
    var pageIndex: Int
    var rect: NormalizedRect
}

struct Highlight: Identifiable, Codable, Equatable, Sendable {
    var id: UUID
    /// The page the highlight starts on — where the sidebar files it and where
    /// navigation lands. `lines` is what says where it is actually painted.
    var pageIndex: Int
    var bounds: NormalizedRect?
    var lines: [HighlightLine]?
    var selectedText: String
    var surroundingText: String
    var label: String
    /// A short name for the conversation, written by the model once the first
    /// answer lands. nil until then (and for threads that were never asked),
    /// where `displayName` falls back to the passage.
    var title: String?
    var note: String?
    var messages: [ThreadMessage]
    var isPinned: Bool
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        pageIndex: Int,
        bounds: NormalizedRect? = nil,
        lines: [HighlightLine]? = nil,
        selectedText: String,
        surroundingText: String? = nil,
        label: String? = nil,
        title: String? = nil,
        note: String? = nil,
        messages: [ThreadMessage] = [],
        isPinned: Bool = false,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.pageIndex = pageIndex
        self.bounds = bounds
        self.lines = lines
        self.selectedText = selectedText
        self.surroundingText = surroundingText ?? selectedText
        self.label = label ?? Self.defaultLabel(from: selectedText)
        self.title = title
        self.note = note
        self.messages = messages
        self.isPinned = isPinned
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    init(from anchor: TextAnchor, messages: [ThreadMessage] = [], isPinned: Bool = false) {
        self.init(
            id: anchor.id,
            pageIndex: anchor.pageIndex,
            bounds: anchor.bounds,
            selectedText: anchor.selectedText,
            surroundingText: anchor.surroundingText,
            messages: messages,
            isPinned: isPinned,
            createdAt: anchor.createdAt,
            updatedAt: anchor.updatedAt
        )
    }

    var anchor: TextAnchor {
        TextAnchor(
            id: id,
            pageIndex: pageIndex,
            bounds: bounds,
            selectedText: selectedText,
            surroundingText: surroundingText,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    enum CodingKeys: String, CodingKey {
        case id, pageIndex, bounds, lines, selectedText, surroundingText, label, title, note, messages
        case isPinned, createdAt, updatedAt
        case excerpt
        /// Pre-cross-page line rects, all of them implicitly on `pageIndex`.
        case lineBounds
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        let decodedPageIndex = try container.decode(Int.self, forKey: .pageIndex)
        pageIndex = decodedPageIndex
        bounds = try container.decodeIfPresent(NormalizedRect.self, forKey: .bounds)
        if let lines = try container.decodeIfPresent([HighlightLine].self, forKey: .lines) {
            self.lines = lines
        } else if let legacy = try container.decodeIfPresent([NormalizedRect].self, forKey: .lineBounds) {
            self.lines = legacy.map { HighlightLine(pageIndex: decodedPageIndex, rect: $0) }
        } else {
            lines = nil
        }
        label = try container.decode(String.self, forKey: .label)
        title = try container.decodeIfPresent(String.self, forKey: .title)
        note = try container.decodeIfPresent(String.self, forKey: .note)
        messages = try container.decodeIfPresent([ThreadMessage].self, forKey: .messages) ?? []
        isPinned = try container.decodeIfPresent(Bool.self, forKey: .isPinned) ?? true
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? createdAt

        if let selected = try container.decodeIfPresent(String.self, forKey: .selectedText) {
            selectedText = selected
            surroundingText = try container.decodeIfPresent(String.self, forKey: .surroundingText) ?? selected
        } else {
            let legacyExcerpt = try container.decode(String.self, forKey: .excerpt)
            selectedText = legacyExcerpt
            surroundingText = legacyExcerpt
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(pageIndex, forKey: .pageIndex)
        try container.encodeIfPresent(bounds, forKey: .bounds)
        try container.encodeIfPresent(lines, forKey: .lines)
        try container.encode(selectedText, forKey: .selectedText)
        try container.encode(surroundingText, forKey: .surroundingText)
        try container.encode(label, forKey: .label)
        try container.encodeIfPresent(title, forKey: .title)
        try container.encodeIfPresent(note, forKey: .note)
        try container.encode(messages, forKey: .messages)
        try container.encode(isPinned, forKey: .isPinned)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
    }

    static func defaultLabel(from text: String) -> String {
        let line = text
            .components(separatedBy: .newlines)
            .first { !$0.trimmingCharacters(in: .whitespaces).isEmpty } ?? "Highlight"
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count > 48 {
            return String(trimmed.prefix(45)) + "…"
        }
        return trimmed
    }

    /// What to call this thread in a list. The model writes a real name once
    /// the first answer lands; until then the raw question stands in, because a
    /// row with no name at all is worse than a literal one. An unasked
    /// highlight is named by its passage.
    var displayName: String {
        if let title, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return title
        }
        let question = messages
            .first { $0.role == .user && !$0.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }?
            .content
        return Self.title(from: question ?? label)
    }

    /// Collapses a passage into a single tidy line: no runs of whitespace, no
    /// trailing sentence punctuation, and cut at a word boundary rather than
    /// mid-word.
    static func title(from text: String, limit: Int = 60) -> String {
        let collapsed = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        let trimmed = collapsed.trimmingCharacters(in: CharacterSet(charactersIn: ".,;:—- "))
        guard trimmed.count > limit else {
            return trimmed.isEmpty ? "Highlight" : trimmed
        }
        let clipped = trimmed.prefix(limit)
        guard let lastSpace = clipped.lastIndex(of: " ") else { return clipped + "…" }
        return clipped[..<lastSpace] + "…"
    }

    static func fromLegacyPin(_ pin: ReferencePin) -> Highlight {
        let text = pin.extractedText ?? pin.label
        return Highlight(
            id: pin.id,
            pageIndex: pin.pageIndex,
            bounds: pin.bounds,
            selectedText: text,
            surroundingText: text,
            label: pin.label,
            note: nil,
            messages: [],
            isPinned: true,
            createdAt: pin.createdAt,
            updatedAt: pin.createdAt
        )
    }
}
