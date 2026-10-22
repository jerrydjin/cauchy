import SwiftUI

/// A reversible learner decision, separate from the tutor's recorded grade.
struct LearningAssessmentReviewControl: View {
    let learning: LearningViewModel
    let sessionID: UUID
    let attempt: LearningAttempt

    var body: some View {
        if let date = attempt.setAsideAt {
            VStack(alignment: .leading, spacing: 8) {
                Text("Set aside by you \(date.formatted(date: .abbreviated, time: .shortened)) · excluded from progress.")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Use recorded result again") {
                    learning.setAssessmentAside(false, sessionID: sessionID, attemptID: attempt.id)
                }
                .buttonStyle(.borderless).disabled(learning.isBusy)
                .help("Use the original recorded assessment again. This does not recheck the tutor’s feedback.")
            }
        } else {
            DisclosureGroup("Review this assessment") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("If you disagree with the tutor or want to check its reasoning, set this assessment aside. Your answer and feedback stay saved; this result will not count toward progress.")
                        .font(.callout).foregroundStyle(.secondary)
                    Button("Set aside assessment") {
                        learning.setAssessmentAside(true, sessionID: sessionID, attemptID: attempt.id)
                    }
                    .buttonStyle(.borderless).disabled(learning.isBusy)
                }.padding(.top, 8)
            }
        }
    }
}
