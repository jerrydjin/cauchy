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
    var studyRunItemID: UUID? = nil

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

/// A local read-only projection. Hidden keys, hints and future assessment
/// prompts are deliberately absent from the searchable fields.
enum LearningHistorySearch {
    struct Match: Identifiable {
        let session: LearningSession
        let snippet: String?
        var id: UUID { session.id }
    }

    static func results(in sessions: [LearningSession], query: String) -> [Match] {
        let terms = query.split(whereSeparator: \.isWhitespace).map(String.init)
        return sessions.sorted {
            $0.updatedAt == $1.updatedAt ? $0.id.uuidString < $1.id.uuidString : $0.updatedAt > $1.updatedAt
        }.compactMap { session in
            if terms.isEmpty { return Match(session: session, snippet: nil) }
            let fields = fields(in: session)
            guard terms.allSatisfy({ term in fields.contains { range(of: term, in: $0.text) != nil } }) else { return nil }
            let matching = fields.filter { $0.label != nil }.max { lhs, rhs in
                terms.filter { range(of: $0, in: lhs.text) != nil }.count
                    < terms.filter { range(of: $0, in: rhs.text) != nil }.count
            }
            let snippet = matching.flatMap { field -> String? in
                guard let label = field.label, terms.contains(where: { range(of: $0, in: field.text) != nil }) else { return nil }
                return "\(label): \(excerpt(field.text, terms: terms))"
            }
            return Match(session: session, snippet: snippet)
        }
    }

    private struct Field {
        let label: String?
        let text: String
    }

    private static func fields(in session: LearningSession) -> [Field] {
        var fields: [Field] = [.init(label: nil, text: session.lesson.title),
            .init(label: nil, text: session.delayedReview != nil ? "Delayed check" : session.chapter != nil ? "Chapter challenge" : "Lesson"),
            .init(label: nil, text: session.progressLabel),
            .init(label: nil, text: (session.studyTarget?.kind ?? session.lesson.exitCheck.kind)?.label ?? ""),
            .init(label: "Learning goal", text: session.studyTarget?.objective ?? session.lesson.objective),
            .init(label: "Your draft", text: session.answerDraft)]
        if let question = session.question { fields.append(.init(label: "Question", text: question.prompt)) }
        if let feedback = session.feedback {
            fields += [.init(label: "Feedback", text: feedback.feedback), .init(label: "Next step", text: feedback.nextStep)]
        }
        for attempt in session.attempts + (session.chapter?.rescueAttempts ?? []) {
            fields += [.init(label: "Question", text: attempt.question.prompt), .init(label: "Your answer", text: attempt.answer),
                       .init(label: "Feedback", text: attempt.assessment.feedback), .init(label: "Next step", text: attempt.assessment.nextStep)]
            fields += (attempt.assessment.criteria ?? []).map { .init(label: "Feedback", text: $0.feedback) }
        }
        if let chapter = session.chapter {
            fields.append(.init(label: "Your refresher draft", text: chapter.rescueDraft))
            if chapter.rescueVisible { fields.append(.init(label: "Refresher question", text: chapter.challenge.refresher.check.prompt)) }
        }
        for exchange in session.clarifications ?? [] {
            fields += [.init(label: "Your question", text: exchange.question), .init(label: "Explanation", text: exchange.reply.answer)]
        }
        fields += (session.clarificationDrafts ?? [:]).sorted { $0.key < $1.key }.map { .init(label: "Your question draft", text: $0.value) }
        return fields
    }

    private static func range(of term: String, in text: String) -> Range<String.Index>? {
        text.range(of: term, options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }

    private static func excerpt(_ text: String, terms: [String]) -> String {
        let text = LearningSource.normalized(text)
        let match = terms.compactMap { range(of: $0, in: text) }.min { $0.lowerBound < $1.lowerBound }
        let start = match.flatMap { text.index($0.lowerBound, offsetBy: -60, limitedBy: text.startIndex) } ?? text.startIndex
        let end = text.index(start, offsetBy: 200, limitedBy: text.endIndex) ?? text.endIndex
        return (start > text.startIndex ? "…" : "") + String(text[start..<end]) + (end < text.endIndex ? "…" : "")
    }
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
