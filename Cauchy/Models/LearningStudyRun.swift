import Foundation

/// A bounded navigation plan. Outcomes reference real lesson attempts; this
/// record never grants learning credit or changes an assessment.
struct LearningStudyRun: Identifiable, Codable, Equatable, Sendable {
    enum State: String, Codable, Sendable { case active, paused, finished }
    enum Focus: Hashable { case mixed, reviewOnly }
    struct Item: Identifiable, Codable, Equatable, Sendable {
        enum Mode: String, Codable, Sendable { case lesson, delayedReview }
        var id = UUID()
        let unitID: UUID
        let title: String
        let target: LearningStudyTarget
        let mode: Mode
        let existingSessionID: UUID?
        let earlierAttemptIDs: [UUID]
        var outcome: Outcome? = nil

        func session(in sessions: [LearningSession]) -> LearningSession? {
            let matching = sessions.filter {
                $0.chapter == nil && target.matchesRequirement($0.studyTarget)
                    && ($0.delayedReview != nil) == (mode == .delayedReview)
                    && ($0.id == existingSessionID || $0.studyRunItemID == id)
            }
            return matching.filter { $0.studyRunItemID == id }.max { $0.updatedAt < $1.updatedAt }
                ?? matching.max { $0.updatedAt < $1.updatedAt }
        }

        func newExitAttempt(in sessions: [LearningSession]) -> (LearningSession, LearningAttempt)? {
            guard let session = session(in: sessions),
                  let attempt = session.latestExitAttempt,
                  attempt.question.kind == target.kind, !earlierAttemptIDs.contains(attempt.id) else { return nil }
            return (session, attempt)
        }
    }
    struct Outcome: Codable, Equatable, Sendable {
        let sessionID: UUID
        let attemptID: UUID
        let grade: LearningGrade
        let assistanceUsed: Bool
        let independentCorrect: Bool
        let assessedAt: Date

        func isSetAside(in sessions: [LearningSession]) -> Bool {
            sessions.first { $0.id == sessionID }?.attempts.first { $0.id == attemptID }?.setAsideAt != nil
        }
    }
    enum Blocker: Equatable {
        case changedSource, changedRequirement
        case sourceReview(unitID: UUID, title: String, pageIndex: Int)
        case earlierRequirement(unitID: UUID, target: LearningStudyTarget, title: String)

        var message: String {
            switch self {
            case .changedSource: "The source changed after this plan was made. Your work is saved; finish this session and plan again from the current notes."
            case .changedRequirement: "This requirement changed in the learning path. Your work is saved; finish this session and plan again."
            case .sourceReview(_, let title, _): "Review the source for \(title) before continuing this plan."
            case .earlierRequirement(_, let target, let title): "An earlier requirement is still open: \(title) · \(target.kind.label)."
            }
        }
    }

    var id = UUID()
    let pageSignatures: [String]
    var items: [Item]
    var state: State = .active
    let startedAt: Date
    var pausedAt: Date? = nil
    var endedAt: Date? = nil
    var summaryAcknowledgedAt: Date? = nil

    var currentIndex: Int? { items.firstIndex { $0.outcome == nil } }
    var currentItem: Item? { currentIndex.map { items[$0] } }
    var attemptedCount: Int { items.filter { $0.outcome != nil }.count }

    static func plan(map: LearningStudyMap, sessions: [LearningSession], count: Int = 3, focus: Focus = .mixed, now: Date) -> Self? {
        guard map.course != nil else { return nil }
        let limit = min(3, max(1, count))
        var items: [Item] = []
        var targets = Set<UUID>()
        let reviews = map.delayedReviews(sessions: sessions, now: now)
        for review in reviews.prefix(focus == .reviewOnly ? limit : 1) where !targets.contains(review.target.id) {
            let existing = review.activeSessionID.flatMap { id in sessions.first { $0.id == id } }
            items.append(.init(unitID: review.unit.id, title: review.unit.title, target: review.target,
                mode: .delayedReview, existingSessionID: existing?.id, earlierAttemptIDs: existing?.attempts.map(\.id) ?? []))
            targets.insert(review.target.id)
        }
        if focus == .reviewOnly {
            return items.isEmpty ? nil : .init(pageSignatures: map.pageSignatures, items: items, startedAt: now)
        }
        for unit in map.studyRunUnits {
            for target in unit.studyRunTargets where items.count < limit && !targets.contains(target.id) {
                guard unit.evidence(for: target, sessions: sessions)?.hasIndependentCorrectResult != true else { continue }
                let saved = sessions.filter { $0.chapter == nil && $0.delayedReview == nil && target.matchesRequirement($0.studyTarget) }
                    .max { $0.updatedAt < $1.updatedAt }
                items.append(.init(unitID: unit.id, title: unit.title, target: target, mode: .lesson,
                    existingSessionID: saved?.id, earlierAttemptIDs: saved?.attempts.map(\.id) ?? []))
                targets.insert(target.id)
                // Keep the first blocked requirement as an actionable stop;
                // never promise later work by silently skipping a source gap.
                if unit.needsSourceReview || unit.openGapCount > 0 || unit.hasUnlocatedProof {
                    return .init(pageSignatures: map.pageSignatures, items: items, startedAt: now)
                }
            }
            if items.count == limit { break }
        }
        guard !items.isEmpty else { return nil }
        return .init(pageSignatures: map.pageSignatures, items: items, startedAt: now)
    }

    func blocker(in map: LearningStudyMap, sessions: [LearningSession]) -> Blocker? {
        guard pageSignatures == map.pageSignatures else { return .changedSource }
        guard let item = currentItem,
              let unit = map.units.first(where: { $0.id == item.unitID }),
              let target = unit.learningTargets.first(where: { $0.id == item.target.id }),
              item.unitID == item.target.unitID, target.matchesRequirement(item.target) else { return .changedRequirement }
        if unit.needsSourceReview || unit.openGapCount > 0 || unit.hasUnlocatedProof {
            return .sourceReview(unitID: unit.id, title: unit.title, pageIndex: unit.anchorPage)
        }
        // Delayed work revisits its own existing evidence. New work follows
        // the path and concept/proof/application order; it cannot jump over an
        // earlier open requirement or missing proof on the way to a later one.
        guard item.mode == .lesson else { return nil }
        for earlier in map.studyRunUnits {
            if earlier.needsSourceReview || earlier.openGapCount > 0 || earlier.hasUnlocatedProof {
                return .sourceReview(unitID: earlier.id, title: earlier.title, pageIndex: earlier.anchorPage)
            }
            for prerequisite in earlier.studyRunTargets {
                if prerequisite.id == target.id { return nil }
                if earlier.evidence(for: prerequisite, sessions: sessions)?.hasIndependentCorrectResult != true {
                    return .earlierRequirement(unitID: earlier.id, target: prerequisite, title: earlier.title)
                }
            }
        }
        return .changedRequirement
    }

    mutating func pause(at date: Date) {
        guard state == .active else { return }
        state = .paused; pausedAt = date
    }

    mutating func resume() {
        guard state == .paused else { return }
        state = .active
    }

    @discardableResult
    mutating func advance(map: LearningStudyMap, sessions: [LearningSession], at date: Date) -> Bool {
        guard state == .active, let index = currentIndex,
              blocker(in: map, sessions: sessions) == nil,
              let (session, attempt) = items[index].newExitAttempt(in: sessions), session.phase == .complete,
              attempt.hasIndependentCorrectResult,
              let unit = map.units.first(where: { $0.id == items[index].unitID }),
              Set(unit.sourceCorrectionIDs ?? []).isSubset(of: Set(session.source.passages.compactMap { $0.correction?.id })) else { return false }
        items[index].outcome = Self.outcome(session: session, attempt: attempt)
        if currentIndex == nil { state = .finished; endedAt = date }
        return true
    }

    mutating func finish(sessions: [LearningSession], at date: Date) {
        guard state != .finished else { return }
        if let index = currentIndex, let (session, attempt) = items[index].newExitAttempt(in: sessions) {
            items[index].outcome = Self.outcome(session: session, attempt: attempt)
        }
        state = .finished; endedAt = date
    }

    private static func outcome(session: LearningSession, attempt: LearningAttempt) -> Outcome {
        .init(sessionID: session.id, attemptID: attempt.id, grade: attempt.assessment.grade,
              assistanceUsed: attempt.assistanceUsed, independentCorrect: attempt.hasIndependentCorrectResult,
              assessedAt: attempt.createdAt)
    }
}

extension LearningStudyMap {
    var studyRunUnits: [LearningStudyUnit] {
        var seen = Set<UUID>()
        let ordered = course?.modules.flatMap(\.unitIDs).compactMap { id in units.first { $0.id == id } }
            ?? units.sorted { $0.anchorPage < $1.anchorPage }
        return ordered.filter { seen.insert($0.id).inserted }
    }
}

extension LearningStudyUnit {
    var studyRunTargets: [LearningStudyTarget] {
        learningTargets.enumerated().sorted {
            let lhs = LearningStudyKind.allCases.firstIndex(of: $0.element.kind) ?? 0
            let rhs = LearningStudyKind.allCases.firstIndex(of: $1.element.kind) ?? 0
            return lhs == rhs ? $0.offset < $1.offset : lhs < rhs
        }.map(\.element)
    }
}
