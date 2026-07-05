import Foundation

struct Highlight: Identifiable, Codable, Equatable, Sendable {
    var id: UUID
    var pageIndex: Int
    var bounds: NormalizedRect?
    var lineBounds: [NormalizedRect]?
    var selectedText: String
    var surroundingText: String
    var label: String
    var note: String?
    var messages: [ThreadMessage]
    var isPinned: Bool
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        pageIndex: Int,
        bounds: NormalizedRect? = nil,
        lineBounds: [NormalizedRect]? = nil,
        selectedText: String,
        surroundingText: String? = nil,
        label: String? = nil,
        note: String? = nil,
        messages: [ThreadMessage] = [],
        isPinned: Bool = false,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.pageIndex = pageIndex
        self.bounds = bounds
        self.lineBounds = lineBounds
        self.selectedText = selectedText
        self.surroundingText = surroundingText ?? selectedText
        self.label = label ?? Self.defaultLabel(from: selectedText)
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
        case id, pageIndex, bounds, lineBounds, selectedText, surroundingText, label, note, messages
        case isPinned, createdAt, updatedAt
        case excerpt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        pageIndex = try container.decode(Int.self, forKey: .pageIndex)
        bounds = try container.decodeIfPresent(NormalizedRect.self, forKey: .bounds)
        lineBounds = try container.decodeIfPresent([NormalizedRect].self, forKey: .lineBounds)
        label = try container.decode(String.self, forKey: .label)
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
        try container.encodeIfPresent(lineBounds, forKey: .lineBounds)
        try container.encode(selectedText, forKey: .selectedText)
        try container.encode(surroundingText, forKey: .surroundingText)
        try container.encode(label, forKey: .label)
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
