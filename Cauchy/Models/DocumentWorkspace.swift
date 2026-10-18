import CoreGraphics
import Foundation

enum WorkspaceLayoutMode: String, Codable, Sendable {
    case split
    case overlay
}

struct DocumentWorkspace: Identifiable, Codable, Sendable {
    var id: UUID
    var documentURL: URL
    var highlights: [Highlight]
    var learningSessions: [LearningSession]
    var learningStudyMap: LearningStudyMap?
    var primaryViewport: ViewportState
    var secondaryViewport: ViewportState
    var layoutMode: WorkspaceLayoutMode
    var sidebarWidth: CGFloat
    var contextPanelWidth: CGFloat
    var lastOpenedAt: Date
    /// Whole-document Ask thread. Empty until the reader asks without a highlight.
    var documentConversationID: UUID
    var documentConversation: [ThreadMessage]

    init(
        id: UUID = UUID(),
        documentURL: URL,
        highlights: [Highlight] = [],
        learningSessions: [LearningSession] = [],
        learningStudyMap: LearningStudyMap? = nil,
        primaryViewport: ViewportState = .default,
        secondaryViewport: ViewportState = .default,
        layoutMode: WorkspaceLayoutMode = .split,
        sidebarWidth: CGFloat = 280,
        contextPanelWidth: CGFloat = 380,
        lastOpenedAt: Date = Date(),
        documentConversationID: UUID = UUID(),
        documentConversation: [ThreadMessage] = []
    ) {
        self.id = id
        self.documentURL = documentURL
        self.highlights = highlights
        self.learningSessions = learningSessions
        self.learningStudyMap = learningStudyMap
        self.primaryViewport = primaryViewport
        self.secondaryViewport = secondaryViewport
        self.layoutMode = layoutMode
        self.sidebarWidth = sidebarWidth
        self.contextPanelWidth = contextPanelWidth
        self.lastOpenedAt = lastOpenedAt
        self.documentConversationID = documentConversationID
        self.documentConversation = documentConversation
    }

    enum CodingKeys: String, CodingKey {
        case id
        case documentURL
        case highlights
        case learningSessions
        case learningStudyMap
        case pins
        case links
        case primaryViewport
        case secondaryViewport
        case layoutMode
        case sidebarWidth
        case contextPanelWidth
        case lastOpenedAt
        case documentConversationID
        case documentConversation
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        documentURL = try container.decode(URL.self, forKey: .documentURL)
        learningSessions = try container.decodeIfPresent([LearningSession].self, forKey: .learningSessions) ?? []
        learningStudyMap = try container.decodeIfPresent(LearningStudyMap.self, forKey: .learningStudyMap)
        primaryViewport = try container.decodeIfPresent(ViewportState.self, forKey: .primaryViewport) ?? .default
        secondaryViewport = try container.decodeIfPresent(ViewportState.self, forKey: .secondaryViewport) ?? .default
        layoutMode = try container.decodeIfPresent(WorkspaceLayoutMode.self, forKey: .layoutMode) ?? .split
        sidebarWidth = try container.decodeIfPresent(CGFloat.self, forKey: .sidebarWidth) ?? 280
        contextPanelWidth = try container.decodeIfPresent(CGFloat.self, forKey: .contextPanelWidth) ?? 380
        lastOpenedAt = try container.decodeIfPresent(Date.self, forKey: .lastOpenedAt) ?? Date()
        documentConversationID = try container.decodeIfPresent(UUID.self, forKey: .documentConversationID) ?? UUID()
        documentConversation = try container.decodeIfPresent([ThreadMessage].self, forKey: .documentConversation) ?? []

        if let decoded = try container.decodeIfPresent([Highlight].self, forKey: .highlights) {
            highlights = decoded
        } else if let legacyPins = try container.decodeIfPresent([ReferencePin].self, forKey: .pins) {
            highlights = legacyPins.map { Highlight.fromLegacyPin($0) }
        } else {
            highlights = []
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(documentURL, forKey: .documentURL)
        try container.encode(highlights, forKey: .highlights)
        try container.encode(learningSessions, forKey: .learningSessions)
        try container.encodeIfPresent(learningStudyMap, forKey: .learningStudyMap)
        try container.encode(primaryViewport, forKey: .primaryViewport)
        try container.encode(secondaryViewport, forKey: .secondaryViewport)
        try container.encode(layoutMode, forKey: .layoutMode)
        try container.encode(sidebarWidth, forKey: .sidebarWidth)
        try container.encode(contextPanelWidth, forKey: .contextPanelWidth)
        try container.encode(lastOpenedAt, forKey: .lastOpenedAt)
        try container.encode(documentConversationID, forKey: .documentConversationID)
        try container.encode(documentConversation, forKey: .documentConversation)
    }
}

struct SelectionCapture: Sendable {
    let pageIndex: Int
    let bounds: NormalizedRect
    let viewRect: CGRect
}
