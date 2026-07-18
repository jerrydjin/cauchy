import Foundation

struct IndexedReference: Equatable, Sendable, Codable {
    let reference: DetectedReference
    let formattedBody: String
    let pageIndex: Int
    /// The printed title, e.g. "Compactness" for "Definition 3.2 (Compactness)".
    /// nil when the notes give no name (or the entry predates schema v4).
    let name: String?

    init(reference: DetectedReference, formattedBody: String, pageIndex: Int, name: String? = nil) {
        self.reference = reference
        self.formattedBody = formattedBody
        self.pageIndex = pageIndex
        self.name = name
    }

    var documentBlock: DocumentBlock {
        DocumentBlock(reference: reference, formattedBody: formattedBody, pageIndex: pageIndex)
    }

    /// "Definition 3.2 (Compactness), p. 41" — used when injecting the
    /// statement into an assistant prompt.
    var promptHeading: String {
        let title = name.map { " (\($0))" } ?? ""
        return "\(reference.displayName)\(title), p. \(pageIndex + 1)"
    }
}

struct DocumentBlock: Equatable, Sendable {
    let reference: DetectedReference
    let formattedBody: String
    let pageIndex: Int

    var title: String { reference.displayName }

    init(reference: DetectedReference, formattedBody: String, pageIndex: Int) {
        self.reference = reference
        self.formattedBody = formattedBody
        self.pageIndex = pageIndex
    }

    init(from indexed: IndexedReference) {
        self.reference = indexed.reference
        self.formattedBody = indexed.formattedBody
        self.pageIndex = indexed.pageIndex
    }
}
