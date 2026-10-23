import CryptoKit
import Foundation

/// A snapshot of visible teaching or a question. Answer keys are deliberately
/// absent: clarification is separate from assessment.
struct LearningClarificationContext: Codable, Equatable, Sendable, Identifiable {
    let phase: LearningPhase
    let partIndex: Int?
    let title: String
    let content: String
    /// Absent for legacy teaching/question contexts. Feedback discussions bind
    /// to a saved attempt without including its private answer key.
    var attemptID: UUID? = nil

    var id: String {
        var fields = [phase.rawValue, partIndex.map(String.init) ?? "", title, content]
        if let attemptID { fields.append(attemptID.uuidString) }
        let text = fields.joined(separator: "\n")
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
    var feedbackClarificationContext: LearningClarificationContext? {
        // A prerequisite refresher owns separate supported feedback. This
        // discussion always refers to the saved main-argument assessment.
        guard chapter?.rescueVisible != true else { return nil }
        let attempt: LearningAttempt?
        if phase == .complete { attempt = latestExitAttempt }
        else if let feedback, let question {
            attempt = attempts.last { $0.phase == phase && $0.question == question && $0.assessment == feedback }
        } else { attempt = nil }
        guard let attempt else { return nil }
        var content = ["Assessed question: \(attempt.question.prompt)", "Learner answer: \(attempt.answer)",
                       "Tutor assessment: \(attempt.assessment.grade.label)", attempt.assessment.feedback,
                       "Suggested next step: \(attempt.assessment.nextStep)"]
        if let rubric = attempt.question.gradingCriteria {
            for (index, criterion) in rubric.enumerated() {
                content.append("Criterion \(index + 1): \(criterion)")
                if let result = attempt.assessment.criteria?.first(where: { $0.index == index }) {
                    content.append("\(result.outcome.rawValue): \(result.feedback)")
                }
            }
        }
        return .init(phase: attempt.phase, partIndex: nil, title: "Tutor feedback",
                     content: content.joined(separator: "\n"), attemptID: attempt.id)
    }

    func canAskClarification(for context: LearningClarificationContext) -> Bool {
        if context.attemptID != nil { return feedbackClarificationContext?.id == context.id }
        return feedback == nil && clarificationContext?.id == context.id
    }

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
