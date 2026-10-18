import Foundation
import FoundationModels

struct LearningSourcePassage: Codable, Equatable, Sendable {
    let pageIndex: Int
    let text: String
    var correction: LearningSourceCorrection? = nil
}

/// A deliberate user transcription, never original PDF extraction or model
/// output. Every revision retains the raw page and its predecessor.
struct LearningSourceCorrection: Identifiable, Codable, Equatable, Sendable {
    var id = UUID()
    let pageIndex: Int
    let originalText: String
    let correctedText: String
    let note: String
    let previousID: UUID?
    var createdAt = Date()
}

struct LearningSource: Codable, Equatable, Sendable {
    let passages: [LearningSourcePassage]

    var label: String {
        let pages = Array(Set(passages.map { $0.pageIndex + 1 })).sorted()
        return pages.map { "Page \($0)" }.joined(separator: ", ")
            + (passages.contains { $0.correction != nil } ? " · user-verified transcription" : "")
    }

    var prompt: String {
        passages.map { passage in
            if let correction = passage.correction {
                return "PDF page \(passage.pageIndex + 1) — USER-VERIFIED TRANSCRIPTION (revision \(correction.id); not original PDF text or AI output):\n\(passage.text)"
            }
            return "PDF page \(passage.pageIndex + 1):\n\(passage.text)"
        }.joined(separator: "\n\n")
    }

    static func normalized(_ text: String) -> String {
        text.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }

    func contains(quote: String) -> Bool {
        let normalizedQuote = Self.normalized(quote)
        return normalizedQuote.count >= 24 && passages.contains {
            Self.normalized($0.text).contains(normalizedQuote)
        }
    }
}

struct LearningQuestion: Codable, Equatable, Sendable {
    let prompt: String
    let expectedAnswer: String
    let hints: [String]
    var kind: LearningStudyKind? = nil
    var gradingCriteria: [String]? = nil
}

/// Generated teaching material, not a verified mathematical solution. An exact
/// quote anchors the objective; it does not certify the generated exercises.
struct LearningLesson: Codable, Equatable, Sendable {
    let title: String
    let objective: String
    let sourceQuote: String
    let explanation: String
    let workedExample: String
    var diagnostic: LearningQuestion
    var practice: LearningQuestion
    var exitCheck: LearningQuestion
    var proof: LearningProof? = nil

    /// Presentation only. Every claim and justification remains intact, and
    /// reading these parts never creates assessment evidence.
    var parts: [LearningLessonPart] {
        if let proof {
            return [.proofOverview] + proof.steps.indices.map { .proofStep($0) }
                + [.proofConclusion, .example]
        }
        return [.idea, .example]
    }
}

enum LearningLessonPart: Equatable, Sendable {
    case idea, proofOverview, proofStep(Int), proofConclusion, example

    var label: String {
        switch self {
        case .idea: "The idea"
        case .proofOverview: "Statement and approach"
        case .proofStep(let index): "Argument · step \(index + 1)"
        case .proofConclusion: "Bring the argument together"
        case .example: "Worked example"
        }
    }
}

enum LearningPhase: String, Codable, Sendable {
    case diagnostic, lesson, practice, exitCheck, complete

    var label: String {
        switch self {
        case .diagnostic: "Starting point"
        case .lesson: "Learn"
        case .practice: "Guided practice"
        case .exitCheck: "Exit check"
        case .complete: "Your evidence"
        }
    }
}

enum LearningGrade: String, Codable, Sendable {
    case correct, partial, incorrect, uncertain

    var label: String {
        switch self {
        case .correct: "Correct"
        case .partial: "Partly correct"
        case .incorrect: "Needs another look"
        case .uncertain: "Needs checking"
        }
    }
}

struct LearningAssessment: Codable, Equatable, Sendable {
    let grade: LearningGrade
    let feedback: String
    let nextStep: String
    var criteria: [LearningCriterionAssessment]? = nil
}

struct LearningCriterionAssessment: Codable, Equatable, Sendable {
    @Generable enum Outcome: String, Codable, Sendable { case met, notMet, uncertain }
    let index: Int
    let outcome: Outcome
    let feedback: String
}

struct LearningAttempt: Identifiable, Codable, Equatable, Sendable {
    var id = UUID()
    let phase: LearningPhase
    let question: LearningQuestion
    let answer: String
    let assessment: LearningAssessment
    let assistanceUsed: Bool
    let providerID: String
    let modelID: String?
    var createdAt = Date()

    var proofCriteriaSatisfied: Bool {
        guard question.kind == .proof else { return true }
        guard let rubric = question.gradingCriteria, (3...8).contains(rubric.count),
              let criteria = assessment.criteria, criteria.count == rubric.count,
              Set(criteria.map(\.index)) == Set(rubric.indices) else { return false }
        return criteria.allSatisfy { $0.outcome == .met }
    }

    var hasIndependentCorrectResult: Bool {
        assessment.grade == .correct && !assistanceUsed && proofCriteriaSatisfied
    }
}

struct LearningSession: Identifiable, Codable, Equatable, Sendable {
    var id = UUID()
    let source: LearningSource
    var lesson: LearningLesson
    var phase: LearningPhase = .diagnostic
    var attempts: [LearningAttempt] = []
    var answerDraft = ""
    var feedback: LearningAssessment?
    var hintsRevealed = 0
    var solutionRevealed = false
    var sourceOpened = false
    /// Optional so sessions saved before self-reported help was supported still decode.
    var outsideHelpUsed: Bool?
    let providerID: String
    let modelID: String?
    var createdAt = Date()
    var updatedAt = Date()
    var studyTarget: LearningStudyTarget? = nil
    /// Optional for workspaces saved before paced lessons were introduced.
    var lessonPartIndex: Int? = nil
    var chapter: LearningChapterState? = nil
    var delayedReview: LearningDelayedReview? = nil
    var reviewDueAt: Date? = nil
    /// Optional fields preserve decoding of sessions from before clarification.
    var clarifications: [LearningClarification]? = nil
    var clarificationDrafts: [String: String]? = nil
    var clarificationHelpUsed: Bool? = nil

    var currentLessonPartIndex: Int {
        min(max(lessonPartIndex ?? 0, 0), lesson.parts.count - 1)
    }

    var currentLessonPart: LearningLessonPart { lesson.parts[currentLessonPartIndex] }

    var question: LearningQuestion? {
        switch phase {
        case .diagnostic: lesson.diagnostic
        case .practice: lesson.practice
        case .exitCheck: chapter?.challenge.question ?? lesson.exitCheck
        case .lesson, .complete: nil
        }
    }

    var latestExitAttempt: LearningAttempt? { attempts.last { $0.phase == .exitCheck } }

    var passedExitCheck: Bool {
        guard let attempt = latestExitAttempt else { return false }
        return attempt.hasIndependentCorrectResult
    }

    var assistanceUsed: Bool {
        hintsRevealed > 0 || solutionRevealed || sourceOpened || outsideHelpUsed == true || chapter?.assistanceUsed == true
            || delayedReview?.helpUsed == true
            || clarificationHelpUsed == true
    }

    var progressLabel: String {
        if phase == .complete {
            guard let attempt = latestExitAttempt else { return "No exit result yet" }
            switch attempt.assessment.grade {
            case .correct:
                guard attempt.proofCriteriaSatisfied else { return "Proof assessment incomplete" }
                return attempt.assistanceUsed ? "Correct with help" : "Passed exit check"
            case .uncertain: return "Assessment inconclusive"
            case .partial, .incorrect: return "More practice needed"
            }
        }
        return phase.label
    }

    mutating func move(to phase: LearningPhase) {
        self.phase = phase
        if phase == .lesson { lessonPartIndex = 0 }
        answerDraft = ""
        feedback = nil
        hintsRevealed = 0
        solutionRevealed = false
        sourceOpened = false
        outsideHelpUsed = nil
        clarificationHelpUsed = nil
        updatedAt = Date()
    }
}

/// Scheduling policy, not a model of memory or a retention guarantee. The
/// due date and triggering evidence are saved with each separate review.
struct LearningDelayedReview: Codable, Equatable, Sendable {
    let previousSessionID: UUID
    let scheduledFor: Date
    let startedAt: Date
    let round: Int
    var helpUsed: Bool? = nil
}

/// A cumulative argument owns its evidence. It never inherits a topic target ID.
struct LearningChapterChallenge: Codable, Equatable, Sendable {
    struct Idea: Codable, Equatable, Sendable {
        let unitID: UUID
        let title: String
        let pageIndex: Int
        let sourceQuote: String
    }
    struct Criterion: Codable, Equatable, Sendable {
        let index: Int
        let unitIDs: [UUID]
    }
    struct Refresher: Codable, Equatable, Sendable {
        let unitID: UUID
        let pageIndex: Int
        let sourceQuote: String
        let explanation: String
        let check: LearningQuestion
    }
    let moduleID: UUID
    let title: String
    let connection: String
    let ideas: [Idea]
    let assumptions: [String]
    var question: LearningQuestion
    let criteria: [Criterion]
    let refresher: Refresher

    /// Presentation metadata for the shared session/sidebar, never generated
    /// local teaching or a replacement for this challenge's question.
    var sessionEnvelope: LearningLesson {
        .init(title: title, objective: connection, sourceQuote: ideas.first?.sourceQuote ?? "",
              explanation: "", workedExample: "", diagnostic: question, practice: question, exitCheck: question)
    }
}

struct LearningChapterRequest: Codable, Equatable, Sendable {
    let moduleID: UUID
    let title: String
    let connection: String
    let units: [LearningStudyUnit]
}

struct LearningChapterState: Codable, Equatable, Sendable {
    let request: LearningChapterRequest
    var challenge: LearningChapterChallenge
    var rescueVisible = false
    var rescueDraft = ""
    var rescueFeedback: LearningAssessment?
    var rescueAttempts: [LearningAttempt] = []
    /// Only a genuinely new question resets this flag. Returning or revising does not.
    var assistanceUsed = false
    var position = "argument"
    var scrollOffset: Double? = nil
}
