import SwiftUI

enum PinCategory: String, Codable, CaseIterable, Identifiable, Sendable {
    case theorem
    case proof
    case exercise
    case solution
    case note

    var id: String { rawValue }

    var displayName: String {
        rawValue.capitalized
    }

    var symbol: String {
        switch self {
        case .theorem: "function"
        case .proof: "checkmark.seal"
        case .exercise: "pencil.and.outline"
        case .solution: "lightbulb"
        case .note: "note.text"
        }
    }

    var tintColor: Color {
        switch self {
        case .theorem: .purple
        case .proof: .blue
        case .exercise: .orange
        case .solution: .green
        case .note: .gray
        }
    }
}
