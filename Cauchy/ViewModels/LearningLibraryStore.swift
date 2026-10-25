import AppKit
import Observation
import PDFKit

enum LearningDestination: Hashable {
    case document(UUID)
    case studyMap(UUID)
    case passage(UUID)
    case session(document: UUID, session: UUID)

    var documentID: UUID {
        switch self {
        case .document(let id), .studyMap(let id), .passage(let id), .session(let id, _): id
        }
    }
}

struct LearningLibraryReview: Identifiable, Equatable {
    var id: UUID { workspaceID }
    let workspaceID: UUID
    let title: String
    let dueCount: Int
    let inProgressCount: Int
    let earliestDate: Date
}

/// Learning owns its PDF and tutor state independently of reader windows.
/// The saved document record remains shared, with one current learning model
/// per document and a merged snapshot for every write.
@MainActor
@Observable
final class LearningDocument: Identifiable {
    nonisolated let id: UUID
    var title: String { snapshot.documentURL.deletingPathExtension().lastPathComponent }
    var pageCount: Int { pdfDocument.pageCount }
    let pdfDocument: PDFDocument
    let learning: LearningViewModel
    let studyMap: LearningStudyMapViewModel
    var isBusy: Bool { learning.isBusy || studyMap.isBusy }
    /// Locate recovery from actual page/transcription provenance. A removed
    /// page falls back to the nearest page that still exists in this PDF.
    var selectedSourceReviewPage: Int? {
        learning.session.flatMap { sourceReviewPage(for: $0) }
    }

    func sourceReviewPage(for session: LearningSession) -> Int? {
        let source = session.source
        func availablePage(_ index: Int) -> Int { min(max(0, index), max(0, pageCount - 1)) }
        guard !source.passages.isEmpty else { return availablePage(sourcePageIndex) }
        guard let changed = source.passages.first(where: {
            !LearningSourceBuilder.matches(.init(passages: [$0]), document: pdfDocument, map: studyMap.map)
        }) else { return nil }
        return availablePage(changed.pageIndex)
    }
    var sourcePageIndex = 0
    var selectedPassage: LearningSourcePassage?
    var sourceRequestID = UUID()
    var requestsNewSection = false
    var notesVisible = false
    var notesPageIndex = 0
    var saveError: String?
    var snapshot: DocumentWorkspace
    var bookmarkData: Data?
    let isVerificationFixture: Bool

    init(workspace: DocumentWorkspace, document: PDFDocument, bookmarkData: Data?,
         learning: LearningViewModel? = nil, studyMap: LearningStudyMapViewModel? = nil,
         isVerificationFixture: Bool = false) {
        id = workspace.id
        snapshot = workspace
        pdfDocument = document
        self.bookmarkData = bookmarkData
        self.isVerificationFixture = isVerificationFixture
        self.learning = learning ?? LearningViewModel()
        self.studyMap = studyMap ?? LearningStudyMapViewModel(map: workspace.learningStudyMap)
        self.learning.restore(workspace.learningSessions)
        self.learning.chapterRequestIsCurrent = { [weak self] request in
            self?.studyMap.map?.isCurrentChapterRequest(request) == true
        }
        self.learning.delayedReviewRecommendation = { [weak self] targetID, date in
            guard let self else { return nil }
            return self.studyMap.map?.nextDelayedReview(sessions: self.learning.sessions, now: date, targetID: targetID)
        }
        self.learning.sourceIsCurrent = { [weak self] source in
            guard let self else { return false }
            return LearningSourceBuilder.matches(source, document: self.pdfDocument, map: self.studyMap.map)
        }
    }

    func showNotes(at pageIndex: Int? = nil) {
        notesPageIndex = min(max(pageIndex ?? sourcePageIndex, 0), max(0, pageCount - 1))
        learning.openedSource()
        notesVisible = true
    }

    func savedChapter(for request: LearningChapterRequest) -> LearningSession? {
        guard studyMap.map?.isCurrentChapterRequest(request) == true else { return nil }
        return learning.sessions.first {
            $0.chapter?.request.hasSameRequirements(as: request) == true && sourceReviewPage(for: $0) == nil
        }
    }
}

@MainActor
@Observable
final class LearningLibraryStore: Equatable {
    static let shared = LearningLibraryStore()
    nonisolated static func == (lhs: LearningLibraryStore, rhs: LearningLibraryStore) -> Bool { lhs === rhs }

    var destination: LearningDestination?
    private(set) var documents: [UUID: LearningDocument] = [:]
    private(set) var summaries: [WorkspaceSummary] = []
    private(set) var isLoading = false
    private(set) var isLoadingReviews = false
    private(set) var unreadableReviewTitles: [String] = []
    var unreadableReviewNotes: Int { unreadableReviewTitles.count }
    private struct ReviewRevision: Equatable {
        let sessions: UInt64
        let map: UInt64
    }
    private var reviewProgress: [UUID: LearningReviewSchedule] = [:]
    @ObservationIgnored private var liveReviewCache: [UUID: (revision: ReviewRevision, schedule: LearningReviewSchedule)] = [:]
    private var reviewRequestID: UUID?
    var errorMessage: String?
    private var openRequestID: UUID?
    private let persistence: DocumentPersistenceService
    private let makeDocument: (DocumentWorkspace, PDFDocument, Data?) -> LearningDocument
    let isVerificationFixture: Bool

    var selectedDocument: LearningDocument? { destination.flatMap { documents[$0.documentID] } }

    init(persistence: DocumentPersistenceService = .shared) {
        self.persistence = persistence
        makeDocument = { LearningDocument(workspace: $0, document: $1, bookmarkData: $2) }
        isVerificationFixture = false
    }

    #if DEBUG
    init(verificationPersistence: DocumentPersistenceService,
         makeDocument: @escaping (DocumentWorkspace, PDFDocument, Data?) -> LearningDocument) {
        persistence = verificationPersistence
        self.makeDocument = makeDocument
        isVerificationFixture = true
    }
    #endif

    func flushPendingSaves() async throws { try await persistence.flushAll() }

    func refreshLibrary() async {
        summaries = await persistence.listWorkspaceSummaries()
    }

    /// Prepare small schedules on explicit review, not on every sidebar refresh.
    /// Closed PDFs stay closed; full histories are not kept in the overview cache.
    func refreshReviewOverview(excluding hidden: Set<UUID> = []) async {
        let request = UUID()
        reviewRequestID = request
        isLoadingReviews = true
        defer { if reviewRequestID == request { isLoadingReviews = false } }
        await refreshLibrary()
        guard reviewRequestID == request, !Task.isCancelled else { return }
        var progress: [UUID: LearningReviewSchedule] = [:]
        var unreadable: [String] = []
        for summary in summaries {
            guard reviewRequestID == request, !Task.isCancelled else { return }
            if hidden.contains(summary.workspaceID) { continue }
            if let live = documents[summary.workspaceID] {
                let revision = reviewRevision(for: live)
                if liveReviewCache[live.id]?.revision == revision { continue }
                let schedule = await Self.prepareReviewSchedule(map: live.studyMap.map, sessions: live.learning.sessions)
                guard reviewRequestID == request, !Task.isCancelled else { return }
                if revision == reviewRevision(for: live) { liveReviewCache[live.id] = (revision, schedule) }
                continue
            }
            if let saved = await persistence.loadWorkspace(id: summary.workspaceID),
               saved.workspace.id == summary.workspaceID, saved.workspace.documentURL == summary.documentURL {
                progress[summary.workspaceID] = await Self.prepareReviewSchedule(map: saved.workspace.learningStudyMap,
                    sessions: saved.workspace.learningSessions)
            } else { unreadable.append(summary.documentURL.deletingPathExtension().lastPathComponent) }
        }
        guard reviewRequestID == request, !Task.isCancelled else { return }
        reviewProgress = progress
        unreadableReviewTitles = unreadable.sorted()
    }

    private nonisolated static func prepareReviewSchedule(map: LearningStudyMap?, sessions: [LearningSession]) async -> LearningReviewSchedule {
        await Task.detached(priority: .utility) { map?.delayedReviewSchedule(sessions: sessions) ?? .empty }.value
    }

    private func reviewRevision(for document: LearningDocument) -> ReviewRevision {
        .init(sessions: document.learning.sessionsRevision, map: document.studyMap.mapRevision)
    }

    private func liveReviewSchedule(for document: LearningDocument) -> LearningReviewSchedule {
        // Reading both revisions keeps observation connected even on a cache hit.
        let revision = reviewRevision(for: document)
        if let cached = liveReviewCache[document.id], cached.revision == revision { return cached.schedule }
        let schedule = document.studyMap.map?.delayedReviewSchedule(sessions: document.learning.sessions) ?? .empty
        liveReviewCache[document.id] = (revision, schedule)
        return schedule
    }

    func reviewOverview(at date: Date, excluding hidden: Set<UUID> = []) -> [LearningLibraryReview] {
        summaries.compactMap { summary -> LearningLibraryReview? in
            guard !hidden.contains(summary.workspaceID) else { return nil }
            let schedule = documents[summary.workspaceID].map { liveReviewSchedule(for: $0) } ?? reviewProgress[summary.workspaceID]
            guard let status = schedule?.status(at: date) else { return nil }
            return .init(workspaceID: summary.workspaceID, title: summary.documentURL.deletingPathExtension().lastPathComponent,
                dueCount: status.dueCount, inProgressCount: status.inProgressCount, earliestDate: status.earliestDate)
        }.sorted {
            if ($0.inProgressCount > 0) != ($1.inProgressCount > 0) { return $0.inProgressCount > 0 }
            if $0.earliestDate != $1.earliestDate { return $0.earliestDate < $1.earliestDate }
            return $0.workspaceID.uuidString < $1.workspaceID.uuidString
        }
    }

    @discardableResult
    func install(_ workspace: DocumentWorkspace, document: PDFDocument, bookmarkData: Data?) -> LearningDocument {
        if let existing = documents[workspace.id] {
            var snapshot = workspace
            synchronize(&snapshot, bookmarkData: bookmarkData)
            return existing
        }
        let entry = makeDocument(workspace, document, bookmarkData)
        documents[workspace.id] = entry
        entry.learning.onChange = { [weak self, weak entry] sessions in
            guard let self, let entry else { return }
            entry.snapshot.learningSessions = sessions
            self.persist(entry)
        }
        entry.studyMap.onChange = { [weak self, weak entry] map in
            guard let self, let entry else { return }
            entry.snapshot.learningStudyMap = map
            self.persist(entry)
        }
        return entry
    }

    private func persist(_ entry: LearningDocument) {
        if isVerificationFixture { save(entry); return }
        // Update a live reader's canonical record before its next save.
        if let reader = OpenDocumentRegistry.shared.holder(of: entry.snapshot.documentURL),
           reader.workspace?.id == entry.id {
            reader.workspace?.learningSessions = entry.learning.sessions
            reader.workspace?.learningStudyMap = entry.studyMap.map
            reader.persistWorkspace()
        } else {
            save(entry)
        }
    }

    func activate(from reader: WorkspaceViewModel, newSection: Bool = false) {
        guard !isVerificationFixture else { return }
        guard let workspace = reader.workspace, let readerPDF = reader.pdfDocument else { return }
        // A separate PDF view avoids sharing PDFKit selection and layout state.
        guard let document = documents[workspace.id]?.pdfDocument
            ?? PDFDocument(url: workspace.documentURL)
            ?? readerPDF.dataRepresentation().flatMap({ PDFDocument(data: $0) }) else { return }
        let entry = install(workspace, document: document, bookmarkData: reader.bookmarkData)
        openRequestID = nil
        isLoading = false
        if !entry.isBusy {
            entry.requestsNewSection = newSection
            entry.sourcePageIndex = max(0, reader.currentPage - 1)
            if let thread = reader.selectionThread.activeThread, !thread.selectedText.isEmpty {
                entry.selectedPassage = .init(pageIndex: thread.pageIndex, text: thread.selectedText)
            } else {
                entry.selectedPassage = nil
            }
            if newSection { entry.learning.showSections() }
            entry.sourceRequestID = UUID()
        }
        destination = entry.learning.selectedSessionID.map { .session(document: entry.id, session: $0) }
            ?? (entry.requestsNewSection ? .passage(entry.id) : .document(entry.id))
        errorMessage = nil
    }

    /// Called by every reader save, including closing/changing its document.
    /// Reading fields come from the reader; learning fields come from this store.
    func synchronize(_ workspace: inout DocumentWorkspace, bookmarkData: Data?) {
        guard !isVerificationFixture else { return }
        guard let entry = documents[workspace.id] else { return }
        workspace.learningSessions = entry.learning.sessions
        workspace.learningStudyMap = entry.studyMap.map
        entry.snapshot = workspace
        entry.bookmarkData = bookmarkData
    }

    func navigate(to destination: LearningDestination) async {
        if let entry = documents[destination.documentID], entry.isBusy {
            openRequestID = nil
            isLoading = false
            self.destination = entry.learning.selectedSessionID.map { .session(document: entry.id, session: $0) }
                ?? (entry.studyMap.isBusy ? .studyMap(entry.id) : .document(entry.id))
            return
        }
        if documents[destination.documentID] == nil {
            guard let summary = summaries.first(where: { $0.workspaceID == destination.documentID }) else { return }
            if isVerificationFixture {
                #if DEBUG
                let root = persistence.applicationSupportRoot().deletingLastPathComponent()
                guard let verifiedRoot = try? LearningUIFixture.validatedRoot(root.path),
                      let saved = await persistence.loadWorkspace(id: summary.workspaceID),
                      saved.workspace.id == summary.workspaceID,
                      saved.workspace.documentURL.standardizedFileURL.resolvingSymlinksInPath().deletingLastPathComponent() == verifiedRoot,
                      saved.workspace.documentURL == summary.documentURL,
                      let pdf = PDFDocument(url: saved.workspace.documentURL) else {
                    errorMessage = "Couldn’t open these saved authored fixture notes. The PDF or saved record is unavailable, or its location is outside the temporary root."
                    return
                }
                _ = install(saved.workspace, document: pdf, bookmarkData: nil)
                #else
                return
                #endif
            } else {
                await open(summary.documentURL)
                guard selectedDocument?.id == destination.documentID else { return }
            }
        }
        guard let entry = documents[destination.documentID] else { return }
        openRequestID = nil
        isLoading = false
        switch destination {
        case .document, .studyMap:
            entry.requestsNewSection = false
            entry.learning.showSections()
        case .passage:
            entry.requestsNewSection = true
            entry.learning.showSections()
        case .session(_, let id):
            entry.requestsNewSection = false
            entry.learning.select(id)
        }
        self.destination = destination
    }

    func openNotes() {
        guard !isVerificationFixture else {
            errorMessage = "This authored verification workspace uses only its temporary fixture PDF. Open normal notes in the regular app."
            return
        }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.pdf]
        panel.allowsMultipleSelection = false
        panel.message = "Choose notes to learn from."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task { await open(url) }
    }

    func open(_ url: URL) async {
        guard !isVerificationFixture else {
            errorMessage = "The verification fixture cannot import documents from the normal library."
            return
        }
        let request = UUID()
        openRequestID = request
        isLoading = true
        errorMessage = nil
        if let reader = OpenDocumentRegistry.shared.holder(of: url), reader.workspace != nil {
            activate(from: reader)
            await refreshLibrary()
            return
        }
        if let entry = documents.values.first(where: { $0.snapshot.documentURL.standardizedFileURL == url.standardizedFileURL }) {
            destination = entry.learning.selectedSessionID.map { .session(document: entry.id, session: $0) }
                ?? (entry.studyMap.isBusy ? .studyMap(entry.id) : .document(entry.id))
            isLoading = false
            await refreshLibrary()
            return
        }
        do {
            let persisted = try await persistence.loadWorkspace(for: url)
            guard openRequestID == request else { return }
            let resolved = persisted?.bookmarkData.flatMap { try? persistence.resolveBookmark($0) } ?? url
            guard let document = PDFDocument(url: resolved) else {
                throw CocoaError(.fileReadCorruptFile)
            }
            var workspace = persisted?.workspace ?? DocumentWorkspace(documentURL: resolved)
            workspace.documentURL = resolved
            let entry = install(workspace, document: document,
                                bookmarkData: persisted?.bookmarkData ?? (try? persistence.createBookmark(for: resolved)))
            destination = entry.learning.selectedSessionID.map { .session(document: entry.id, session: $0) }
                ?? .document(entry.id)
            save(entry)
            await refreshLibrary()
        } catch {
            if openRequestID == request { errorMessage = "Couldn’t open “\(url.lastPathComponent)”. \(error.localizedDescription)" }
        }
        if openRequestID == request { isLoading = false }
    }

    private func save(_ entry: LearningDocument) {
        persistence.scheduleSave(entry.snapshot, bookmarkData: entry.bookmarkData, learningOnly: true) { [weak entry] error in
            Task { @MainActor in entry?.saveError = "Couldn’t save your learning progress. \(error.localizedDescription)" }
        }
    }
}
