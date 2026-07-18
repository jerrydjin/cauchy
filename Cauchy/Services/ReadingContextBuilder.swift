import Foundation

enum ReadingContextBuilder {
    static func from(
        anchor: TextAnchor,
        documentTitle: String,
        index: (any DocumentIndexProtocol)? = nil,
        query: String? = nil
    ) -> ReadingContext {
        let retrievedPassages: [String]
        if let index, let query, !query.isEmpty {
            retrievedPassages = index.passages(matching: query, limit: 3, excludingPage: nil)
        } else {
            retrievedPassages = []
        }

        return ReadingContext(
            documentTitle: documentTitle,
            selectedText: anchor.selectedText,
            surroundingText: anchor.surroundingText,
            retrievedPassages: retrievedPassages
        )
    }
}
