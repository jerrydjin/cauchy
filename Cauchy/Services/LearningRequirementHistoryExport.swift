import Foundation

/// A portable record of learner-visible work, never a serialization of a
/// lesson's keys, hidden hints, future questions or complete source passages.
enum LearningRequirementHistoryExport {
    static func markdown(documentTitle: String, target: LearningStudyTarget, sessions: [LearningSession],
                         selectedEntryID: String? = nil, exportedAt: Date = Date(),
                         sourceIsCurrent: (LearningSession) -> Bool) -> String? {
        let entries = LearningRequirementHistory.entries(for: target, in: sessions)
            .filter { selectedEntryID == nil || $0.id == selectedEntryID }
        guard !entries.isEmpty else { return nil }
        let dates = ISO8601DateFormatter()
        dates.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var out = "# Saved learning work\n\n"
        out += "Exported from Cauchy at \(dates.string(from: exportedAt)).\n\n"
        out += "\(selectedEntryID == nil ? "Requirement history" : "Selected record") · \(entries.count) saved \(entries.count == 1 ? "record" : "records"), most recent first.\n\n"
        out += "A record of your work and saved tutor feedback. Source references identify supplied material; they do not verify the tutor’s judgement.\n\n"
        out += "## Notes\n\n\(quote(documentTitle))\n\n"
        out += "## Current requirement · \(target.kind.label)\n\n\(quote(target.objective))\n\n"
        for (index, entry) in entries.enumerated() {
            guard let session = sessions.first(where: { $0.id == entry.sessionID }) else { continue }
            out += "---\n\n## Record \(index + 1) · \(entry.activity)\n\n"
            out += "**Saved status:** \(entry.status)\n\n"
            out += "**Recorded at:** \(dates.string(from: entry.date))\n\n"
            out += "### Saved lesson\n\n\(quote(entry.lessonTitle))\n\n"
            if !target.matchesRequirement(session.studyTarget) {
                let title = entry.requirementObjective != target.objective ? "Earlier requirement wording" : "Earlier requirement version"
                out += "### \(title)\n\n\(quote(entry.requirementObjective))\n\n"
                out += "This record belongs to an earlier requirement and does not establish the current requirement.\n\n"
            }
            if entry.phase != .lesson {
                out += entry.assistanceUsed ? "Help was recorded for this \(entry.isDraft ? "question" : "answer").\n\n"
                    : "No help was recorded for this \(entry.isDraft ? "question" : "answer").\n\n"
            }
            if !entry.isDraft, entry.recordedKind != target.kind {
                out += entry.recordedKind == nil ? "The saved question’s requirement kind was not recorded. This record does not establish the current requirement.\n\n"
                    : "The saved question has a different requirement kind. This record does not establish the current requirement.\n\n"
            }
            out += "### \(entry.phase == .lesson ? "Learning goal" : "Question")\n\n\(quote(entry.question))\n\n"
            if entry.phase != .lesson {
                out += "### \(entry.isDraft ? "Your saved draft" : "Your answer")\n\n"
                out += entry.answer.isEmpty ? "_No answer was saved._\n\n" : "\(quote(entry.answer))\n\n"
            }
            if let assessment = entry.assessment {
                out += "**Recorded tutor grade:** \(assessment.grade.label)\n\n"
                if let setAsideAt = entry.setAsideAt {
                    out += "Set aside by you at \(dates.string(from: setAsideAt)). This assessment does not count toward progress; the original tutor grade is retained.\n\n"
                }
                if entry.incompleteCriteriaAssessment {
                    out += "The saved reasoning checks do not support a complete assessment. The original tutor grade is retained above.\n\n"
                }
                out += "### Tutor feedback\n\n\(quote(assessment.feedback))\n\n"
                out += "### Next step\n\n\(quote(assessment.nextStep))\n\n"
                for criterion in assessment.criteria ?? [] {
                    out += "#### Reasoning check\n\n"
                    if entry.rubric.indices.contains(criterion.index) {
                        out += "\(quote(entry.rubric[criterion.index]))\n\n"
                    } else {
                        out += "Recorded check index: \(criterion.index).\n\n"
                    }
                    let outcome = criterion.outcome == .met ? "Met" : criterion.outcome == .notMet ? "Not met" : "Uncertain"
                    out += "**Outcome:** \(outcome)\n\n\(quote(criterion.feedback))\n\n"
                }
            }
            out += "### Tutor attribution\n\n\(quote(entry.providerID + (entry.modelID.map { " / " + $0 } ?? "")))\n\n"
            out += "### Saved source\n\n"
            if !sourceIsCurrent(session) { out += "This saved source needs review against the current notes.\n\n" }
            let pages = Array(Set(session.source.passages.map(\.pageIndex))).sorted().map(pageLabel)
            out += pages.isEmpty ? "No source pages were saved.\n\n" : "Supplied pages: \(pages.joined(separator: ", ")).\n\n"
            for passage in session.source.passages {
                if let correction = passage.correction {
                    out += "\(pageLabel(passage.pageIndex)): user-verified transcription saved at \(dates.string(from: correction.createdAt)), not original PDF extraction or tutor output.\n\n"
                }
            }
            let sourceQuote = session.lesson.sourceQuote
            if sourceQuote.isEmpty {
                out += "No source quote was saved.\n\n"
            } else {
                out += "**Saved source quote:**\n\n\(quote(sourceQuote))\n\n"
                let normalized = LearningSource.normalized(sourceQuote)
                let located = Array(Set(session.source.passages.filter {
                    LearningSource.normalized($0.text).contains(normalized)
                }.map(\.pageIndex))).sorted().map(pageLabel)
                out += normalized.isEmpty || located.isEmpty ? "The saved quote could not be located in the recorded source.\n\n"
                    : "Quote located in saved material on: \(located.joined(separator: ", ")).\n\n"
            }
        }
        return out
    }

    private static func pageLabel(_ index: Int) -> String {
        index >= 0 && index < Int.max ? "PDF page \(index + 1)" : "Recorded PDF index \(index)"
    }

    /// Keep content inside its own block, including multiline mathematics,
    /// Markdown headings and fenced code, without truncating the saved text.
    private static func quote(_ text: String) -> String {
        text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n").map { "> \($0)" }.joined(separator: "\n")
    }
}
