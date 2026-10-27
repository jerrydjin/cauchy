import Foundation

/// `AssistantResponseNormalizer.swift` also defines the answer-audit types,
/// which mention these models. The real ones live next to highlights. The
/// reference snapshot never calls the audit; it only needs the normalizer
/// that prepares text for `MessageContentView`.
enum AnswerBasis: String, Equatable, Sendable {
    case pdf
    case mixed
    case insufficient
    case unverified
}

enum AnswerCitationStatus: String, Equatable, Sendable {
    case idsResolve
    case noResolvableCitation
    case invalidID
    case uncitedPassage
}

struct AnswerSourceAnchor: Equatable, Sendable {
    var sourceID: String?
}
