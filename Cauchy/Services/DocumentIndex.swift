import Foundation

protocol DocumentIndexProtocol: Sendable {
    func passages(matching query: String, limit: Int) -> [String]
}

final class DocumentIndex: DocumentIndexProtocol, @unchecked Sendable {
    func passages(matching query: String, limit: Int) -> [String] {
        _ = query
        _ = limit
        return []
    }
}
