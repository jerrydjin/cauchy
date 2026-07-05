import Foundation

struct ReadingContext: Sendable, Equatable {
    let documentTitle: String
    let selectedText: String
    let surroundingText: String
    let retrievedPassages: [String]
}
