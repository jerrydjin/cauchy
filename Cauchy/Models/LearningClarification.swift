import CryptoKit
import Foundation

/// A snapshot of visible teaching or a question. Answer keys are deliberately
/// absent: clarification is separate from assessment.
struct LearningClarificationContext: Codable, Equatable, Sendable, Identifiable {
    let phase: LearningPhase
    let partIndex: Int?
    let title: String
    let content: String

    var id: String {
        let text = [phase.rawValue, partIndex.map(String.init) ?? "", title, content].joined(separator: "\n")
        return SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

struct LearningClarificationReply: Codable, Equatable, Sendable {
    enum Basis: String, Codable, Sendable {
        case suppliedNotes, additionalExplanation, insufficientSource

        var label: String {
            switch self {
            case .suppliedNotes: "Supplied notes"
            case .additionalExplanation: "Beyond the supplied notes"
            case .insufficientSource: "Source is insufficient"
            }
        }
    }
    struct Citation: Codable, Equatable, Sendable {
        let pageIndex: Int
        let quote: String
        var correctionID: UUID? = nil
    }
    let answer: String
    let basis: Basis
    var citations: [Citation]
}

struct LearningClarification: Codable, Equatable, Sendable, Identifiable {
    var id = UUID()
    let context: LearningClarificationContext
    let question: String
    let reply: LearningClarificationReply
    let suppliedPageIndices: [Int]
    let previousExchangeIDs: [UUID]
    let providerID: String
    let modelID: String?
    var createdAt = Date()
}

extension LearningSession {
    var clarificationContext: LearningClarificationContext? {
        guard chapter == nil else { return nil }
        if let question {
            return .init(phase: phase, partIndex: nil, title: phase.label, content: question.prompt)
        }
        guard phase == .lesson else { return nil }
        let content: String
        switch currentLessonPart {
        case .idea: content = lesson.explanation
        case .example: content = lesson.workedExample
        case .proofOverview:
            guard let proof = lesson.proof else { return nil }
            content = ([proof.statement] + proof.assumptions + [proof.strategy]).joined(separator: "\n")
        case .proofStep(let index):
            guard let proof = lesson.proof, proof.steps.indices.contains(index) else { return nil }
            let previous = index > 0 ? [proof.steps[index - 1].claim, proof.steps[index - 1].justification] : []
            content = ([proof.statement] + proof.assumptions + previous
                + [proof.steps[index].claim, proof.steps[index].justification]).joined(separator: "\n")
        case .proofConclusion:
            guard let proof = lesson.proof else { return nil }
            content = [proof.statement, proof.conclusion].joined(separator: "\n")
        }
        return .init(phase: phase, partIndex: currentLessonPartIndex, title: currentLessonPart.label,
                     content: "Learning goal: \(lesson.objective)\n\(content)")
    }
}
