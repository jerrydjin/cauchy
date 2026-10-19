import Foundation

/// DocumentFind.sections calls this. The snapshot does not index a table of
/// contents, and the real helper lives in a file that imports FoundationModels.
enum LLMReferenceIndexSupport {
    static func isLikelyTableOfContents(_ pageText: String) -> Bool { false }
}
