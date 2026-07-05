import Foundation

enum DocumentBlockExtractor {
    static func block(from indexed: IndexedReference) -> DocumentBlock {
        DocumentBlock(from: indexed)
    }
}
