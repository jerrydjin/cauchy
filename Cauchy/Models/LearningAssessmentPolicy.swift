import Foundation

/// Structural consistency shared by new tutor replies and saved evidence.
/// This checks the record, not the mathematical truth of an assessment.
enum LearningAssessmentPolicy {
    static func checked(_ assessment: LearningAssessment, question: LearningQuestion) throws -> LearningAssessment {
        guard valid(assessment.feedback), valid(assessment.nextStep) else { throw LearningError.invalidResponse }
        if question.kind == .proof || question.gradingCriteria != nil {
            let minimum = question.kind == .proof ? 3 : 1
            guard let rubric = question.gradingCriteria, (minimum...8).contains(rubric.count), rubric.allSatisfy(valid),
                  let criteria = assessment.criteria, criteria.count == rubric.count,
                  Set(criteria.map(\.index)) == Set(rubric.indices) else { throw LearningError.invalidResponse }
        }
        if let criteria = assessment.criteria {
            guard criteria.count <= 8, Set(criteria.map(\.index)).count == criteria.count,
                  criteria.allSatisfy({ $0.index >= 0 && valid($0.feedback) }) else { throw LearningError.invalidResponse }
        }
        let grade: LearningGrade
        if assessment.criteria?.contains(where: { $0.outcome == .uncertain }) == true { grade = .uncertain }
        else if assessment.grade == .correct, assessment.criteria?.contains(where: { $0.outcome == .notMet }) == true { grade = .partial }
        else { grade = assessment.grade }
        return .init(grade: grade, feedback: assessment.feedback, nextStep: assessment.nextStep,
                     criteria: assessment.criteria?.sorted { $0.index < $1.index })
    }

    private static func valid(_ text: String) -> Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && text.count <= 6_000
    }
}
