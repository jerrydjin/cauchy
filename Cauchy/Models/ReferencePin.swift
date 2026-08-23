import Foundation

struct ReferencePin: Identifiable, Codable, Equatable, Sendable {
    var id: UUID
    var pageIndex: Int
    var bounds: NormalizedRect
    var label: String
    /// Kept only so old sidecars keep decoding. Nothing reads it: the pin
    /// categories were never surfaced, and migration folds every pin into a
    /// plain highlight.
    var category: String?
    var createdAt: Date
    var thumbnailPath: String?
    var extractedText: String?
    var latexSnippet: String?

    init(
        id: UUID = UUID(),
        pageIndex: Int,
        bounds: NormalizedRect,
        label: String,
        category: String? = nil,
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
