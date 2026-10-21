import Foundation

@MainActor
extension LearningDocument {
    struct StudyRunRecovery: Equatable {
        let pageIndex: Int
        let savedSessionID: UUID?
        let blocker: LearningStudyRun.Blocker
    }

    /// Recovery is navigation only. Compare the plan with the actual PDF as
    /// well as its map: the inventory may not have been rebuilt yet.
    func studyRunRecovery(for run: LearningStudyRun) -> StudyRunRecovery? {
        guard run.state != .finished, let item = run.currentItem, let map = studyMap.map else { return nil }
        let saved = item.session(in: learning.sessions)
        func recovery(_ page: Int, _ blocker: LearningStudyRun.Blocker) -> StudyRunRecovery {
            .init(pageIndex: min(max(0, page), max(0, pageCount - 1)), savedSessionID: saved?.id, blocker: blocker)
        }
        if let page = (0..<max(run.pageSignatures.count, pageCount)).first(where: { index in
            guard run.pageSignatures.indices.contains(index), let text = pdfDocument.page(at: index)?.string else { return true }
            return run.pageSignatures[index] != LearningStudyInput.signature(text)
        }) {
            return recovery(page, .changedSource)
        }
        if let saved, let page = sourceReviewPage(for: saved) { return recovery(page, .changedSource) }
        guard let blocker = run.blocker(in: map, sessions: learning.sessions) else { return nil }
        switch blocker {
        case .sourceReview(_, _, let page): return recovery(page, blocker)
        case .changedSource:
            let page = (0..<max(run.pageSignatures.count, map.pageSignatures.count)).first {
                !run.pageSignatures.indices.contains($0) || !map.pageSignatures.indices.contains($0)
                    || run.pageSignatures[$0] != map.pageSignatures[$0]
            }
            return recovery(page ?? sourcePageIndex, blocker)
        case .changedRequirement:
            return recovery(saved?.source.passages.first?.pageIndex
                ?? map.units.first(where: { $0.id == item.unitID })?.anchorPage ?? sourcePageIndex, blocker)
        case .earlierRequirement: return nil
        }
    }

    func reviewStudyRunSource() {
        guard !isBusy, let run = studyMap.currentStudyRun, let recovery = studyRunRecovery(for: run) else { return }
        // Do not mark an old or unrelated answer as having used current notes.
        notesPageIndex = recovery.pageIndex
        notesVisible = true
    }

    func inspectStudyRunWork() {
        guard !isBusy, let run = studyMap.currentStudyRun, run.state != .finished,
              let saved = run.currentItem?.session(in: learning.sessions) else { return }
        learning.select(saved.id)
    }

    var selectedStudyRun: LearningStudyRun? {
        guard let run = studyMap.currentStudyRun, run.state == .active,
              run.currentItem?.session(in: learning.sessions)?.id == learning.selectedSessionID,
              learning.selectedSessionID != nil else { return nil }
        return run
    }

    var canAdvanceStudyRun: Bool {
        guard let map = studyMap.map, var run = selectedStudyRun, studyRunRecovery(for: run) == nil else { return false }
        return run.advance(map: map, sessions: learning.sessions, at: Date())
    }

    func beginStudyRun(_ run: LearningStudyRun) {
        guard !isBusy else { return }
        do {
            try studyMap.startStudyRun(run)
            continueStudyRun()
        } catch { learning.errorMessage = error.localizedDescription }
    }

    func continueStudyRun() {
        guard !isBusy, let map = studyMap.map, let run = studyMap.currentStudyRun,
              run.state != .finished, let item = run.currentItem else { return }
        if studyRunRecovery(for: run) != nil {
            reviewStudyRunSource()
            return
        }
        if let blocker = run.blocker(in: map, sessions: learning.sessions) {
            switch blocker {
            case .sourceReview(_, _, let page): showNotes(at: page)
            case .earlierRequirement(let unitID, let target, _):
                if let unit = map.units.first(where: { $0.id == unitID }) { study(target, unit: unit) }
            case .changedSource, .changedRequirement: break
            }
            return
        }
        studyMap.updateStudyRun(run.id) { $0.resume() }
        if let saved = item.session(in: learning.sessions),
           LearningSourceBuilder.matches(saved.source, document: pdfDocument, map: map) {
            learning.select(saved.id)
            if saved.phase == .complete, item.newExitAttempt(in: learning.sessions) == nil {
                learning.practiseAgain()
            }
        } else if item.mode == .delayedReview {
            guard let review = map.nextDelayedReview(sessions: learning.sessions, now: Date(), targetID: item.target.id) else {
                learning.errorMessage = "This delayed check is no longer available. Your work is saved; finish this session and plan again."
                return
            }
            learning.startDelayedReview(review, studyRunItemID: item.id)
        } else if let unit = map.units.first(where: { $0.id == item.unitID }) {
            study(item.target, unit: unit, prepareNew: true, studyRunItemID: item.id)
        }
    }

    @discardableResult
    func advanceStudyRun() -> Bool {
        guard !isBusy, let map = studyMap.map, let run = selectedStudyRun, studyRunRecovery(for: run) == nil else { return false }
        var advanced = false
        studyMap.updateStudyRun(run.id) { advanced = $0.advance(map: map, sessions: learning.sessions, at: Date()) }
        if advanced, studyMap.currentStudyRun?.state == .active { continueStudyRun() }
        return advanced
    }

    func pauseStudyRun() {
        guard !studyMap.isBusy, let run = studyMap.currentStudyRun else { return }
        learning.cancel(); learning.cancelClarification()
        studyMap.updateStudyRun(run.id) { $0.pause(at: Date()) }
    }

    func finishStudyRun() {
        guard !studyMap.isBusy, let run = studyMap.currentStudyRun else { return }
        learning.cancel(); learning.cancelClarification()
        studyMap.updateStudyRun(run.id) { $0.finish(sessions: learning.sessions, at: Date()) }
    }

    func study(_ target: LearningStudyTarget, unit: LearningStudyUnit, prepareNew: Bool = false, studyRunItemID: UUID? = nil) {
        // Existing lessons and drafts remain available for inspection, but
        // damaged source text cannot silently generate another lesson.
        if !prepareNew, let session = learning.sessions.first(where: { $0.delayedReview == nil && $0.studyTarget?.id == target.id }) {
            learning.select(session.id)
            return
        }
        guard !unit.needsSourceReview else { return }
        guard let map = studyMap.map, unit.learningPageIndices.allSatisfy({ index in
            guard map.pageSignatures.indices.contains(index), let text = pdfDocument.page(at: index)?.string else { return false }
            return LearningStudyInput.signature(text) == map.pageSignatures[index]
        }) else {
            learning.errorMessage = LearningError.sourceChanged.localizedDescription
            return
        }
        let source = LearningSource(passages: unit.learningPageIndices.compactMap { index in
            guard let text = pdfDocument.page(at: index)?.string else { return nil }
            return try? map.passage(pageIndex: index, originalText: text)
        })
        guard source.passages.count == unit.learningPageIndices.count,
              LearningSource(passages: source.passages.filter { $0.pageIndex == unit.teachingAnchor.pageIndex }).contains(quote: unit.teachingAnchor.quote) else {
            learning.errorMessage = LearningError.sourceChanged.localizedDescription
            return
        }
        var contextualTarget = target
        if let course = map.course, let module = course.modules.first(where: { $0.unitIDs.contains(unit.id) }) {
            let connections = course.connections.filter { $0.toUnitID == unit.id || $0.fromUnitID == unit.id }.map(\.reason)
            contextualTarget.courseContext = ([course.title, course.overview, module.title, module.goal] + connections).joined(separator: "\n")
        }
        let openIssues = unit.gaps.enumerated().compactMap { index, gap -> String? in
            let review = unit.reconciliation?.issues.first { $0.gapIndex == index }
            guard review?.disposition != .foundElsewhere else { return nil }
            return review.map { "\($0.disposition.label): \($0.explanation) Original warning: \(gap)" } ?? gap
        }
        if !openIssues.isEmpty {
            contextualTarget.courseContext = (contextualTarget.courseContext ?? "")
                + "\nOpen source obligations (retain explicitly; do not invent missing arguments or hypotheses):\n"
                + openIssues.joined(separator: "\n")
        }
        learning.start(source: source, target: contextualTarget, studyRunItemID: studyRunItemID)
    }

}
