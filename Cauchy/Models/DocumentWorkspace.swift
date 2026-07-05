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
    var primaryViewport: ViewportState
    var secondaryViewport: ViewportState
    var layoutMode: WorkspaceLayoutMode
    var sidebarWidth: CGFloat
    var contextPanelWidth: CGFloat
    var lastOpenedAt: Date

    init(
        id: UUID = UUID(),
        documentURL: URL,
        highlights: [Highlight] = [],
        primaryViewport: ViewportState = .default,
        secondaryViewport: ViewportState = .default,
        layoutMode: WorkspaceLayoutMode = .split,
        sidebarWidth: CGFloat = 280,
        contextPanelWidth: CGFloat = 380,
        lastOpenedAt: Date = Date()
    ) {
        self.id = id
        self.documentURL = documentURL
        self.highlights = highlights
        self.primaryViewport = primaryViewport
        self.secondaryViewport = secondaryViewport
        self.layoutMode = layoutMode
        self.sidebarWidth = sidebarWidth
        self.contextPanelWidth = contextPanelWidth
        self.lastOpenedAt = lastOpenedAt
    }

    enum CodingKeys: String, CodingKey {
        case id
        case documentURL
        case highlights
        case pins
        case links
        case primaryViewport
        case secondaryViewport
        case layoutMode
        case sidebarWidth
        case contextPanelWidth
        case lastOpenedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        documentURL = try container.decode(URL.self, forKey: .documentURL)
        primaryViewport = try container.decodeIfPresent(ViewportState.self, forKey: .primaryViewport) ?? .default
        secondaryViewport = try container.decodeIfPresent(ViewportState.self, forKey: .secondaryViewport) ?? .default
        layoutMode = try container.decodeIfPresent(WorkspaceLayoutMode.self, forKey: .layoutMode) ?? .split
        sidebarWidth = try container.decodeIfPresent(CGFloat.self, forKey: .sidebarWidth) ?? 280
        contextPanelWidth = try container.decodeIfPresent(CGFloat.self, forKey: .contextPanelWidth) ?? 380
        lastOpenedAt = try container.decodeIfPresent(Date.self, forKey: .lastOpenedAt) ?? Date()

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
        try container.encode(primaryViewport, forKey: .primaryViewport)
        try container.encode(secondaryViewport, forKey: .secondaryViewport)
        try container.encode(layoutMode, forKey: .layoutMode)
        try container.encode(sidebarWidth, forKey: .sidebarWidth)
        try container.encode(contextPanelWidth, forKey: .contextPanelWidth)
        try container.encode(lastOpenedAt, forKey: .lastOpenedAt)
    }
}

struct SelectionCapture: Sendable {
    let pageIndex: Int
    let bounds: NormalizedRect
    let viewRect: CGRect
}
