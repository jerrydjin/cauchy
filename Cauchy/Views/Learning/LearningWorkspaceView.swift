import AppKit
import PDFKit
import SwiftUI
import UniformTypeIdentifiers

private struct LearningPlanActionKey: FocusedValueKey {
    typealias Value = () -> Void
}

private struct LearningHistorySearchActionKey: FocusedValueKey {
    typealias Value = () -> Void
}

extension FocusedValues {
    var findSavedLearningLesson: (() -> Void)? {
        get { self[LearningHistorySearchActionKey.self] }
        set { self[LearningHistorySearchActionKey.self] = newValue }
    }
    var planLearningSession: (() -> Void)? {
        get { self[LearningPlanActionKey.self] }
        set { self[LearningPlanActionKey.self] = newValue }
    }
}

struct LearningWorkspaceView: View {
    @Bindable var library: LearningLibraryStore
    @State private var assistantPreferenceRevision = 0
    @State private var showingStudyPlan = false
    @State private var lessonDetails: LearningSession?
    @State private var showingHistorySearch = false
    @State private var showingReviewOverview = false
    @AppStorage("library.hiddenRecents") private var hiddenRecents = ""
    // Learn has one window. Keep its last working location across window
    // closure and app termination, when scene storage may be discarded.
    @AppStorage("learning.workspace.document") private var restoredDocument = ""
    @AppStorage("learning.workspace.session") private var restoredSession = ""
    @AppStorage("learning.workspace.studyMap") private var restoredStudyMap = false
    @AppStorage("learning.workspace.passage") private var restoredPassage = false

    private var canPlanStudySession: Bool {
        _ = assistantPreferenceRevision
        guard lessonDetails == nil, !showingStudyPlan, !showingHistorySearch, !showingReviewOverview,
              let document = library.selectedDocument, !document.isBusy,
              document.studyMap.map?.course != nil else { return false }
        let run = document.studyMap.currentStudyRun
        guard run == nil || (run?.state == .finished && run?.summaryAcknowledgedAt != nil) else { return false }
        return document.isVerificationFixture || AskPresentation.current().canAsk
    }

    private var canFindSavedLesson: Bool {
        guard lessonDetails == nil, !showingStudyPlan, !showingHistorySearch, !showingReviewOverview,
              let document = library.selectedDocument else { return false }
        return !document.isBusy && !document.learning.sessions.isEmpty
    }

    private var sidebarSelection: Binding<LearningDestination?> {
        Binding(get: {
            guard let document = library.selectedDocument else { return library.destination }
            if library.destination == .studyMap(document.id) || library.destination == .passage(document.id) { return library.destination }
            return document.learning.selectedSessionID.map { .session(document: document.id, session: $0) }
                ?? .document(document.id)
        }, set: { destination in
            guard let destination else { return }
            Task { await library.navigate(to: destination) }
        })
    }

    var body: some View {
        NavigationSplitView {
            List(selection: sidebarSelection) {
                Section("Your notes") {
                    ForEach(library.summaries.filter { !hiddenRecents.split(separator: ",").contains(Substring($0.workspaceID.uuidString)) }, id: \.workspaceID) { summary in
                        HStack {
                            Label(summary.documentURL.deletingPathExtension().lastPathComponent, systemImage: "doc.text")
                                .lineLimit(2)
                            if library.documents[summary.workspaceID]?.isBusy == true {
                                Spacer()
                                ProgressView().controlSize(.small).accessibilityLabel("Tutor working on this document")
                            }
                        }
                        .tag(LearningDestination.document(summary.workspaceID))
                    }
                }
                if let document = library.selectedDocument {
                    Section("Study") {
                        Label("Learning path", systemImage: "list.bullet.rectangle")
                            .tag(LearningDestination.studyMap(document.id))
                        Label("Study a passage", systemImage: "text.viewfinder")
                            .tag(LearningDestination.passage(document.id))
                    }
                }
                if let document = library.selectedDocument, !document.learning.sessions.isEmpty {
                    Section("Lessons") {
                        ForEach(document.learning.sessions.sorted { $0.updatedAt > $1.updatedAt }) { session in
                            LearningHistoryRow(session: session)
                            .tag(LearningDestination.session(document: document.id, session: session.id))
                        }
                    }
                }
            }
            .listStyle(.sidebar)
            .navigationTitle("Learn")
            .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 340)
        } detail: {
            Group {
                if library.isLoading {
                    ProgressView("Opening your notes…").frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let document = library.selectedDocument {
                    Group {
                        if library.destination == .studyMap(document.id) || library.destination == .document(document.id) {
                            LearningStudyMapView(document: document, onStudyPassage: {
                                Task { await library.navigate(to: .passage(document.id)) }
                            }, onPlanStudySession: { showingStudyPlan = true })
                        } else {
                            LearningSessionView(document: document) {
                                Task { await library.navigate(to: .studyMap(document.id)) }
                            }
                        }
                    }
                        .id(document.id)
                        .inspector(isPresented: Binding(get: { document.notesVisible }, set: { visible in
                            if visible { document.showNotes() } else { document.notesVisible = false }
                        })) {
                            LearningNotesView(document: document)
                                .inspectorColumnWidth(min: 280, ideal: 380, max: 520)
                        }
                } else {
                    VStack(spacing: 20) {
                        ContentUnavailableView("Learn from your notes", systemImage: "graduationcap",
                                               description: Text("Open your notes to build a learning path across the whole document."))
                        Button("Open notes…", systemImage: "doc.badge.plus") { library.openNotes() }
                            .buttonStyle(.glassProminent).controlSize(.large)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .navigationTitle(library.selectedDocument.map { "Learn — \($0.title)" } ?? "Learn")
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup {
                    Button("Open notes", systemImage: "doc.badge.plus") { library.openNotes() }
                        .help("Open notes to learn from (⌘O)")
                        .disabled(library.isVerificationFixture)
                }
                ToolbarSpacer(.fixed)
                ToolbarItem {
                    if let document = library.selectedDocument, let run = document.studyMap.currentStudyRun, run.state != .finished {
                        Menu("Study session", systemImage: "list.bullet.clipboard") {
                            if run.state == .active {
                                Button("Pause session") {
                                    document.pauseStudyRun()
                                    Task { await library.navigate(to: .studyMap(document.id)) }
                                }
                            } else {
                                Button("Resume session") { document.continueStudyRun() }.disabled(document.isBusy)
                            }
                            Button("Finish session here") {
                                document.finishStudyRun()
                                Task { await library.navigate(to: .studyMap(document.id)) }
                            }
                        }.disabled(document.studyMap.isBusy)
                    }
                }
                ToolbarItem {
                    Button("Review across notes", systemImage: "calendar.badge.clock") { showingReviewOverview = true }
                        .keyboardShortcut("r", modifiers: [.command, .shift])
                        .help("See due checks and unfinished reviews across your notes (⇧⌘R)")
                        .disabled(lessonDetails != nil || showingStudyPlan || showingHistorySearch || showingReviewOverview)
                }
                ToolbarItem {
                    Button("Find a saved lesson", systemImage: "magnifyingglass") { showingHistorySearch = true }
                        .help("Find a saved lesson (⇧⌘F)")
                        .disabled(!canFindSavedLesson)
                }
                ToolbarItem {
                    if let document = library.selectedDocument, document.learning.session != nil {
                        Button("Lesson details", systemImage: "info.circle") {
                            // Resolve at invocation: toolbar shortcuts can retain
                            // their action across selection changes.
                            lessonDetails = library.selectedDocument?.learning.session
                        }
                            .help("Lesson details (⇧⌘D)")
                            .keyboardShortcut("d", modifiers: [.command, .shift])
                            .disabled(document.isBusy)
                    }
                }
                ToolbarItem {
                    if library.isVerificationFixture {
                        Label("Offline fixture", systemImage: "testtube.2")
                    } else {
                        ModelPicker(style: .toolbar) {
                            NotificationCenter.default.post(name: .assistantPreferencesChanged, object: nil)
                        }
                        .disabled(library.selectedDocument?.isBusy == true)
                    }
                }
                ToolbarSpacer(.fixed)
                ToolbarItem {
                    Button("Notes", systemImage: "sidebar.trailing") {
                        guard let document = library.selectedDocument else { return }
                        if document.notesVisible { document.notesVisible = false } else { document.showNotes() }
                    }
                    .disabled(library.selectedDocument == nil)
                    .help("Show or hide the source notes")
                }
            }
        }
        .navigationSplitViewStyle(.balanced)
        .focusedSceneValue(\.learningLibrary, library)
        .focusedSceneValue(\.planLearningSession, canPlanStudySession ? { showingStudyPlan = true } : nil)
        .focusedSceneValue(\.findSavedLearningLesson, canFindSavedLesson ? { showingHistorySearch = true } : nil)
        .sheet(isPresented: $showingHistorySearch) {
            if let document = library.selectedDocument {
                LearningHistorySearchView(document: document) { id in
                    guard library.selectedDocument?.id == document.id else { return }
                    Task { await library.navigate(to: .session(document: document.id, session: id)) }
                }
            }
        }
        .sheet(isPresented: $showingStudyPlan) {
            if let document = library.selectedDocument { LearningStudyRunPlanView(document: document) }
        }
        .sheet(item: $lessonDetails) { session in LearningHistoryDetailsView(session: session) }
        .frame(minWidth: 1000, minHeight: 720)
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            guard !library.isVerificationFixture else { return false }
            guard let provider = providers.first else { return false }
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url, url.pathExtension.lowercased() == "pdf" else { return }
                Task { @MainActor in await library.open(url) }
            }
            return true
        }
        .alert("Couldn’t open your notes", isPresented: Binding(get: { library.errorMessage != nil && !showingReviewOverview }, set: { if !$0 { library.errorMessage = nil } })) {
            Button("OK") { library.errorMessage = nil }
        } message: {
            Text(library.errorMessage ?? "")
        }
        .onChange(of: library.selectedDocument?.id) {
            let id = library.selectedDocument?.id.uuidString ?? ""
            if restoredDocument != id { restoredSession = "" }
            restoredDocument = id
        }
        .sheet(isPresented: $showingReviewOverview) {
            LearningReviewOverviewView(library: library, hiddenRecents: hiddenRecents)
        }
        .onChange(of: library.selectedDocument?.learning.selectedSessionID) {
            guard let document = library.selectedDocument else { return }
            if let id = document.learning.selectedSessionID {
                library.destination = .session(document: document.id, session: id)
            }
            rememberLocation(document)
        }
        .onChange(of: library.destination) {
            if let document = library.selectedDocument { rememberLocation(document) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .assistantPreferencesChanged)) { _ in
            assistantPreferenceRevision += 1
        }
        .task(id: assistantPreferenceRevision) {
            // Verification fixtures remain entirely offline. Normal Learn opens
            // must initiate readiness without requiring a visit to the reader.
            guard !library.isVerificationFixture else { return }
            await ProviderReadinessStore.shared.probeIfNeededCurrentSelection()
        }
        .task {
            await library.refreshLibrary()
            if let document = library.selectedDocument {
                if document.requestsNewSection {
                    document.requestsNewSection = false
                    restoredDocument = document.id.uuidString
                    restoredSession = ""
                    restoredStudyMap = false
                    restoredPassage = true
                    return
                }
                if document.learning.selectedSessionID == nil,
                   document.id.uuidString == restoredDocument, let id = UUID(uuidString: restoredSession),
                   document.learning.sessions.contains(where: { $0.id == id }) {
                    await library.navigate(to: .session(document: document.id, session: id))
                }
                rememberLocation(document)
                return
            }
            guard library.selectedDocument == nil, let documentID = UUID(uuidString: restoredDocument) else { return }
            let destination: LearningDestination = UUID(uuidString: restoredSession).map { .session(document: documentID, session: $0) }
                ?? (restoredPassage ? .passage(documentID) : restoredStudyMap ? .studyMap(documentID) : .document(documentID))
            await library.navigate(to: destination)
        }
    }

    private func rememberLocation(_ document: LearningDocument) {
        restoredDocument = document.id.uuidString
        restoredSession = document.learning.selectedSessionID?.uuidString ?? ""
        restoredStudyMap = library.destination == .studyMap(document.id)
        restoredPassage = library.destination == .passage(document.id)
    }
}

private struct LearningHistoryMetadata {
    let session: LearningSession

    var category: String {
        session.delayedReview != nil ? "Delayed check" : session.chapter != nil ? "Chapter challenge" : "Lesson"
    }

    var kind: String? {
        let kind = session.studyTarget?.kind ?? session.lesson.exitCheck.kind
        return switch kind {
        case .concept: "Concept"
        case .proof: "Proof"
        case .application: "Application"
        case nil: nil
        }
    }

    var context: String { kind.map { "\(category) · \($0)" } ?? category }
    var sidebarContext: String { category == "Lesson" ? kind ?? category : category }
    var startedAt: Date { session.delayedReview?.startedAt ?? session.createdAt }
    var startedLabel: String { startedAt.formatted(date: .abbreviated, time: .shortened) }
    var summary: String { "\(context) · \(session.progressLabel)\nStarted \(startedLabel)" }
}

private struct LearningHistoryRow: View {
    let session: LearningSession
    private var metadata: LearningHistoryMetadata { .init(session: session) }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(session.lesson.title, systemImage: session.delayedReview != nil ? "clock.arrow.circlepath" : session.passedExitCheck ? "checkmark.circle" : "book")
                .lineLimit(2)
            Text("\(metadata.sidebarContext) · \(session.progressLabel)")
                .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 4)
        .help("\(session.lesson.title)\n\(metadata.summary)")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(session.lesson.title), \(metadata.summary)")
    }
}

private struct LearningHistorySearchView: View {
    @Bindable var document: LearningDocument
    let onOpen: (UUID) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var selection: UUID?
    private var results: [LearningHistorySearch.Match] {
        LearningHistorySearch.results(in: document.learning.sessions, query: query)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Find a saved lesson").font(.title2.weight(.semibold))
            Text(document.title).font(.callout).foregroundStyle(.secondary).lineLimit(1).help(document.title)
            LearningHistorySearchField(text: $query, onMove: moveSelection, onOpen: {
                if let selection { open(selection) }
            }, onCancel: { dismiss() }).frame(height: 24)
            if results.isEmpty {
                ContentUnavailableView(query.isEmpty ? "No saved lessons" : "No matching lessons", systemImage: "magnifyingglass",
                    description: Text("Try a title, a question, or part of your own answer."))
                    .frame(maxWidth: .infinity).frame(height: 320)
            } else {
                ScrollViewReader { scroll in
                    List(selection: $selection) {
                        ForEach(results) { result in
                            VStack(alignment: .leading, spacing: 5) {
                                LearningHistoryRow(session: result.session)
                                if let snippet = result.snippet { Text(snippet).font(.callout).lineLimit(2) }
                                Text("Started \(LearningHistoryMetadata(session: result.session).startedLabel)")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            .contentShape(Rectangle()).tag(result.id).id(result.id)
                            .onTapGesture(count: 2) { open(result.id) }
                        }
                    }
                    .accessibilityLabel("Matching saved lessons")
                    .onChange(of: selection) {
                        if let selection { scroll.scrollTo(selection) }
                    }
                }.frame(height: 320)
            }
            HStack {
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Text("\(results.count) \(results.count == 1 ? "lesson" : "lessons")")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Open lesson") { if let selection { open(selection) } }
                    .buttonStyle(.glassProminent).keyboardShortcut(.defaultAction)
                    .disabled(document.isBusy || !results.contains { $0.id == selection })
            }
        }
        .padding(24).frame(width: 560)
        .onAppear { selection = document.learning.selectedSessionID ?? results.first?.id }
        .onChange(of: query) {
            if !results.contains(where: { $0.id == selection }) { selection = results.first?.id }
        }
    }

    private func moveSelection(backwards: Bool) {
        guard !results.isEmpty else { return }
        guard let index = results.firstIndex(where: { $0.id == selection }) else { selection = results.first?.id; return }
        selection = results[min(max(index + (backwards ? -1 : 1), 0), results.count - 1)].id
    }

    private func open(_ id: UUID) {
        guard !document.isBusy, results.contains(where: { $0.id == id }) else { return }
        onOpen(id)
        dismiss()
    }
}

/// NSTextField's editor consumes arrow keys before SwiftUI's key handler.
/// Handle its native movement commands while preserving ordinary text editing.
private struct LearningHistorySearchField: NSViewRepresentable {
    @Binding var text: String
    let onMove: (Bool) -> Void
    let onOpen: () -> Void
    let onCancel: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSSearchField {
        let field = InitiallyFocusedSearchField()
        field.placeholderString = "Titles, questions and your work"
        field.maximumRecents = 0
        field.sendsSearchStringImmediately = true
        field.delegate = context.coordinator
        field.setAccessibilityLabel("Search saved lessons in these notes")
        return field
    }

    func updateNSView(_ field: NSSearchField, context: Context) {
        context.coordinator.parent = self
        if field.stringValue != text { field.stringValue = text }
    }

    final class Coordinator: NSObject, NSSearchFieldDelegate {
        var parent: LearningHistorySearchField
        init(_ parent: LearningHistorySearchField) { self.parent = parent }
        func controlTextDidChange(_ notification: Notification) {
            if let field = notification.object as? NSSearchField { parent.text = field.stringValue }
        }
        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            switch commandSelector {
            case #selector(NSResponder.moveDown(_:)): parent.onMove(false)
            case #selector(NSResponder.moveUp(_:)): parent.onMove(true)
            case #selector(NSResponder.insertNewline(_:)): parent.onOpen()
            case #selector(NSResponder.cancelOperation(_:)): parent.onCancel()
            default: return false
            }
            return true
        }
    }

    private final class InitiallyFocusedSearchField: NSSearchField {
        private var needsInitialFocus = true
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard window != nil, needsInitialFocus else { return }
            needsInitialFocus = false
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.window?.makeFirstResponder(self)
            }
        }
    }
}

private struct LearningHistoryDetailsView: View {
    let session: LearningSession
    @Environment(\.dismiss) private var dismiss
    private var metadata: LearningHistoryMetadata { .init(session: session) }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Lesson details").font(.title2.weight(.semibold))
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text(session.lesson.title).font(.headline).textSelection(.enabled)
                    Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 12) {
                        GridRow { Text("Activity").foregroundStyle(.secondary); Text(metadata.category) }
                        if let kind = metadata.kind {
                            GridRow { Text("Focus").foregroundStyle(.secondary); Text(kind) }
                        }
                        GridRow { Text("Status").foregroundStyle(.secondary); Text(session.progressLabel) }
                        GridRow { Text("Started").foregroundStyle(.secondary); Text(metadata.startedLabel) }
                    }.font(.callout).textSelection(.enabled)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.trailing, 8)
            }.frame(maxHeight: 360)
            HStack {
                Spacer()
                Button("Done") { dismiss() }.buttonStyle(.glassProminent).keyboardShortcut(.cancelAction)
            }
        }.padding(24).frame(width: 460)
    }
}

private struct LearningNotesView: View {
    @Bindable var document: LearningDocument
    @State private var transcriptionPage: Int?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Source notes").font(.headline)
                Spacer()
                Button("Close notes", systemImage: "xmark") { document.notesVisible = false }
                    .labelStyle(.iconOnly).buttonStyle(.glass)
            }.padding(16)
            Divider()
            LearningSourcePDFView(document: document.pdfDocument, pageIndex: document.notesPageIndex)
            Button("Review transcription…", systemImage: "text.magnifyingglass") {
                transcriptionPage = document.notesPageIndex
            }
            .buttonStyle(.borderless).padding(.top, 8)
            .disabled(document.isBusy || document.studyMap.map == nil)
            .help("Compare extracted text with the original PDF and save a deliberate correction after preparing the learning path.")
            HStack {
                Button("Previous page", systemImage: "chevron.left") { document.notesPageIndex -= 1 }
                    .labelStyle(.iconOnly).disabled(document.notesPageIndex == 0)
                Spacer()
                Text("Page \(document.notesPageIndex + 1) of \(document.pageCount)").font(.callout.monospacedDigit())
                Spacer()
                Button("Next page", systemImage: "chevron.right") { document.notesPageIndex += 1 }
                    .labelStyle(.iconOnly).disabled(document.notesPageIndex >= document.pageCount - 1)
            }.padding(16)
        }
        .onChange(of: document.notesPageIndex) {
            if document.learning.session == nil { document.sourcePageIndex = document.notesPageIndex }
        }
        .sheet(isPresented: Binding(get: { transcriptionPage != nil }, set: { if !$0 { transcriptionPage = nil } })) {
            if let page = transcriptionPage { LearningTranscriptionReviewView(document: document, pageIndex: page) }
        }
    }
}

private struct LearningTranscriptionReviewView: View {
    @Bindable var document: LearningDocument
    let pageIndex: Int
    private let originalText: String
    @State private var transcription: String
    @State private var note = ""
    @State private var confirmed = false
    @State private var error: String?
    @Environment(\.dismiss) private var dismiss

    init(document: LearningDocument, pageIndex: Int) {
        self.document = document
        self.pageIndex = pageIndex
        let original = document.pdfDocument.page(at: pageIndex)?.string ?? ""
        originalText = original
        _transcription = State(initialValue: document.studyMap.map?.latestCorrection(for: pageIndex)?.correctedText ?? original)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Review PDF page \(pageIndex + 1)").font(.title2.weight(.semibold))
            Text("Compare the full page with the original. Your correction is saved as user-verified transcription; the PDF and original extraction are retained.")
                .font(.callout).foregroundStyle(.secondary)
            HSplitView {
                LearningSourcePDFView(document: document.pdfDocument, pageIndex: pageIndex)
                    .frame(minWidth: 360, minHeight: 400)
                    .accessibilityLabel("Original PDF page \(pageIndex + 1)")
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        DisclosureGroup("Original extracted text — unchanged") {
                            Text(originalText).font(.callout).textSelection(.enabled)
                        }
                        Text("Your full-page transcription").font(.headline)
                        TextEditor(text: $transcription)
                            .font(.body).frame(minHeight: 240)
                            .accessibilityLabel("Full-page corrected transcription")
                        TextField("What did you correct?", text: $note, axis: .vertical)
                            .textFieldStyle(.roundedBorder).lineLimit(2...4)
                            .accessibilityLabel("Correction note")
                        Toggle("I compared this transcription with the original PDF", isOn: $confirmed)
                        if let history = document.studyMap.map?.sourceCorrections?.filter({ $0.pageIndex == pageIndex }), !history.isEmpty {
                            DisclosureGroup("Correction history (\(history.count))") {
                                ForEach(history.reversed()) { revision in
                                    DisclosureGroup(revision.createdAt.formatted(date: .abbreviated, time: .shortened)) {
                                        Text(revision.note).font(.callout)
                                        Text(revision.correctedText).font(.callout).textSelection(.enabled)
                                    }.padding(.top, 8)
                                }
                            }
                        }
                        Text("Saving flags affected topics for source review. It does not certify a proof, grade an answer, or replace your saved learner work.")
                            .font(.caption).foregroundStyle(.secondary)
                    }.padding(.leading, 16)
                }.frame(minWidth: 360)
            }
            if let error { Label(error, systemImage: "exclamationmark.circle").font(.callout).textSelection(.enabled) }
            HStack {
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Save verified transcription") {
                    do {
                        try document.studyMap.saveCorrection(pageIndex: pageIndex, originalText: originalText,
                            correctedText: transcription, note: note, confirmed: confirmed)
                        document.learning.revalidateSelectedSource()
                        dismiss()
                    } catch { self.error = error.localizedDescription }
                }
                .buttonStyle(.glassProminent).keyboardShortcut(.defaultAction)
                .disabled(!confirmed || note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || document.isBusy)
            }
        }
        .padding(24).frame(minWidth: 900, idealWidth: 1060, minHeight: 660)
    }
}

private struct LearningSourcePDFView: NSViewRepresentable {
    let document: PDFDocument
    let pageIndex: Int

    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePage
        view.backgroundColor = .windowBackgroundColor
        return view
    }

    func updateNSView(_ view: PDFView, context: Context) {
        if view.document !== document { view.document = document }
        if let page = document.page(at: pageIndex), view.currentPage !== page { view.go(to: page) }
    }
}

private struct LearningReviewOverviewView: View {
    let library: LearningLibraryStore
    let hiddenRecents: String
    @State private var selection: UUID?
    @State private var clock = Date()
    @State private var opening = false
    @State private var openError: String?
    @State private var overviewPrepared = false
    @Environment(\.dismiss) private var dismiss

    private var hidden: Set<UUID> { Set(hiddenRecents.split(separator: ",").compactMap { UUID(uuidString: String($0)) }) }
    private var reviews: [LearningLibraryReview] { overviewPrepared ? library.reviewOverview(at: clock, excluding: hidden) : [] }
    private var isPreparing: Bool { !overviewPrepared || library.isLoadingReviews }
    private var selected: LearningLibraryReview? { reviews.first { $0.id == selection } }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Review across notes").font(.title2.weight(.semibold))
            Text("Return to an unfinished review or revisit an idea after a delay.").font(.callout).foregroundStyle(.secondary)
            if isPreparing, !reviews.isEmpty {
                ProgressView("Checking saved notes…").controlSize(.small)
            }
            if library.unreadableReviewNotes > 0 {
                DisclosureGroup("\(library.unreadableReviewNotes) \(library.unreadableReviewNotes == 1 ? "set of notes couldn’t" : "sets of notes couldn’t") be checked") {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(library.unreadableReviewTitles.enumerated()), id: \.offset) { _, title in
                            Text(title).font(.callout).textSelection(.enabled)
                        }
                        Text("Try refreshing or open these notes from the sidebar.").font(.caption).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(.top, 8)
                }
            }
            if reviews.isEmpty {
                ContentUnavailableView(isPreparing ? "Checking your reviews"
                    : library.unreadableReviewNotes > 0 ? "Some notes couldn’t be checked" : "No reviews due",
                    systemImage: "calendar.badge.clock", description: Text(isPreparing
                        ? "Reading saved learning progress."
                        : library.unreadableReviewNotes > 0 ? "No due reviews were found in the notes that could be checked."
                        : "A review is scheduled after an independent exit check. Your learning paths remain available."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(selection: $selection) {
                    ForEach(reviews) { review in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(review.title).font(.headline)
                            Text(status(review)).font(.callout)
                            Text("Earliest scheduled check: \(review.earliestDate.formatted(date: .abbreviated, time: .omitted))")
                                .font(.caption).foregroundStyle(.secondary)
                        }.padding(.vertical, 6).tag(review.id)
                    }
                }.accessibilityLabel("Notes with due or unfinished reviews")
            }
            Text("Open a learning path to review its current requirements and source.").font(.caption).foregroundStyle(.secondary)
            if let openError { Text(openError).font(.callout).foregroundStyle(.secondary).textSelection(.enabled) }
            HStack {
                Button("Close") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Refresh", systemImage: "arrow.clockwise") {
                    Task { await library.refreshReviewOverview(excluding: hidden); clock = Date() }
                }.disabled(library.isLoadingReviews || opening)
                Spacer()
                Button("Open learning path") {
                    guard let selected else { return }
                    openError = nil
                    library.errorMessage = nil
                    opening = true
                    Task {
                        await library.navigate(to: .studyMap(selected.workspaceID))
                        opening = false
                        if library.selectedDocument?.id == selected.workspaceID { dismiss() }
                        else {
                            openError = library.errorMessage ?? "These notes couldn’t be opened. Refresh the overview or reopen the PDF from the sidebar."
                            library.errorMessage = nil
                        }
                    }
                }
                .buttonStyle(.glassProminent).keyboardShortcut(.defaultAction)
                .disabled(selected == nil || opening || library.isLoading)
            }
        }
        .padding(24).frame(minWidth: 560, idealWidth: 640, minHeight: 460, idealHeight: 560)
        .multilineTextAlignment(.leading)
        .task(id: hiddenRecents) {
            await library.refreshReviewOverview(excluding: hidden)
            guard !Task.isCancelled else { return }
            overviewPrepared = true
            selectFirstIfNeeded()
        }
        .onChange(of: reviews.map(\.id)) { selectFirstIfNeeded() }
        .onReceive(Timer.publish(every: 60, on: .main, in: .common).autoconnect()) { clock = $0 }
    }

    private func selectFirstIfNeeded() {
        if !reviews.contains(where: { $0.id == selection }) { selection = reviews.first?.id }
    }

    private func status(_ review: LearningLibraryReview) -> String {
        [review.inProgressCount > 0 ? "\(review.inProgressCount) in progress" : nil,
         review.dueCount > 0 ? "\(review.dueCount) due" : nil].compactMap { $0 }.joined(separator: " · ")
    }
}
