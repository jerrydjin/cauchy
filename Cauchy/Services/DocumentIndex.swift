import Foundation

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
}
