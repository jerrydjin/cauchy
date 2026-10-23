import Foundation
import Observation

@MainActor
@Observable
final class LearningViewModel {
    private(set) var sessions: [LearningSession] = []
    private(set) var selectedSessionID: UUID?
    enum Operation {
        case lesson, assessment, exitQuestion, chapter, clarification

        var label: String {
            switch self {
            case .lesson: "Preparing your lesson…"
            case .chapter: "Connecting the chapter ideas…"
            case .assessment: "Checking your reasoning…"
            case .exitQuestion: "Preparing a fresh exit check…"
            case .clarification: "Thinking about your question…"
            }
        }
    }
    private(set) var operation: Operation?
    var isBusy: Bool { operation != nil }
    var errorMessage: String?
    private(set) var clarificationErrorMessage: String?

    @ObservationIgnored var onChange: (([LearningSession]) -> Void)?
    @ObservationIgnored var chapterRequestIsCurrent: ((LearningChapterRequest) -> Bool)?
    @ObservationIgnored var delayedReviewRecommendation: ((UUID, Date) -> LearningReviewRecommendation?)?
    @ObservationIgnored var sourceIsCurrent: ((LearningSource) -> Bool)?
    @ObservationIgnored private let makeTutor: () -> any LearningTutorProtocol
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var operationID: UUID?

    init(makeTutor: @escaping () -> any LearningTutorProtocol = { LearningTutorService() }) {
        self.makeTutor = makeTutor
        self.now = Date.init
    }

    init(now: @escaping () -> Date, makeTutor: @escaping () -> any LearningTutorProtocol) {
        self.makeTutor = makeTutor
        self.now = now
    }

    var session: LearningSession? { sessions.first { $0.id == selectedSessionID } }

    func clarificationDraft(for context: LearningClarificationContext) -> String {
        session?.clarificationDrafts?[context.id] ?? ""
    }

    func setClarificationDraft(_ text: String, for context: LearningClarificationContext) {
        guard !isBusy, session?.canAskClarification(for: context) == true else { return }
        update { current in
            var drafts = current.clarificationDrafts ?? [:]
            let draft = String(text.prefix(2_000))
            if draft.isEmpty { drafts.removeValue(forKey: context.id) } else { drafts[context.id] = draft }
            current.clarificationDrafts = drafts.isEmpty ? nil : drafts
        }
    }

    func openedClarifications(for context: LearningClarificationContext) {
        guard !isBusy else { return }
        clarificationErrorMessage = nil
        guard session?.question != nil, session?.feedback == nil,
              let source = session?.source, sourceIsCurrent?(source) != false,
              session?.clarifications?.contains(where: { $0.context.id == context.id }) == true else { return }
        update { $0.clarificationHelpUsed = true; $0.delayedReview?.helpUsed = true }
    }

    func askClarification(for context: LearningClarificationContext) {
        guard !isBusy, let session, session.canAskClarification(for: context) else { return }
        guard checkClarificationSource(session.source) else { return }
        let question = clarificationDraft(for: context).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty else { return }
        let previous = Array((session.clarifications ?? []).filter { $0.context.id == context.id }.suffix(2))
        perform(.clarification, source: session.source) { tutor in
            let reply = try await tutor.clarify(question: question, context: context, source: session.source, previous: previous)
            return try LearningTutorService.checkedClarification(reply, source: session.source)
        } apply: { [weak self] reply, tutor in
            guard let self, self.selectedSessionID == session.id,
                  self.session?.canAskClarification(for: context) == true else { return }
            self.update { current in
                let exchange = LearningClarification(context: context, question: question, reply: reply,
                    suppliedPageIndices: Array(Set(session.source.passages.map(\.pageIndex))).sorted(),
                    previousExchangeIDs: previous.map(\.id), providerID: tutor.providerID, modelID: tutor.modelID,
                    createdAt: self.now())
                current.clarifications = (current.clarifications ?? []) + [exchange]
                current.clarificationDrafts?.removeValue(forKey: context.id)
                if current.question != nil && current.feedback == nil {
                    current.clarificationHelpUsed = true
                    current.delayedReview?.helpUsed = true
                }
            }
        }
    }

    func cancelClarification() {
        if operation == .clarification { cancel() }
    }

    private func checkClarificationSource(_ source: LearningSource) -> Bool {
        guard sourceIsCurrent?(source) != false else {
            clarificationErrorMessage = "The source has changed. Your question and saved replies are retained. Review the current source before asking for new teaching."
            return false
        }
        return true
    }

    var answerDraft: String {
        get { session?.answerDraft ?? "" }
        set {
            guard !isBusy, session?.feedback == nil, session?.chapter?.rescueVisible != true else { return }
            update { $0.answerDraft = String(newValue.prefix(12_000)) }
        }
    }

    var rescueDraft: String {
        get { session?.chapter?.rescueDraft ?? "" }
        set {
            guard !isBusy, session?.chapter?.rescueVisible == true, session?.chapter?.rescueFeedback == nil else { return }
            update { $0.chapter?.rescueDraft = String(newValue.prefix(12_000)) }
        }
    }

    var outsideHelpUsed: Bool {
        get { session?.outsideHelpUsed == true }
        set {
            guard !isBusy, session?.phase == .exitCheck, session?.feedback == nil else { return }
            update {
                $0.outsideHelpUsed = newValue
                if newValue { $0.delayedReview?.helpUsed = true }
            }
        }
    }

    func restore(_ sessions: [LearningSession]) {
        cancel()
        self.sessions = sessions
        selectedSessionID = nil
        errorMessage = nil
        clarificationErrorMessage = nil
    }

    func select(_ id: UUID) {
        guard !isBusy, let saved = sessions.first(where: { $0.id == id }) else { return }
        selectedSessionID = id
        errorMessage = nil
        clarificationErrorMessage = nil
        if sourceIsCurrent?(saved.source) == false { errorMessage = LearningError.sourceChanged.localizedDescription }
    }

    func setAssessmentAside(_ aside: Bool, sessionID: UUID, attemptID: UUID) {
        guard !isBusy, let sessionIndex = sessions.firstIndex(where: { $0.id == sessionID }),
              let attemptIndex = sessions[sessionIndex].attempts.firstIndex(where: { $0.id == attemptID }),
              (sessions[sessionIndex].attempts[attemptIndex].setAsideAt != nil) != aside else { return }
        let date = now()
        sessions[sessionIndex].attempts[attemptIndex].setAsideAt = aside ? date : nil
        sessions[sessionIndex].updatedAt = date
        save()
    }

    func revalidateSelectedSource() {
        guard let source = session?.source else { return }
        if sourceIsCurrent?(source) == false {
            errorMessage = "The source has a newer transcription. Your saved lesson, answers and citations are retained for inspection. Review the current source before new teaching or assessment."
        }
    }

    func showSections() {
        cancel()
        selectedSessionID = nil
        errorMessage = nil
    }

    func start(source: LearningSource, target: LearningStudyTarget? = nil, studyRunItemID: UUID? = nil) {
        guard !isBusy, check(source) else { return }
        perform(.lesson, source: source) { tutor in
            var lesson: LearningLesson
            if let target { lesson = try await tutor.makeLesson(source: source, target: target) }
            else { lesson = try await tutor.makeLesson(source: source) }
            if let target {
                lesson.diagnostic.kind = target.kind
                lesson.practice.kind = target.kind
                lesson.exitCheck.kind = target.kind
            }
            try LearningTutorService.validate(lesson, source: source, target: target)
            return lesson
        } apply: { [weak self] lesson, tutor in
            guard let self else { return }
            var session = LearningSession(source: source, lesson: lesson, providerID: tutor.providerID, modelID: tutor.modelID)
            session.studyTarget = target
            session.studyRunItemID = studyRunItemID
            self.sessions.insert(session, at: 0)
            self.selectedSessionID = session.id
            self.save()
        }
    }

    func startDelayedReview(_ recommendation: LearningReviewRecommendation, studyRunItemID: UUID? = nil) {
        guard !isBusy else { return }
        let startedAt = now()
        guard let current = currentDelayedReview(for: recommendation, at: startedAt) else { return }
        let previous = current.previous
        let target = current.target
        if let active = current.activeSessionID {
            select(active)
            return
        }
        guard check(previous.source), previous.source.contains(quote: previous.lesson.sourceQuote) else { return }
        let seen = questionHistory(for: previous, includeExitCheck: true)
        perform(.exitQuestion, source: previous.source) { tutor in
            var lesson = previous.lesson
            lesson.exitCheck.kind = target.kind
            let question = try await tutor.newExitQuestion(lesson: lesson, source: previous.source, previous: seen)
            return try LearningTutorService.checkedExitQuestion(question, kind: target.kind, previous: seen)
        } apply: { [weak self] question, tutor in
            guard let self, let latest = self.currentDelayedReview(for: current, at: self.now()),
                  latest.activeSessionID == nil, latest.previous.id == previous.id,
                  latest.dueAt == current.dueAt else { return }
            var lesson = previous.lesson
            lesson.exitCheck = question
            var review = LearningSession(source: previous.source, lesson: lesson, providerID: tutor.providerID, modelID: tutor.modelID,
                                         createdAt: startedAt, updatedAt: startedAt)
            review.studyTarget = target
            review.studyRunItemID = studyRunItemID
            review.phase = .exitCheck
            review.delayedReview = .init(previousSessionID: previous.id, scheduledFor: current.dueAt,
                                        startedAt: startedAt, round: (previous.delayedReview?.round ?? 0) + 1)
            sessions.insert(review, at: 0)
            selectedSessionID = review.id
            save()
        }
    }

    private func currentDelayedReview(for requested: LearningReviewRecommendation, at date: Date) -> LearningReviewRecommendation? {
        let current: LearningReviewRecommendation?
        if let delayedReviewRecommendation {
            current = delayedReviewRecommendation(requested.target.id, date)
        } else {
            // Standalone view models still resolve saved work, rather than
            // treating a captured recommendation as permission for a new check.
            current = LearningStudyMap(pageSignatures: [], pages: [], units: [requested.unit])
                .nextDelayedReview(sessions: sessions, now: date, targetID: requested.target.id)
        }
        guard requested.target.unitID == requested.unit.id,
              let current, current.target.matchesRequirement(requested.target) else {
            errorMessage = "This delayed check is no longer available for the current requirement. Your work is saved. Open the learning path to see what is ready now."
            return nil
        }
        return current
    }

    func startChapter(request: LearningChapterRequest, source: LearningSource) {
        guard !isBusy, check(source), checkChapterRequest(request) else { return }
        if let saved = sessions.first(where: {
            $0.chapter?.request.hasSameRequirements(as: request) == true && $0.source == source
        }) {
            select(saved.id)
            return
        }
        do { try LearningTutorService.validateChapterRequest(request, source: source) }
        catch { errorMessage = error.localizedDescription; return }
        let previous = chapterQuestionHistory(for: request)
        perform(.chapter, source: source, chapterRequest: request) { tutor in
            let challenge = try await tutor.makeChapterChallenge(request: request, source: source, previous: previous)
            try LearningTutorService.validate(challenge, request: request, source: source, previous: previous)
            return challenge
        } apply: { [weak self] challenge, tutor in
            guard let self else { return }
            // Reuse the persisted session envelope; this is not a local lesson
            // and deliberately has no studyTarget, so no topic earns credit.
            var session = LearningSession(source: source, lesson: challenge.sessionEnvelope, phase: .exitCheck,
                providerID: tutor.providerID, modelID: tutor.modelID)
            session.chapter = .init(request: request, challenge: challenge)
            self.sessions.insert(session, at: 0)
            self.selectedSessionID = session.id
            self.save()
        }
    }

    func openPrerequisiteRescue() {
        guard !isBusy, let session, session.chapter != nil, session.phase == .exitCheck,
              session.feedback == nil, check(session.source) else { return }
        update {
            $0.chapter?.assistanceUsed = true
            $0.chapter?.rescueVisible = true
        }
    }

    func returnToChapter() {
        guard session?.chapter?.rescueVisible == true else { return }
        cancel()
        update { $0.chapter?.rescueVisible = false }
    }

    func setChapterScrollOffset(_ offset: Double) {
        guard offset.isFinite, offset >= 0, let chapter = session?.chapter, !chapter.rescueVisible,
              (chapter.scrollOffset ?? 0) != offset else { return }
        update { $0.chapter?.scrollOffset = offset }
    }

    func setChapterPosition(_ position: String) {
        guard ["argument", "reasoning"].contains(position), let chapter = session?.chapter,
              chapter.position != position else { return }
        update { $0.chapter?.position = position }
    }

    func reviseChapterArgument(sessionID: UUID, attemptID: UUID) {
        guard !isBusy, selectedSessionID == sessionID, let session, let chapter = session.chapter,
              !chapter.rescueVisible, let attempt = session.latestExitAttempt, attempt.id == attemptID,
              attempt.question == chapter.challenge.question,
              session.phase == .complete || (session.phase == .exitCheck && session.feedback == attempt.assessment) else { return }
        guard check(session.source), checkChapterRequest(chapter.request) else { return }
        errorMessage = nil
        update {
            $0.phase = .exitCheck
            $0.answerDraft = attempt.answer
            $0.feedback = nil
            $0.chapter?.revisingAttemptID = attempt.id
            $0.chapter?.assistanceUsed = true
            $0.chapter?.position = "reasoning"
            $0.chapter?.scrollOffset = nil
        }
    }

    func freshChapterCheck() {
        guard !isBusy, let session, let chapter = session.chapter, session.phase == .complete,
              check(session.source) else { return }
        guard checkChapterRequest(chapter.request) else { return }
        let previous = chapterQuestionHistory(for: chapter.request)
        perform(.chapter, source: session.source, chapterRequest: chapter.request) { tutor in
            let challenge = try await tutor.makeChapterChallenge(request: chapter.request, source: session.source, previous: previous)
            try LearningTutorService.validate(challenge, request: chapter.request, source: session.source, previous: previous)
            return challenge
        } apply: { [weak self] challenge, _ in
            self?.update {
                $0.lesson = challenge.sessionEnvelope
                $0.chapter?.challenge = challenge
                $0.chapter?.assistanceUsed = false
                $0.chapter?.rescueVisible = false
                $0.chapter?.rescueDraft = ""
                $0.chapter?.rescueFeedback = nil
                $0.chapter?.revisingAttemptID = nil
                $0.chapter?.position = "argument"
                $0.chapter?.scrollOffset = nil
                $0.move(to: .exitCheck)
            }
        }
    }

    private func submitRescueCheck() {
        guard !isBusy, let session, let chapter = session.chapter, chapter.rescueVisible,
              chapter.rescueFeedback == nil, check(session.source) else { return }
        let answer = chapter.rescueDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !answer.isEmpty else { return }
        let question = chapter.challenge.refresher.check
        perform(.assessment, source: session.source) { tutor in
            try LearningTutorService.checkedAssessment(
                await tutor.assess(question: question, answer: answer, source: session.source), question: question)
        } apply: { [weak self] assessment, tutor in
            self?.update {
                $0.chapter?.rescueAttempts.append(.init(phase: .practice, question: question, answer: answer,
                    assessment: assessment, assistanceUsed: true, providerID: tutor.providerID, modelID: tutor.modelID))
                $0.chapter?.rescueFeedback = assessment
            }
        }
    }

    func submitAnswer() {
        if session?.chapter?.rescueVisible == true { submitRescueCheck(); return }
        guard !isBusy, let session, session.feedback == nil, let question = session.question,
              check(session.source) else { return }
        let answer = session.answerDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !answer.isEmpty else { return }
        perform(.assessment, source: session.source) { tutor in
            let assessment = try await tutor.assess(question: question, answer: answer, source: session.source)
            return try LearningTutorService.checkedAssessment(assessment, question: question)
        } apply: { [weak self] assessment, tutor in
            self?.update { current in
                var attempt = LearningAttempt(
                    phase: session.phase, question: question, answer: answer, assessment: assessment,
                    assistanceUsed: session.assistanceUsed,
                    providerID: tutor.providerID, modelID: tutor.modelID
                )
                attempt.createdAt = self?.now() ?? Date()
                current.attempts.append(attempt)
                current.chapter?.revisingAttemptID = nil
                if session.phase == .exitCheck, session.studyTarget != nil, session.chapter == nil,
                   attempt.hasIndependentCorrectResult || session.delayedReview != nil {
                    let delay: TimeInterval = attempt.hasIndependentCorrectResult && session.delayedReview != nil ? 3 * 86_400 : 86_400
                    current.reviewDueAt = attempt.createdAt.addingTimeInterval(delay)
                }
                current.feedback = assessment
            }
        }
    }

    func revealHint() {
        guard !isBusy, let session, session.phase == .practice, session.feedback == nil,
              let question = session.question, session.hintsRevealed < question.hints.count else { return }
        update { $0.hintsRevealed += 1; $0.delayedReview?.helpUsed = true }
    }

    func revealSolution() {
        guard !isBusy, session?.phase == .practice, session?.feedback != nil else { return }
        update { $0.solutionRevealed = true; $0.delayedReview?.helpUsed = true }
    }

    func openedSource() {
        guard !isBusy, let session, session.question != nil, sourceIsCurrent?(session.source) != false else { return }
        update { $0.sourceOpened = true; $0.delayedReview?.helpUsed = true }
    }

    func tryAgain() {
        guard !isBusy, session?.phase == .practice else { return }
        update { $0.feedback = nil }
    }

    func studyInstead() {
        guard !isBusy, let session, session.phase == .diagnostic,
              session.feedback == nil, check(session.source) else { return }
        update { $0.move(to: .lesson); $0.delayedReview?.helpUsed = true }
    }

    func reviewIdea() {
        guard !isBusy, let session, session.phase == .practice,
              check(session.source) else { return }
        update { $0.move(to: .lesson); $0.delayedReview?.helpUsed = true }
    }

    func selectLessonPart(_ index: Int) {
        guard !isBusy, let session, session.phase == .lesson,
              session.lesson.parts.indices.contains(index) else { return }
        update { $0.lessonPartIndex = index }
    }

    func continueLesson() {
        guard !isBusy, let session, session.phase == .lesson else { return }
        let next = session.currentLessonPartIndex + 1
        if session.lesson.parts.indices.contains(next) { selectLessonPart(next) }
        else { advance() }
    }

    func advance() {
        guard !isBusy, let session, check(session.source) else { return }
        switch session.phase {
        case .diagnostic:
            guard session.feedback != nil else { return }
            if session.feedbackSupportsProgress {
                prepareExitCheck(session)
            } else {
                update { $0.move(to: .lesson) }
            }
        case .lesson:
            update { $0.move(to: .practice) }
        case .practice:
            // Feedback alone is not evidence of readiness for an independent check.
            guard session.feedbackSupportsProgress else { return }
            prepareExitCheck(session)
        case .exitCheck:
            guard session.feedback != nil else { return }
            update { $0.move(to: .complete) }
        case .complete: break
        }
    }

    func practiseAgain() {
        guard !isBusy, let session, session.chapter == nil, session.phase == .complete, check(session.source) else { return }
        update { $0.move(to: .lesson); $0.delayedReview?.helpUsed = true }
    }

    private func prepareExitCheck(_ session: LearningSession) {
        let previous = questionHistory(for: session, includeExitCheck: false)
        let candidate = LearningSource.normalized(session.lesson.exitCheck.prompt)
        if !previous.contains(where: { LearningSource.normalized($0) == candidate }) {
            update { $0.move(to: .exitCheck) }
            return
        }
        let kind = session.studyTarget?.kind ?? session.lesson.exitCheck.kind
        var lesson = session.lesson
        lesson.exitCheck.kind = kind
        perform(.exitQuestion, source: session.source) { tutor in
            let question = try await tutor.newExitQuestion(lesson: lesson, source: session.source, previous: previous)
            return try LearningTutorService.checkedExitQuestion(question, kind: kind, previous: previous)
        } apply: { [weak self] question, _ in
            self?.update {
                $0.lesson.exitCheck = question
                $0.move(to: .exitCheck)
            }
        }
    }

    private func chapterQuestionHistory(for request: LearningChapterRequest) -> [String] {
        let unitIDs = Set(request.units.map(\.id))
        let prompts = sessions.filter {
            guard let saved = $0.chapter?.request else { return false }
            return saved.moduleID == request.moduleID || Set(saved.units.map(\.id)) == unitIDs
        }.flatMap { session in
            (session.chapter.map { [$0.challenge.question.prompt] } ?? []) + session.attempts.map(\.question.prompt)
        }
        var seen = Set<String>()
        return prompts.filter { seen.insert(LearningSource.normalized($0)).inserted }
    }

    /// Exact-repeat prevention, not a semantic novelty or transfer judgement.
    /// Include saved generated questions conservatively, even if unattempted.
    private func questionHistory(for session: LearningSession, includeExitCheck: Bool) -> [String] {
        let related = sessions.filter { other in
            guard other.id != session.id, other.chapter == nil else { return false }
            // Prior wording still counts as a seen question, not as current evidence.
            if let target = session.studyTarget { return other.studyTarget?.id == target.id }
            return other.studyTarget == nil && other.source == session.source
        }
        let prompts = [session.lesson.diagnostic.prompt, session.lesson.practice.prompt]
            + (includeExitCheck ? [session.lesson.exitCheck.prompt] : [])
            + session.attempts.map(\.question.prompt)
            + related.flatMap { [$0.lesson.diagnostic.prompt, $0.lesson.practice.prompt, $0.lesson.exitCheck.prompt]
                + $0.attempts.map(\.question.prompt) }
        var seen = Set<String>()
        return prompts.filter {
            let normalized = LearningSource.normalized($0)
            return !normalized.isEmpty && seen.insert(normalized).inserted
        }
    }

    func cancel() {
        operationID = nil
        task?.cancel()
        task = nil
        operation = nil
    }

    func waitForOperation() async { await task?.value }

    private func check(_ source: LearningSource) -> Bool {
        guard sourceIsCurrent?(source) != false else {
            errorMessage = LearningError.sourceChanged.localizedDescription
            return false
        }
        return true
    }

    private func checkChapterRequest(_ request: LearningChapterRequest) -> Bool {
        guard chapterRequestIsCurrent?(request) != false else {
            errorMessage = "This challenge no longer matches the current learning path or source obligations. Open the current learning path before preparing another challenge. Your saved work is still here."
            return false
        }
        return true
    }

    private func update(_ change: (inout LearningSession) -> Void) {
        guard let index = sessions.firstIndex(where: { $0.id == selectedSessionID }) else { return }
        change(&sessions[index])
        sessions[index].updatedAt = now()
        save()
    }

    private func save() { onChange?(sessions) }

    private func perform<Result>(
        _ kind: Operation,
        source: LearningSource,
        chapterRequest: LearningChapterRequest? = nil,
        _ operation: @escaping @MainActor (any LearningTutorProtocol) async throws -> Result,
        apply: @escaping @MainActor (Result, any LearningTutorProtocol) -> Void
    ) {
        guard !isBusy else { return }
        if kind == .clarification { clarificationErrorMessage = nil } else { errorMessage = nil }
        self.operation = kind
        let id = UUID()
        operationID = id
        task = Task { [weak self] in
            guard let self else { return }
            let tutor = self.makeTutor()
            do {
                let result = try await operation(tutor)
                try Task.checkCancellation()
                guard self.operationID == id else { return }
                // Source checks before a request cannot authorize a response
                // against notes or chapter obligations that changed while it ran.
                let currentSource = kind == .clarification ? self.checkClarificationSource(source) : self.check(source)
                if currentSource, chapterRequest.map({ self.checkChapterRequest($0) }) ?? true {
                    apply(result, tutor)
                }
            } catch {
                guard self.operationID == id else { return }
                if !(error is CancellationError) {
                    if kind == .clarification { self.clarificationErrorMessage = error.localizedDescription }
                    else { self.errorMessage = error.localizedDescription }
                }
            }
            guard self.operationID == id else { return }
            self.operation = nil
            self.operationID = nil
            self.task = nil
        }
    }
}
