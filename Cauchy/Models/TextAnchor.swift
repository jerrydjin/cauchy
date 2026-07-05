import Foundation

struct TextAnchor: Identifiable, Codable, Equatable, Sendable {
    var id: UUID
    var pageIndex: Int
    var bounds: NormalizedRect?
    var selectedText: String
    var surroundingText: String
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        pageIndex: Int,
        bounds: NormalizedRect? = nil,
        selectedText: String,
        surroundingText: String,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.pageIndex = pageIndex
        self.bounds = bounds
        self.selectedText = selectedText
        self.surroundingText = surroundingText
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    init(from context: TextSelectionContext) {
        self.init(
            pageIndex: context.pageIndex,
            bounds: context.bounds,
            selectedText: context.selectedText,
            surroundingText: context.surroundingText
        )
    }
}
