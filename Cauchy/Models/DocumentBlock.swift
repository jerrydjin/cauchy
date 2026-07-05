import Foundation

struct IndexedReference: Equatable, Sendable, Codable {
    let reference: DetectedReference
    let formattedBody: String
    let pageIndex: Int

    var documentBlock: DocumentBlock {
        DocumentBlock(reference: reference, formattedBody: formattedBody, pageIndex: pageIndex)
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
