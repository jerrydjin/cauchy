import Foundation

enum LearningStudyKind: String, Codable, CaseIterable, Sendable {
    case concept, proof, application

    var label: String {
        switch self {
        case .concept: "Concepts and statements"
        case .proof: "Proof and reasoning"
        case .application: "Application"
        }
    }

    var symbol: String {
        switch self {
        case .concept: "text.book.closed"
        case .proof: "list.bullet.rectangle"
        case .application: "pencil.and.outline"
        }
    }
}

struct LearningStudyTarget: Identifiable, Codable, Equatable, Sendable {
    var id = UUID()
    let unitID: UUID
    let kind: LearningStudyKind
    let objective: String
    var courseContext: String? = nil
    var revisionID: UUID? = nil

    /// Credit and lesson reuse belong to this exact requirement. Course
    /// organization can change without changing what the learner must show.
    func matchesRequirement(_ other: LearningStudyTarget?) -> Bool {
        guard let other else { return false }
        return id == other.id && unitID == other.unitID && kind == other.kind
            && objective == other.objective && revisionID == other.revisionID
    }
}

/// A learner's wording decision, separate from the generated source inventory.
/// The full preceding requirement keeps repeated edits and reversals traceable.
struct LearningGoalRevision: Identifiable, Codable, Equatable, Sendable {
    var id = UUID()
    let previous: LearningStudyTarget
    let objective: String
    let note: String
    let unitTitle: String
    let source: LearningSourceEvidence
    let createdAt: Date

    var target: LearningStudyTarget {
        var revised = LearningStudyTarget(id: previous.id, unitID: previous.unitID,
            kind: previous.kind, objective: objective, courseContext: previous.courseContext)
        revised.revisionID = id
        return revised
    }
}

/// Read-only history remains available without a composed course. A retained
/// decision is current only when its exact version is still an effective goal.
enum LearningGoalHistory {
    struct Entry: Identifiable, Equatable {
        enum Status: Equatable {
            case current, earlierGoal, earlierSource

            var label: String {
                switch self {
                case .current: "Current goal"
                case .earlierGoal: "Earlier goal"
                case .earlierSource: "Earlier source"
                }
            }
        }

        var id: UUID { revision.id }
        let revision: LearningGoalRevision
        let status: Status
    }

    static func entries(in map: LearningStudyMap) -> [Entry] {
        let archived = (map.earlierGoalRevisions ?? []).map { Entry(revision: $0, status: .earlierSource) }
        let retained = map.units.flatMap { unit in
            let current = unit.learningTargets
            return (unit.goalRevisions ?? []).map { revision in
                Entry(revision: revision, status: current.contains { $0.matchesRequirement(revision.target) }
                    ? .current : .earlierGoal)
            }
        }
        return (archived + retained).sorted {
            $0.revision.createdAt == $1.revision.createdAt ? $0.id.uuidString < $1.id.uuidString
                : $0.revision.createdAt > $1.revision.createdAt
        }
    }
}

struct LearningStudyUnit: Identifiable, Codable, Equatable, Sendable {
    var id: UUID
    let title: String
    let anchorPage: Int // zero-based, like PDFKit
    let sourceQuote: String
    let pageIndices: [Int]
    let prerequisites: [String]
    let proofRequired: Bool
    let proofQuote: String?
    let gaps: [String]
    let targets: [LearningStudyTarget]
    var reconciliation: LearningUnitReconciliation? = nil
    var pendingSourceCorrection: Bool? = nil
    var sourceCorrectionIDs: [UUID]? = nil
    var goalRevisions: [LearningGoalRevision]? = nil

    var learningTargets: [LearningStudyTarget] {
        (targets + (reconciliation?.proofTarget.map { [$0] } ?? [])).map { original in
            (goalRevisions ?? []).reduce(original) { current, revision in
                current.matchesRequirement(revision.previous) ? revision.target : current
            }
        }
    }

    var teachingAnchor: LearningSourceEvidence {
        reconciliation?.revisedAnchor ?? .init(pageIndex: anchorPage, quote: sourceQuote)
    }

    var openGapCount: Int {
        gaps.indices.filter { index in
            pendingSourceCorrection == true || reconciliation?.issues.first(where: { $0.gapIndex == index })?.disposition != .foundElsewhere
        }.count
    }

    var needsSourceReview: Bool {
        pendingSourceCorrection == true
            || gaps.indices.contains { index in LearningSourceReconciler.extractionConcern(gaps[index])
                && reconciliation?.issues.first(where: { $0.gapIndex == index })?.disposition != .foundElsewhere }
            || reconciliation?.issues.contains { $0.disposition == .extractionProblem } == true
    }

    var hasUnlocatedProof: Bool { proofRequired && !learningTargets.contains { $0.kind == .proof } }

    var learningPageIndices: [Int] {
        Array(Set(pageIndices + [teachingAnchor.pageIndex] + (reconciliation?.issues.filter { $0.disposition == .foundElsewhere }
            .flatMap { $0.evidence.map(\.pageIndex) } ?? [])
            + (reconciliation?.proofEvidence.map(\.pageIndex) ?? []))).sorted()
    }

    func evidence(for target: LearningStudyTarget, sessions: [LearningSession]) -> LearningAttempt? {
        // Only a check explicitly attached to this requirement can count.
        // An unrelated application lesson cannot establish proof comprehension.
        guard target.unitID == id, learningTargets.contains(where: { $0.matchesRequirement(target) }) else { return nil }
        return sessions.filter { session in
            session.chapter == nil && session.delayedReview == nil && target.matchesRequirement(session.studyTarget)
                && Set(sourceCorrectionIDs ?? []).isSubset(of: Set(session.source.passages.compactMap { $0.correction?.id }))
        }
            .compactMap(\.latestExitAttempt).filter { $0.question.kind == target.kind }
            .max { $0.createdAt < $1.createdAt }
    }

    func checkedTargetCount(sessions: [LearningSession]) -> Int {
        learningTargets.filter {
            guard let attempt = evidence(for: $0, sessions: sessions) else { return false }
            return attempt.hasIndependentCorrectResult
        }.count
    }

    func hasEvidenceForEveryTarget(sessions: [LearningSession]) -> Bool {
        !learningTargets.isEmpty && !needsSourceReview && openGapCount == 0 && (!proofRequired || learningTargets.contains { $0.kind == .proof })
            && checkedTargetCount(sessions: sessions) == learningTargets.count
    }
}

enum LearningPageReviewStatus: String, Codable, Sendable {
    case pending, mapped, nonInstructional, needsContext, unreadable, tooLong

    var label: String {
        switch self {
        case .pending: "Not mapped"
        case .mapped: "Mapped"
        case .nonInstructional: "No study material identified"
        case .needsContext: "Needs more context"
        case .unreadable: "No readable text"
        case .tooLong: "Exceeds this model’s capacity"
        }
    }

    var isResolved: Bool { self == .mapped || self == .nonInstructional }
}

struct LearningPageReview: Identifiable, Codable, Equatable, Sendable {
    var id: Int { pageIndex }
    let pageIndex: Int
    var status: LearningPageReviewStatus = .pending
    var reason = ""
    var providerID: String?
    var modelID: String?
}

struct LearningStudyMap: Codable, Equatable, Sendable {
    let pageSignatures: [String]
    var pages: [LearningPageReview]
    var units: [LearningStudyUnit] = []
    var updatedAt = Date()
    var course: LearningCourse? = nil
    var sourceCorrections: [LearningSourceCorrection]? = nil
    var syllabus: LearningSyllabus? = nil
    var studyRuns: [LearningStudyRun]? = nil
    var earlierGoalRevisions: [LearningGoalRevision]? = nil

    func latestCorrection(for pageIndex: Int) -> LearningSourceCorrection? {
        sourceCorrections?.last { $0.pageIndex == pageIndex }
    }

    func passage(pageIndex: Int, originalText: String) throws -> LearningSourcePassage {
        guard pageSignatures.indices.contains(pageIndex),
              LearningStudyInput.signature(originalText) == pageSignatures[pageIndex] else { throw LearningError.sourceChanged }
        guard let correction = latestCorrection(for: pageIndex) else { return .init(pageIndex: pageIndex, text: originalText) }
        guard correction.originalText == originalText else { throw LearningError.sourceChanged }
        return .init(pageIndex: pageIndex, text: correction.correctedText, correction: correction)
    }

    var resolvedPageCount: Int { pages.filter { $0.status.isResolved }.count }
    var unresolvedPages: [LearningPageReview] { pages.filter { !$0.status.isResolved } }

    /// Resume an open requirement first, otherwise follow source order. This
    /// is navigation guidance, not a claim of adaptive prerequisite mastery.
    func nextStudy(sessions: [LearningSession]) -> LearningStudyRecommendation? {
        let requirements = pendingStudies(sessions: sessions)
        // A blocked first requirement stays here. Its next action is source
        // review, not an automatic jump over an unchecked prerequisite.
        return requirements.filter { $0.session != nil }.max {
            ($0.session?.updatedAt ?? .distantPast) < ($1.session?.updatedAt ?? .distantPast)
        } ?? requirements.first
    }

    /// Explicit choices for the learner, not a prerequisite-readiness claim.
    /// Existing saved work remains inspectable even when new teaching would
    /// be blocked by a source fault.
    func availableStudyChoices(sessions: [LearningSession]) -> [LearningStudyRecommendation] {
        pendingStudies(sessions: sessions).filter { !$0.requiresSourceReview }
    }

    func nextDelayedReview(sessions: [LearningSession], now: Date, targetID: UUID? = nil) -> LearningReviewRecommendation? {
        delayedReviews(sessions: sessions, now: now, targetID: targetID).first
    }

    /// Saved checks lead the due queue so an unfinished answer keeps its place.
    func delayedReviews(sessions: [LearningSession], now: Date, targetID: UUID? = nil) -> [LearningReviewRecommendation] {
        reviewCandidates(sessions: sessions, dueBy: now, targetID: targetID)
    }

    /// Retain eligible future dates so the overview can follow its clock without
    /// rescanning saved answers. Evidence and source policy are shared with the queue.
    func delayedReviewSchedule(sessions: [LearningSession]) -> LearningReviewSchedule {
        let candidates = reviewCandidates(sessions: sessions, dueBy: nil, targetID: nil)
        return .init(inProgress: candidates.filter { $0.activeSessionID != nil }.map(\.dueAt),
                     scheduled: candidates.filter { $0.activeSessionID == nil }.map(\.dueAt))
    }

    private func reviewCandidates(sessions: [LearningSession], dueBy: Date?, targetID: UUID?) -> [LearningReviewRecommendation] {
        // Narrow each target's history once. IDs select a bucket only; the
        // complete requirement identity and evidence policy still apply below.
        var histories: [UUID: [LearningSession]] = [:]
        for session in sessions where session.chapter == nil {
            guard let id = session.studyTarget?.id, targetID == nil || id == targetID else { continue }
            histories[id, default: []].append(session)
        }
        var candidates: [LearningReviewRecommendation] = []
        for unit in units {
            for target in unit.learningTargets where targetID == nil || target.id == targetID {
                let related = (histories[target.id] ?? []).filter { target.matchesRequirement($0.studyTarget) }
                if let active = related.filter({ $0.delayedReview != nil && $0.phase != .complete })
                    .max(by: { $0.updatedAt < $1.updatedAt }) {
                    candidates.append(.init(unit: unit, target: target, previous: active,
                        dueAt: active.delayedReview!.scheduledFor, activeSessionID: active.id))
                    continue
                }
                guard !unit.needsSourceReview,
                      unit.evidence(for: target, sessions: related)?.hasIndependentCorrectResult == true else { continue }
                let scheduled = related.filter { session in
                    session.reviewDueAt != nil
                        && session.latestExitAttempt?.setAsideAt == nil
                        && Set(unit.sourceCorrectionIDs ?? []).isSubset(of: Set(session.source.passages.compactMap { $0.correction?.id }))
                }.max { ($0.latestExitAttempt?.createdAt ?? .distantPast) < ($1.latestExitAttempt?.createdAt ?? .distantPast) }
                guard let previous = scheduled, let due = previous.reviewDueAt else { continue }
                if let dueBy, !(due <= dueBy) { continue }
                candidates.append(.init(unit: unit, target: target, previous: previous, dueAt: due, activeSessionID: nil))
            }
        }
        return candidates.sorted {
            if ($0.activeSessionID != nil) != ($1.activeSessionID != nil) { return $0.activeSessionID != nil }
            if $0.dueAt != $1.dueAt { return $0.dueAt < $1.dueAt }
            return $0.target.id.uuidString < $1.target.id.uuidString
        }
    }

    func delayedEvidence(for target: LearningStudyTarget, sessions: [LearningSession]) -> [LearningAttempt] {
        sessions.filter { $0.chapter == nil && $0.delayedReview != nil && target.matchesRequirement($0.studyTarget) }
            .flatMap(\.attempts).filter { $0.phase == .exitCheck && $0.question.kind == target.kind }
            .sorted { $0.createdAt < $1.createdAt }
    }

    private func pendingStudies(sessions: [LearningSession]) -> [LearningStudyRecommendation] {
        let ordered = course.map { outline in
            outline.modules.flatMap(\.unitIDs).compactMap { id in units.first { $0.id == id } }
        } ?? units.sorted { $0.anchorPage < $1.anchorPage }
        return ordered.flatMap { unit in
            unit.learningTargets.map { target in
                LearningStudyRecommendation(unit: unit, target: target,
                    session: sessions.filter { $0.chapter == nil && $0.delayedReview == nil && target.matchesRequirement($0.studyTarget) }.max { $0.updatedAt < $1.updatedAt })
            }
        }.filter { $0.unit.evidence(for: $0.target, sessions: sessions)?.hasIndependentCorrectResult != true }
    }
}

struct LearningReviewRecommendation {
    let unit: LearningStudyUnit
    let target: LearningStudyTarget
    let previous: LearningSession
    let dueAt: Date
    let activeSessionID: UUID?
}

/// Small derived navigation data, never persisted evidence or a memory model.
struct LearningReviewSchedule: Equatable, Sendable {
    struct Status: Equatable, Sendable {
        let dueCount: Int
        let inProgressCount: Int
        let earliestDate: Date
    }

    static let empty = LearningReviewSchedule(inProgress: [], scheduled: [])
    private let inProgress: [Date]
    private let scheduled: [Date]

    fileprivate init(inProgress: [Date], scheduled: [Date]) {
        self.inProgress = inProgress
        self.scheduled = scheduled
    }

    func status(at date: Date) -> Status? {
        // Dates arrive sorted from the shared candidate selector. Find the due
        // prefix without walking every saved requirement on each view update.
        var low = 0, high = scheduled.count
        while low < high {
            let middle = low + (high - low) / 2
            if scheduled[middle] <= date { low = middle + 1 } else { high = middle }
        }
        let earliest: Date
        if let active = inProgress.first { earliest = low > 0 ? min(active, scheduled[0]) : active }
        else if low > 0 { earliest = scheduled[0] }
        else { return nil }
        return .init(dueCount: low, inProgressCount: inProgress.count, earliestDate: earliest)
    }
}

struct LearningSyllabus: Codable, Equatable, Sendable {
    struct Requirement: Identifiable, Codable, Equatable, Sendable {
        var id = UUID()
        let text: String
        let kinds: [LearningStudyKind]
        let provenance: String
        var createdAt = Date()
    }
    enum Status: String, Codable, CaseIterable, Sendable {
        case mapped, absent, unresolved
        var label: String {
            switch self {
            case .mapped: "Mapped to source"
            case .absent: "Absent from these notes (your review)"
            case .unresolved: "Mapping unresolved"
            }
        }
    }
    struct TargetReference: Codable, Equatable, Sendable {
        let unitID: UUID
        let target: LearningStudyTarget
        let sourceQuote: String
        let correctionIDs: [UUID]
    }
    struct Mapping: Identifiable, Codable, Equatable, Sendable {
        var id = UUID()
        let requirementID: UUID
        let kind: LearningStudyKind
        let status: Status
        let references: [TargetReference]
        let note: String
        var createdAt = Date()
    }
    var requirements: [Requirement] = []
    var history: [Mapping] = []

    func latestMapping(for requirement: Requirement, kind: LearningStudyKind) -> Mapping? {
        history.last { $0.requirementID == requirement.id && $0.kind == kind }
    }

    func sourceTargets(for mapping: Mapping, in map: LearningStudyMap) -> [LearningStudyTarget]? {
        guard mapping.status == .mapped, !mapping.references.isEmpty else { return nil }
        var targets: [LearningStudyTarget] = []
        for reference in mapping.references {
            guard let unit = map.units.first(where: { $0.id == reference.unitID }), !unit.needsSourceReview, unit.openGapCount == 0,
                  unit.teachingAnchor.quote == reference.sourceQuote,
                  Set(unit.sourceCorrectionIDs ?? []) == Set(reference.correctionIDs),
                  let target = unit.learningTargets.first(where: { $0.id == reference.target.id }),
                  target.kind == mapping.kind, target.matchesRequirement(reference.target) else { return nil }
            if target.kind == .proof, unit.hasUnlocatedProof { return nil }
            targets.append(target)
        }
        return targets
    }

    func coverage(in map: LearningStudyMap, sessions: [LearningSession]) -> (required: Int, sourceMapped: Int, checked: Int) {
        var required = 0, mapped = 0, checked = 0
        for requirement in requirements {
            for kind in requirement.kinds {
                required += 1
                guard let mapping = latestMapping(for: requirement, kind: kind), let targets = sourceTargets(for: mapping, in: map) else { continue }
                mapped += 1
                if targets.allSatisfy({ target in
                    map.units.first { $0.id == target.unitID }?.evidence(for: target, sessions: sessions)?.hasIndependentCorrectResult == true
                }) { checked += 1 }
            }
        }
        return (required, mapped, checked)
    }
}

/// A whole-document organization of the full inventory. It neither replaces
/// source obligations nor establishes that the learner has mastered them.
struct LearningCourse: Codable, Equatable, Sendable {
    struct Module: Codable, Equatable, Identifiable, Sendable {
        var id = UUID()
        let title: String
        let goal: String
        let unitIDs: [UUID]
    }
    struct Connection: Codable, Equatable, Sendable {
        let fromUnitID: UUID
        let toUnitID: UUID
        let reason: String
    }
    let title: String
    let overview: String
    let modules: [Module]
    let connections: [Connection]
}

struct LearningStudyRecommendation {
    let unit: LearningStudyUnit
    let target: LearningStudyTarget
    let session: LearningSession?

    var requiresRevisedLesson: Bool {
        guard let session else { return false }
        return !Set(unit.sourceCorrectionIDs ?? []).isSubset(of: Set(session.source.passages.compactMap { $0.correction?.id }))
    }
    var requiresSourceReview: Bool { (session == nil || requiresRevisedLesson) && unit.needsSourceReview }
    var label: String { requiresSourceReview ? "Source review before teaching" : requiresRevisedLesson ? "Updated source · new teaching needed" : session == nil ? "Next in your notes" : "Continue where you left off" }
    var actionLabel: String { requiresSourceReview ? "Review source" : requiresRevisedLesson ? "Prepare revised lesson" : session == nil ? "Start next lesson" : "Continue lesson" }
    var actionSymbol: String { requiresSourceReview ? "doc.text.magnifyingglass" : requiresRevisedLesson ? "arrow.clockwise" : session == nil ? "play.fill" : "arrow.right" }

    var sourceReviewPageIndex: Int {
        unit.reconciliation?.issues.first { $0.disposition == .extractionProblem }?.evidence.first?.pageIndex ?? unit.anchorPage
    }

    func canPerformAction(assistantAvailable: Bool, isBusy: Bool) -> Bool {
        !isBusy && (requiresSourceReview || (session != nil && !requiresRevisedLesson) || assistantAvailable)
    }
}

struct LearningProofStep: Codable, Equatable, Sendable {
    let claim: String
    let justification: String
}

struct LearningProof: Codable, Equatable, Sendable {
    let statement: String
    let assumptions: [String]
    let strategy: String
    let steps: [LearningProofStep]
    let conclusion: String
    let sourceQuote: String
}


struct LearningChapterBlocker: Equatable, Identifiable {
    enum Kind: String { case connection, missingTopic, extraction, proof, sourceGap, page }
    var id: String { "\(unitID?.uuidString ?? "chapter"):\(kind.rawValue):\(gapIndex ?? pageIndex ?? -1)" }
    let kind: Kind
    let unitID: UUID?
    let pageIndex: Int?
    var gapIndex: Int? = nil
    let reason: String
}

struct LearningChapterAvailability {
    let request: LearningChapterRequest?
    let blockers: [LearningChapterBlocker]
}

extension LearningStudyMap {
    func isCurrentChapterRequest(_ request: LearningChapterRequest) -> Bool {
        guard let module = course?.modules.first(where: { $0.id == request.moduleID }),
              let current = chapterRequest(for: module) else { return false }
        return current.hasSameRequirements(as: request)
    }

    /// Select a real connection in source order. Unresolved source obligations
    /// are never reclassified as a learner knowledge gap.
    func chapterRequest(for module: LearningCourse.Module) -> LearningChapterRequest? {
        chapterAvailability(for: module).request
    }

    /// Derived from current validated inventory on every read. No persisted
    /// availability bit can go stale or mutate a learner's saved work.
    func chapterAvailability(for module: LearningCourse.Module) -> LearningChapterAvailability {
        guard let course, course.modules.contains(where: { $0.id == module.id }) else {
            return .init(request: nil, blockers: [.init(kind: .connection, unitID: nil, pageIndex: nil,
                reason: "This chapter is no longer in the current learning path. Return to the current chapters.")])
        }
        let connections = course.connections.filter { module.unitIDs.contains($0.fromUnitID)
            && module.unitIDs.contains($0.toUnitID) && $0.fromUnitID != $0.toUnitID }
        guard !connections.isEmpty else {
            return .init(request: nil, blockers: [.init(kind: .connection, unitID: nil,
                pageIndex: units.first { module.unitIDs.contains($0.id) }?.anchorPage,
                reason: "The learning path has no connected pair within this chapter. Review its topics in the notes; individual lessons remain available.")])
        }
        var blockers: [LearningChapterBlocker] = []
        for connection in connections {
            let selected = [connection.fromUnitID, connection.toUnitID].compactMap { id in units.first { $0.id == id } }
            var pairBlockers: [LearningChapterBlocker] = []
            if selected.count != 2 {
                pairBlockers.append(.init(kind: .missingTopic, unitID: nil, pageIndex: selected.first?.anchorPage,
                    reason: "A connected topic is missing from the source inventory. Continue preparing the notes before starting this challenge."))
            }
            for unit in selected {
                if unit.needsSourceReview {
                    let page = unit.reconciliation?.issues.first { $0.disposition == .extractionProblem }?.evidence.first?.pageIndex
                    pairBlockers.append(.init(kind: .extraction, unitID: unit.id, pageIndex: page ?? unit.anchorPage,
                        reason: unit.pendingSourceCorrection == true
                            ? "\(unit.title): a new user-verified transcription needs source revalidation."
                            : "\(unit.title): extracted mathematics needs comparison with the original PDF."))
                }
                if unit.hasUnlocatedProof {
                    pairBlockers.append(.init(kind: .proof, unitID: unit.id, pageIndex: unit.anchorPage,
                        reason: "\(unit.title): the required proof has no complete usable source argument yet."))
                }
                for index in unit.gaps.indices {
                    let review = unit.reconciliation?.issues.first { $0.gapIndex == index }
                    guard review?.disposition != .foundElsewhere else { continue }
                    pairBlockers.append(.init(kind: .sourceGap, unitID: unit.id,
                        pageIndex: review?.evidence.first?.pageIndex ?? unit.anchorPage, gapIndex: index,
                        reason: "\(unit.title): \(review.map { "\($0.disposition.label). \($0.explanation)" } ?? unit.gaps[index])"))
                }
                for index in unit.learningPageIndices {
                    guard let page = pages.first(where: { $0.pageIndex == index }), page.status.isResolved else {
                        pairBlockers.append(.init(kind: .page, unitID: unit.id, pageIndex: index,
                            reason: "\(unit.title): PDF page \(index + 1) still needs source preparation."))
                        continue
                    }
                }
            }
            if pairBlockers.isEmpty {
                return .init(request: .init(moduleID: module.id, title: module.title, connection: connection.reason, units: selected), blockers: [])
            }
            for blocker in pairBlockers where !blockers.contains(where: { $0.id == blocker.id }) { blockers.append(blocker) }
        }
        return .init(request: nil, blockers: blockers)
    }
}
