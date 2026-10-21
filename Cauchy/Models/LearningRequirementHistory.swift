import Foundation

/// A read-only projection of work already visible to the learner. Question
/// keys, hints and future prompts never enter this presentation model.
enum LearningRequirementHistory {
    struct Entry: Identifiable, Equatable {
        let id: String
        let sessionID: UUID
        let lessonTitle: String
        let requirementObjective: String
        let phase: LearningPhase
        let isDelayed: Bool
        let isDraft: Bool
        let date: Date
        let question: String
        let answer: String
        let assessment: LearningAssessment?
        let rubric: [String]
        let recordedKind: LearningStudyKind?
        let assistanceUsed: Bool
        let incompleteCriteriaAssessment: Bool
        let providerID: String
        let modelID: String?

        var activity: String { "\(isDelayed ? "Delayed check" : "Lesson") · \(phase.label)" }
        var status: String {
            if isDraft { return phase == .lesson ? "Teaching in progress" : "Unsubmitted answer" }
            if incompleteCriteriaAssessment { return recordedKind == .proof ? "Proof assessment incomplete" : "Assessment needs checking" }
            return assessment?.grade.label ?? "No assessment recorded"
        }
    }

    static func sessions(for target: LearningStudyTarget, in sessions: [LearningSession]) -> [LearningSession] {
        sessions.filter {
            $0.chapter == nil && $0.studyTarget?.id == target.id
                && $0.studyTarget?.unitID == target.unitID && $0.studyTarget?.kind == target.kind
        }
    }

    static func entries(for target: LearningStudyTarget, in saved: [LearningSession]) -> [Entry] {
        sessions(for: target, in: saved).flatMap { session -> [Entry] in
            var entries = session.attempts.map { attempt in
                Entry(id: "\(session.id):\(attempt.id)", sessionID: session.id, lessonTitle: session.lesson.title,
                    requirementObjective: session.studyTarget?.objective ?? session.lesson.objective,
                    phase: attempt.phase, isDelayed: session.delayedReview != nil, isDraft: false, date: attempt.createdAt,
                    question: attempt.question.prompt, answer: attempt.answer, assessment: attempt.assessment,
                    rubric: attempt.question.gradingCriteria ?? [], recordedKind: attempt.question.kind,
                    assistanceUsed: attempt.assistanceUsed,
                    incompleteCriteriaAssessment: attempt.assessment.grade == .correct && !attempt.assessmentCriteriaSatisfied,
                    providerID: attempt.providerID, modelID: attempt.modelID)
            }
            if session.feedback == nil && session.phase != .complete {
                entries.append(.init(id: "\(session.id):current", sessionID: session.id, lessonTitle: session.lesson.title,
                    requirementObjective: session.studyTarget?.objective ?? session.lesson.objective,
                    phase: session.phase, isDelayed: session.delayedReview != nil, isDraft: true, date: session.updatedAt,
                    question: session.question?.prompt ?? session.lesson.objective, answer: session.answerDraft,
                    assessment: nil, rubric: [], recordedKind: session.question?.kind, assistanceUsed: session.assistanceUsed,
                    incompleteCriteriaAssessment: false, providerID: session.providerID, modelID: session.modelID))
            }
            return entries
        }.sorted { $0.date == $1.date ? $0.id < $1.id : $0.date > $1.date }
    }
}
