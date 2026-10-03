import Foundation

enum ReferenceKind: String, CaseIterable, Equatable, Sendable, Codable {
    case theorem
    case lemma
    case proposition
    case corollary
    case definition
    case exercise
    case example
    case remark
    case proof
    case equation
    case figure

    var displayName: String {
        switch self {
        case .theorem: "Theorem"
        case .lemma: "Lemma"
        case .proposition: "Proposition"
        case .corollary: "Corollary"
        case .definition: "Definition"
        case .exercise: "Exercise"
        case .example: "Example"
        case .remark: "Remark"
        case .proof: "Proof"
        case .equation: "Equation"
        case .figure: "Figure"
        }
    }

    static func fromKeyword(_ keyword: String) -> ReferenceKind? {
        ReferenceKind(rawValue: keyword.lowercased())
    }
}

struct ReferenceKey: Hashable, Sendable {
    let kind: ReferenceKind
    let number: String
}
