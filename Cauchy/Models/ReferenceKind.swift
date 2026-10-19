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
        let normalized = keyword.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
        if let kind = ReferenceKind(rawValue: normalized) {
            return kind
        }
        switch normalized {
        case "theorems": return .theorem
        case "lemmas": return .lemma
        case "propositions": return .proposition
        case "corollaries": return .corollary
        case "definitions": return .definition
        case "exercises": return .exercise
        case "examples": return .example
        case "remarks": return .remark
        case "proofs": return .proof
        default: return nil
        }
    }
}

struct ReferenceKey: Hashable, Sendable {
    let kind: ReferenceKind
    let number: String
}
