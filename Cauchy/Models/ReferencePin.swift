import Foundation

struct ReferencePin: Identifiable, Codable, Equatable, Sendable {
    var id: UUID
    var pageIndex: Int
    var bounds: NormalizedRect
    var label: String
    var category: PinCategory
    var createdAt: Date
    var thumbnailPath: String?
    var extractedText: String?
    var latexSnippet: String?

    init(
        id: UUID = UUID(),
        pageIndex: Int,
        bounds: NormalizedRect,
        label: String,
        category: PinCategory,
        createdAt: Date = Date(),
        thumbnailPath: String? = nil,
        extractedText: String? = nil,
        latexSnippet: String? = nil
    ) {
        self.id = id
        self.pageIndex = pageIndex
        self.bounds = bounds
        self.label = label
        self.category = category
        self.createdAt = createdAt
        self.thumbnailPath = thumbnailPath
        self.extractedText = extractedText
        self.latexSnippet = latexSnippet
    }
}
