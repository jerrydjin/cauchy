import Foundation

/// A byte-for-byte text-layer span, rechecked against the live PDF before a
/// saved answer may offer it as a clickable location. UTF-16 matches PDFKit.
struct PDFTextLocation: Sendable, Equatable {
    let pageIndex: Int
    let matchedText: String
    let startOffset: Int
    let endOffset: Int
}

struct DocumentPassage: Sendable, Equatable {
    let text: String
    /// nil when an implementation cannot prove a unique source span.
    let location: PDFTextLocation?
}

/// Ask-time passage retrieval over the open document. Implemented by
/// LexicalDocumentIndex; kept as a protocol so view models stay testable.
protocol DocumentIndexProtocol: Sendable {
    /// Top passages relevant to the query, formatted with page attribution
    /// ("[p. 12] …"). `excludingPage` drops chunks from the page the user is
    /// already reading (its text is in the prompt as surrounding context).
    func passages(matching query: String, limit: Int, excludingPage: Int?) -> [String]

    /// Hybrid variant: implementations that hold chunk embeddings fuse lexical
    /// and semantic rankings when a query embedding is supplied. Defaults to
    /// the lexical-only method.
    func passages(
        matching query: String,
        queryVector: [Float]?,
        limit: Int,
        excludingPage: Int?
    ) -> [String]

    /// Same ranked passages, with strict source spans when available. Older
    /// or test implementations may return nil locations rather than inventing
    /// coordinates from a page label.
    func passageRecords(
        matching query: String,
        queryVector: [Float]?,
        limit: Int,
        excludingPage: Int?
    ) -> [DocumentPassage]
}

extension DocumentIndexProtocol {
    func passages(
        matching query: String,
        queryVector: [Float]?,
        limit: Int,
        excludingPage: Int?
    ) -> [String] {
        passages(matching: query, limit: limit, excludingPage: excludingPage)
    }

    func passageRecords(
        matching query: String,
        queryVector: [Float]?,
        limit: Int,
        excludingPage: Int?
    ) -> [DocumentPassage] {
        passages(matching: query, queryVector: queryVector, limit: limit, excludingPage: excludingPage)
            .map { DocumentPassage(text: $0, location: nil) }
    }
}
