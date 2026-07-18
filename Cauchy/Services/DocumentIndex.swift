import Foundation

/// Ask-time passage retrieval over the open document. Implemented by
/// LexicalDocumentIndex; kept as a protocol so view models stay testable.
protocol DocumentIndexProtocol: Sendable {
    /// Top passages relevant to the query, formatted with page attribution
    /// ("[p. 12] …"). `excludingPage` drops chunks from the page the user is
    /// already reading (its text is in the prompt as surrounding context).
    func passages(matching query: String, limit: Int, excludingPage: Int?) -> [String]
}
