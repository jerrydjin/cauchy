import Foundation

enum ThreadRole: String, Codable, Sendable {
    case user
    case assistant
}

struct ThreadMessage: Identifiable, Codable, Equatable, Sendable {
    var id: UUID
    var role: ThreadRole
    var content: String
    var createdAt: Date

    init(id: UUID = UUID(), role: ThreadRole, content: String, createdAt: Date = Date()) {
        self.id = id
        self.role = role
        self.content = content
        self.createdAt = createdAt
    }
}

struct SelectionThread: Equatable, Sendable {
    var anchorID: UUID
    var pageIndex: Int
    var selectedText: String
    var surroundingText: String
    var bounds: NormalizedRect?
    var lineBounds: [NormalizedRect]?
    var messages: [ThreadMessage]
    var isPersisted: Bool
    var streamingAssistantText: String?

    init(
        anchorID: UUID,
        pageIndex: Int,
        selectedText: String,
        surroundingText: String,
        bounds: NormalizedRect? = nil,
        lineBounds: [NormalizedRect]? = nil,
        messages: [ThreadMessage] = [],
        isPersisted: Bool = false,
        streamingAssistantText: String? = nil
    ) {
        self.anchorID = anchorID
        self.pageIndex = pageIndex
        self.selectedText = selectedText
        self.surroundingText = surroundingText
        self.bounds = bounds
        self.lineBounds = lineBounds
        self.messages = messages
        self.isPersisted = isPersisted
        self.streamingAssistantText = streamingAssistantText
    }

    var anchor: TextAnchor {
        TextAnchor(
            id: anchorID,
            pageIndex: pageIndex,
            bounds: bounds,
            selectedText: selectedText,
            surroundingText: surroundingText
        )
    }
}

struct TextSelectionContext: Sendable, Equatable {
    let pageIndex: Int
    let selectedText: String
    let surroundingText: String
    let fingerprint: String
    let bounds: NormalizedRect?
    let lineBounds: [NormalizedRect]?

    var anchor: TextAnchor {
        TextAnchor(
            pageIndex: pageIndex,
            bounds: bounds,
            selectedText: selectedText,
            surroundingText: surroundingText
        )
    }
}
