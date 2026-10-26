import Foundation
import Observation
import PDFKit

@MainActor
@Observable
final class LearningStudyMapViewModel {
    private(set) var map: LearningStudyMap? {
        didSet { mapRevision &+= 1 }
    }
    private(set) var mapRevision: UInt64 = 0
    private(set) var isBusy = false
    private(set) var currentPage: Int?
    private(set) var isConnectingTopics = false
    private(set) var recentTopicTitle: String?
    private(set) var isReconciling = false
    private(set) var reconciliationCompleted = 0
    var errorMessage: String?
    @ObservationIgnored var onChange: ((LearningStudyMap) -> Void)?
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var requestID: UUID?
    @ObservationIgnored private let makePlanner: () -> any LearningStudyPlannerProtocol
    @ObservationIgnored private let makeReconciler: () -> any LearningSourceReconcilerProtocol

    init(map: LearningStudyMap? = nil,
         reconciler: (any LearningSourceReconcilerProtocol)? = nil,
         makePlanner: @escaping () -> any LearningStudyPlannerProtocol = { LearningStudyPlannerService() }) {
        self.map = map
        self.makePlanner = makePlanner
        self.makeReconciler = { reconciler ?? LearningSourceReconciler() }
    }

    var currentStudyRun: LearningStudyRun? { map?.studyRuns?.last }

    func addGoal(in unit: LearningStudyUnit, kind: LearningStudyKind, objective: String, note: String,
                 document: PDFDocument, at date: Date = Date()) throws {
        guard !isBusy, var updated = map,
              let index = updated.units.firstIndex(where: { $0.id == unit.id }), updated.units[index] == unit,
              !unit.needsSourceReview,
              (0..<document.pageCount).map({ LearningStudyInput.signature(document.page(at: $0)?.string ?? "") }) == updated.pageSignatures else {
            throw LearningStudyValidationError(reason: "This topic or its source needs review. Close the editor and reopen the current topic before adding a goal.")
        }
        let wording = objective.trimmingCharacters(in: .whitespacesAndNewlines)
        let reason = note.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !wording.isEmpty, wording.count <= 2_000, !reason.isEmpty, reason.count <= 2_000,
              !unit.learningTargets.contains(where: { $0.kind == kind && LearningSource.normalized($0.objective).lowercased() == LearningSource.normalized(wording).lowercased() }) else {
            throw LearningStudyValidationError(reason: "Enter a distinct study goal and a brief reason, each within 2,000 characters.")
        }
        let passages = try unit.learningPageIndices.map { page -> LearningSourcePassage in
            guard let text = document.page(at: page)?.string else { throw LearningError.sourceChanged }
            return try updated.passage(pageIndex: page, originalText: text)
        }
        let source = LearningSource(passages: passages)
        guard let anchor = source.passages.first(where: { $0.pageIndex == unit.teachingAnchor.pageIndex
            && LearningSource(passages: [$0]).contains(quote: unit.teachingAnchor.quote) }) else { throw LearningError.sourceChanged }
        if kind == .proof {
            let evidence = unit.reconciliation?.proofEvidence ?? []
            let supported = evidence.isEmpty ? unit.proofQuote.map { source.contains(quote: $0) } == true
                : evidence.allSatisfy { reference in source.passages.contains { passage in
                    passage.pageIndex == reference.pageIndex && passage.correction?.id == reference.correctionID
                        && LearningSource(passages: [passage]).contains(quote: reference.quote)
                } }
            guard unit.canAddProofGoal, supported else {
                throw LearningStudyValidationError(reason: "Review this topic’s source proof before adding another proof goal. An added goal cannot replace a missing argument.")
            }
        }
        let addition = LearningGoalAddition(target: .init(unitID: unit.id, kind: kind, objective: wording), note: reason,
            unitTitle: unit.title, source: .init(pageIndex: anchor.pageIndex, quote: unit.teachingAnchor.quote,
                correctionID: anchor.correction?.id), createdAt: date)
        updated.units[index].addedGoals = (unit.addedGoals ?? []) + [addition]
        map = updated
        save()
    }

    func reviseGoal(_ target: LearningStudyTarget, in unit: LearningStudyUnit, objective: String, note: String,
                    document: PDFDocument, at date: Date = Date()) throws {
        guard !isBusy, var updated = map,
              let index = updated.units.firstIndex(where: { $0.id == unit.id }), updated.units[index] == unit,
              target.unitID == unit.id, unit.learningTargets.contains(where: { $0.matchesRequirement(target) }),
              (0..<document.pageCount).map({ LearningStudyInput.signature(document.page(at: $0)?.string ?? "") }) == updated.pageSignatures else {
            throw LearningStudyValidationError(reason: "This goal or its source has changed. Close the editor and reopen the current goal before saving.")
        }
        let wording = objective.trimmingCharacters(in: .whitespacesAndNewlines)
        let reason = note.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !wording.isEmpty, wording.count <= 2_000, !reason.isEmpty, reason.count <= 2_000,
              LearningSource.normalized(wording) != LearningSource.normalized(target.objective) else {
            throw LearningStudyValidationError(reason: "Enter a changed study goal and a brief reason, each within 2,000 characters.")
        }
        let revision = LearningGoalRevision(previous: target, objective: wording, note: reason,
            unitTitle: unit.title, source: unit.teachingAnchor, createdAt: date)
        updated.units[index].goalRevisions = (unit.goalRevisions ?? []) + [revision]
        map = updated
        save()
    }

    func startStudyRun(_ run: LearningStudyRun) throws {
        guard !isBusy, var updated = map, updated.pageSignatures == run.pageSignatures,
              !run.items.isEmpty, run.items.count <= 3,
              run.state == .active, run.items.allSatisfy({ $0.outcome == nil }),
              Set(run.items.map(\.id)).count == run.items.count,
              Set(run.items.map { $0.target.id }).count == run.items.count,
              run.items.allSatisfy({ item in
                  updated.units.contains { unit in
                      unit.id == item.unitID && item.unitID == item.target.unitID && unit.learningTargets.contains {
                          $0.matchesRequirement(item.target)
                      }
                  }
              }),
              currentStudyRun == nil || currentStudyRun?.state == .finished else {
            throw LearningStudyValidationError(reason: "Resume or finish the current study session before starting another.")
        }
        updated.studyRuns = (updated.studyRuns ?? []) + [run]
        map = updated
        save()
    }

    func updateStudyRun(_ id: UUID, _ change: (inout LearningStudyRun) -> Void) {
        guard !isBusy, var updated = map, var runs = updated.studyRuns,
              runs.last?.id == id, let index = runs.indices.last else { return }
        change(&runs[index])
        updated.studyRuns = runs
        map = updated
        save()
    }

    /// Append a user-verified full-page transcription. Existing lessons and
    /// review findings stay intact; affected topics require a fresh review.
    func saveCorrection(pageIndex: Int, originalText: String, correctedText: String, note: String,
                        confirmed: Bool, at date: Date = Date()) throws {
        guard !isBusy, var updated = map, confirmed,
              updated.pageSignatures.indices.contains(pageIndex),
              LearningStudyInput.signature(originalText) == updated.pageSignatures[pageIndex] else { throw LearningError.sourceChanged }
        guard LearningSource.normalized(originalText).count >= 24,
              LearningSource.normalized(correctedText).count >= 24, correctedText.count <= 60_000,
              !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, note.count <= 2_000,
              correctedText != (updated.latestCorrection(for: pageIndex)?.correctedText ?? originalText) else {
            throw LearningStudyValidationError(reason: "Provide a changed transcription of the complete readable page and a brief correction note. Compare it with the PDF and confirm the transcription yourself.")
        }
        let correction = LearningSourceCorrection(pageIndex: pageIndex, originalText: originalText,
            correctedText: correctedText, note: note, previousID: updated.latestCorrection(for: pageIndex)?.id, createdAt: date)
        updated.sourceCorrections = (updated.sourceCorrections ?? []) + [correction]
        for index in updated.units.indices where updated.units[index].learningPageIndices.contains(pageIndex)
            || updated.units[index].reconciliation?.inspectedPageIndices.contains(pageIndex) == true {
            updated.units[index].pendingSourceCorrection = true
            updated.units[index].sourceCorrectionIDs = updated.units[index].learningPageIndices.compactMap {
                updated.latestCorrection(for: $0)?.id
            }
        }
        map = updated
        save()
    }

    func addSyllabusRequirements(_ text: String, kinds: [LearningStudyKind], provenance: String) throws {
        guard !isBusy, var updated = map else { return }
        let lines = text.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        guard !lines.isEmpty, lines.count <= 100, lines.allSatisfy({ $0.count <= 2_000 }),
              !kinds.isEmpty, Set(kinds).count == kinds.count, !provenance.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              provenance.count <= 2_000 else {
            throw LearningStudyValidationError(reason: "Enter one syllabus requirement per line, its required kinds of work, and where it came from.")
        }
        var syllabus = updated.syllabus ?? .init()
        let existing = Set(syllabus.requirements.map { LearningSource.normalized($0.text) })
        guard Set(lines.map(LearningSource.normalized)).count == lines.count,
              lines.allSatisfy({ !existing.contains(LearningSource.normalized($0)) }) else {
            throw LearningStudyValidationError(reason: "These requirements already contain a repeated item. Existing required items are retained.")
        }
        syllabus.requirements += lines.map { .init(text: $0, kinds: kinds, provenance: provenance) }
        updated.syllabus = syllabus
        map = updated
        save()
    }

    func mapSyllabusRequirement(_ id: UUID, kind: LearningStudyKind, targetIDs: [UUID],
                                status: LearningSyllabus.Status, note: String) throws {
        guard !isBusy, var updated = map, var syllabus = updated.syllabus,
              let requirement = syllabus.requirements.first(where: { $0.id == id }), requirement.kinds.contains(kind),
              !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, note.count <= 2_000 else {
            throw LearningStudyValidationError(reason: "Choose an existing syllabus requirement and record why you changed its mapping.")
        }
        var references: [LearningSyllabus.TargetReference] = []
        guard Set(targetIDs).count == targetIDs.count,
              (status == .mapped ? !targetIDs.isEmpty : targetIDs.isEmpty) else { throw LearningError.invalidStudyMap }
        for targetID in targetIDs {
            guard let unit = updated.units.first(where: { $0.learningTargets.contains { $0.id == targetID && $0.kind == kind } }),
                  !unit.needsSourceReview, let target = unit.learningTargets.first(where: { $0.id == targetID }) else {
                throw LearningStudyValidationError(reason: "Map this obligation to a source-supported requirement of the same kind. Missing proofs and damaged source stay unresolved.")
            }
            references.append(.init(unitID: unit.id, target: target, sourceQuote: unit.teachingAnchor.quote,
                                    correctionIDs: unit.sourceCorrectionIDs ?? []))
        }
        syllabus.history.append(.init(requirementID: id, kind: kind, status: status, references: references, note: note))
        updated.syllabus = syllabus
        map = updated
        save()
    }

    /// Each validated topic is persisted independently through the existing
    /// learning save flow. No sessions, answers or original target IDs change.
    func reconcile(document: PDFDocument, unitID: UUID? = nil) {
        guard !isBusy, let map else { return }
        errorMessage = nil
        isBusy = true
        isReconciling = true
        reconciliationCompleted = map.units.filter { $0.reconciliation != nil }.count
        let request = UUID()
        requestID = request
        task = Task { [weak self] in
            guard let self else { return }
            do {
                var pages: [String] = []
                for index in 0..<document.pageCount {
                    try Task.checkCancellation()
                    guard requestID == request else { return }
                    pages.append(document.page(at: index)?.string ?? "")
                    await Task.yield()
                }
                guard pages.map(LearningStudyInput.signature) == map.pageSignatures else { throw LearningError.sourceChanged }
                let search = LearningDocumentSearch(pages: pages, corrections: map.sourceCorrections ?? [])
                let reviewer = makeReconciler()
                for unit in map.units where (unit.pendingSourceCorrection == true || !unit.gaps.isEmpty && unit.reconciliation == nil)
                    && (unitID == nil || unit.id == unitID) {
                    try Task.checkCancellation()
                    guard requestID == request else { return }
                    currentPage = unit.anchorPage + 1
                    recentTopicTitle = unit.title
                    guard var source = search.initialSource(unit: unit, limit: reviewer.sourceLimit) else {
                        throw LearningStudyValidationError(reason: "The full source pages for \(unit.title) exceed this assistant’s review capacity. Choose an assistant with more capacity; earlier reviews are saved.")
                    }
                    var result: LearningUnitReconciliation?
                    var validatedResponse = false
                    var repairNote: String?
                    for round in 0..<4 {
                        let response = try await reviewer.review(unit: unit, source: source, pageCount: pages.count, repairNote: repairNote)
                        try Task.checkCancellation()
                        guard requestID == request else { return }
                        if response.requestedPages.isEmpty {
                            do {
                                result = try LearningSourceReconciler.validate(response, unit: unit, source: source,
                                    pageCount: pages.count, providerID: reviewer.providerID, modelID: reviewer.modelID)
                                validatedResponse = true
                                break
                            } catch {
                                guard round < 3 else { throw error }
                                repairNote = error.localizedDescription
                                continue
                            }
                        }
                        let requested = response.requestedPages.map { $0 - 1 }
                        guard requested.allSatisfy({ pages.indices.contains($0) }) else {
                            throw LearningStudyValidationError(reason: "The source reviewer requested a page outside this PDF.")
                        }
                        let current = source.passages.map(\.pageIndex)
                        if round < 3, !Set(requested).isSubset(of: Set(current)),
                           let expanded = search.source(indices: current + requested, limit: reviewer.sourceLimit) {
                            source = expanded
                        } else {
                            // A bounded lookup is never evidence of omission.
                            result = .init(issues: unit.gaps.indices.map { .init(gapIndex: $0, disposition: .notLocated,
                                explanation: "More source context is needed. Inspect PDF pages \(response.requestedPages.map(String.init).joined(separator: ", ")); this assistant could not finish the reference chain within its review capacity.", evidence: []) },
                                inspectedPageIndices: current, searchedPageCount: pages.count, proofEvidence: [], proofTarget: nil,
                                providerID: reviewer.providerID, modelID: reviewer.modelID)
                            break
                        }
                    }
                    guard var result, let index = self.map?.units.firstIndex(where: { $0.id == unit.id }) else { continue }
                    if let target = result.proofTarget, let previous = unit.reconciliation?.proofTarget,
                       previous.objective == target.objective {
                        result = .init(issues: result.issues, inspectedPageIndices: result.inspectedPageIndices,
                            searchedPageCount: result.searchedPageCount, proofEvidence: result.proofEvidence,
                            proofTarget: previous, providerID: result.providerID, modelID: result.modelID,
                            reviewedAt: result.reviewedAt, revisedAnchor: result.revisedAnchor)
                    }
                    self.map?.units[index].reconciliation = result
                    if let current = self.map?.units[index] {
                        let correctionIDs = current.learningPageIndices.compactMap {
                            self.map?.latestCorrection(for: $0)?.id
                        }
                        self.map?.units[index].sourceCorrectionIDs = correctionIDs.isEmpty ? nil : correctionIDs
                    }
                    // Only a completed validator-approved response may clear
                    // this marker. A capacity-bounded search miss cannot.
                    self.map?.units[index].pendingSourceCorrection = unit.pendingSourceCorrection == true
                        && (!validatedResponse || result.issues.contains { $0.disposition == .extractionProblem })
                    if unit.reconciliation == nil { reconciliationCompleted += 1 }
                    save()
                }
            } catch {
                if requestID == request, !(error is CancellationError) { errorMessage = error.localizedDescription }
            }
            if requestID == request {
                isBusy = false
                isReconciling = false
                currentPage = nil
                requestID = nil
                task = nil
            }
        }
    }

    func build(document: PDFDocument) {
        guard !isBusy else { return }
        errorMessage = nil
        recentTopicTitle = nil
        isBusy = true
        let request = UUID()
        requestID = request
        task = Task { [weak self] in
            guard let self else { return }
            let planner = makePlanner()
            // Yield during extraction so large PDFs don't freeze the window.
            var texts: [String] = []
            var blankPages = Set<Int>()
            for index in 0..<document.pageCount {
                guard self.requestID == request, !Task.isCancelled else { return }
                let page = document.page(at: index)
                let text = page?.string ?? ""
                texts.append(text)
                if LearningSource.normalized(text).count < 24, let page, LearningStudyInput.isBlank(page) {
                    blankPages.insert(index)
                }
                await Task.yield()
            }
            do { try await scan(pages: texts, blankPages: blankPages, planner: planner, request: request) }
            catch {
                if requestID == request, !(error is CancellationError) { errorMessage = error.localizedDescription }
            }
            if requestID == request {
                isBusy = false
                currentPage = nil
                isConnectingTopics = false
                requestID = nil
                task = nil
            }
        }
    }

    private func scan(pages: [String], blankPages: Set<Int>, planner: any LearningStudyPlannerProtocol, request: UUID) async throws {
        let signatures = pages.map(LearningStudyInput.signature)
        if map?.pageSignatures != signatures {
            let syllabus = map?.syllabus
            let runs = map?.studyRuns
            let revisions = (map?.earlierGoalRevisions ?? []) + (map?.units.flatMap { $0.goalRevisions ?? [] } ?? [])
            let additions = (map?.earlierGoalAdditions ?? []) + (map?.units.flatMap { $0.addedGoals ?? [] } ?? [])
            map = LearningStudyMap(pageSignatures: signatures, pages: pages.indices.map { .init(pageIndex: $0) },
                syllabus: syllabus, studyRuns: runs, earlierGoalRevisions: revisions.isEmpty ? nil : revisions,
                earlierGoalAdditions: additions.isEmpty ? nil : additions)
            save()
        }
        let pending = map?.unresolvedPages.map(\.pageIndex) ?? []
        var batches: [[Int]] = []
        var offset = 0
        while offset < pending.count {
            try Task.checkCancellation()
            guard requestID == request else { return }
            let index = pending[offset]
            currentPage = index + 1
            if blankPages.contains(index) {
                setPage(index, status: .nonInstructional, reason: "Blank page with no visible content or annotations.", planner: planner)
                offset += 1
                continue
            }
            if LearningSource.normalized(pages[index]).count < 24 {
                let reason = LearningSource.normalized(pages[index]).isEmpty
                    ? "No readable text was extracted. Review this page for a scan or visual material."
                    : "Too little text was extracted to classify this page reliably. Check whether it is a cover or whether content is missing."
                setPage(index, status: .unreadable, reason: reason, planner: planner)
                offset += 1
                continue
            }
            var core = [index]
            // Core pages must be consecutive; completed pages are context only.
            while offset + core.count < pending.count, core.count < 3 {
                let next = pending[offset + core.count]
                guard next == core.last! + 1, LearningSource.normalized(pages[next]).count >= 24,
                      LearningStudyInput.source(pages: pages, core: core + [next], limit: planner.sourceLimit) != nil else { break }
                core.append(next)
            }
            guard LearningStudyInput.source(pages: pages, core: core, limit: planner.sourceLimit) != nil else {
                setPage(index, status: .tooLong, reason: "The full page does not fit this model. Choose a model with greater capacity; no text was omitted.", planner: planner)
                offset += 1
                continue
            }
            batches.append(core)
            offset += core.count
        }
        // Keep a small bounded number of independent requests in flight. All
        // validation, commits and cancellation checks remain on the main actor.
        let work = batches
        try await withThrowingTaskGroup(of: Void.self) { group in
            var next = 0
            let width = min(max(1, planner.parallelism), 3, work.count)
            for _ in 0..<width {
                let core = work[next]
                next += 1
                group.addTask { @Sendable [self, core, pages, planner, request] in
                    try await self.mapBatch(core: core, pages: pages, planner: planner, request: request)
                }
            }
            while try await group.next() != nil {
                if next < work.count {
                    let core = work[next]
                    next += 1
                    group.addTask { @Sendable [self, core, pages, planner, request] in
                        try await self.mapBatch(core: core, pages: pages, planner: planner, request: request)
                    }
                }
            }
        }
        if let units = map?.units, !units.isEmpty, map?.course == nil {
            currentPage = nil
            isConnectingTopics = true
            recentTopicTitle = nil
            let course = try await planner.course(units: units)
            try Task.checkCancellation()
            guard requestID == request else { return }
            // Do not accept an outline that loses a topic, even from an
            // injected planner. Previously saved coverage survives failure.
            let ids = course.modules.flatMap(\.unitIDs)
            guard ids.count == units.count, Set(ids) == Set(units.map(\.id)) else { throw LearningError.invalidCourse }
            map?.course = course
            save()
        }
    }

    /// A malformed batch cannot stop review of the rest of a document.
    /// Tighten the scope, retry once, then keep a failed page explicitly open.
    private func mapBatch(
        core: [Int], pages: [String], planner: any LearningStudyPlannerProtocol,
        request: UUID, retries: Int = 1, repairNote: String? = nil
    ) async throws {
        try Task.checkCancellation()
        guard requestID == request else { return }
        currentPage = core.first.map { $0 + 1 }
        guard let source = LearningStudyInput.source(pages: pages, core: core, limit: planner.sourceLimit) else {
            throw LearningError.sourceTooLong
        }
        do {
            let response = try await planner.plan(source: source, corePages: core, repairNote: repairNote)
            let units = try LearningStudyPlannerService.validate(response, source: source, corePages: core)
            try Task.checkCancellation()
            guard requestID == request else { return }
            // Commit a validated batch atomically; cancellation or failure leaves
            // earlier batches and their target IDs available for resumption.
            var merged = map?.units ?? []
            for candidate in units {
                if let index = merged.firstIndex(where: { $0.anchorPage == candidate.anchorPage && $0.sourceQuote == candidate.sourceQuote }) {
                    let previous = merged[index]
                    merged[index] = LearningStudyUnit(id: previous.id, title: candidate.title, anchorPage: candidate.anchorPage,
                        sourceQuote: candidate.sourceQuote, pageIndices: candidate.pageIndices, prerequisites: candidate.prerequisites,
                        proofRequired: candidate.proofRequired, proofQuote: candidate.proofQuote, gaps: candidate.gaps,
                        targets: candidate.targets.map { target in
                            let id = previous.targets.first { $0.kind == target.kind && $0.objective == target.objective }?.id ?? target.id
                            return LearningStudyTarget(id: id, unitID: previous.id, kind: target.kind, objective: target.objective)
                        }, reconciliation: previous.gaps == candidate.gaps
                            && previous.pageIndices == candidate.pageIndices
                            && previous.proofRequired == candidate.proofRequired
                            && previous.proofQuote == candidate.proofQuote
                            && previous.prerequisites == candidate.prerequisites
                            && previous.targets.map(\.kind) == candidate.targets.map(\.kind)
                            && previous.targets.map(\.objective) == candidate.targets.map(\.objective)
                            ? previous.reconciliation : nil,
                        pendingSourceCorrection: previous.pendingSourceCorrection,
                        sourceCorrectionIDs: previous.sourceCorrectionIDs,
                        goalRevisions: previous.goalRevisions, addedGoals: previous.addedGoals)
                } else { merged.append(candidate) }
            }
            map?.units = merged.sorted { $0.anchorPage < $1.anchorPage }
            recentTopicTitle = units.last?.title
            map?.course = nil
            for page in response.pages {
                setPage(page.pageNumber - 1, status: page.status, reason: page.reason, planner: planner, persist: false)
            }
            save()
        } catch {
            try Task.checkCancellation()
            guard requestID == request else { return }
            let deadline: Bool
            switch error {
            case CLIAgentError.timedOut, AssistantFailure.timedOut: deadline = true
            default: deadline = false
            }
            guard Self.canRetryPage(error) || (deadline && core.count > 1) else { throw error }
            if core.count > 1 {
                for page in core {
                    try await mapBatch(core: [page], pages: pages, planner: planner, request: request, repairNote: error.localizedDescription)
                }
            } else if retries > 0 {
                try await mapBatch(core: core, pages: pages, planner: planner, request: request, retries: retries - 1, repairNote: error.localizedDescription)
            } else if let page = core.first {
                setPage(page, status: .needsContext,
                    reason: "This page remains open: \(error.localizedDescription)",
                    planner: planner)
            }
        }
    }

    private static func canRetryPage(_ error: Error) -> Bool {
        if error is DecodingError { return true }
        if error is LearningStudyValidationError { return true }
        if let error = error as? LearningError {
            switch error {
            case .invalidStudyMap, .invalidResponse, .sourceTooLong: return true
            default: return false
            }
        }
        return false
    }

    var processedPageCount: Int {
        map?.pages.filter { $0.status != .pending }.count ?? 0
    }

    private func setPage(_ index: Int, status: LearningPageReviewStatus, reason: String, planner: any LearningStudyPlannerProtocol, persist: Bool = true) {
        guard map?.pages.indices.contains(index) == true else { return }
        map?.pages[index] = .init(pageIndex: index, status: status, reason: reason,
                                 providerID: planner.providerID, modelID: planner.modelID)
        if persist { save() }
    }

    private func save() {
        map?.updatedAt = Date()
        if let map { onChange?(map) }
    }

    func cancel() {
        requestID = nil
        task?.cancel()
        task = nil
        isBusy = false
        currentPage = nil
        isConnectingTopics = false
        isReconciling = false
    }

    func waitForOperation() async { await task?.value }
}
