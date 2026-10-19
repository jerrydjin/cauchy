import PDFKit
import SwiftUI
import UniformTypeIdentifiers

struct LearningWorkspaceView: View {
    @Bindable var library: LearningLibraryStore
    @AppStorage("library.hiddenRecents") private var hiddenRecents = ""
    // Learn has one window. Keep its last working location across window
    // closure and app termination, when scene storage may be discarded.
    @AppStorage("learning.workspace.document") private var restoredDocument = ""
    @AppStorage("learning.workspace.session") private var restoredSession = ""
    @AppStorage("learning.workspace.studyMap") private var restoredStudyMap = false
    @AppStorage("learning.workspace.passage") private var restoredPassage = false

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
                            LearningStudyMapView(document: document) {
                                Task { await library.navigate(to: .passage(document.id)) }
                            }
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
        .alert("Couldn’t open your notes", isPresented: Binding(get: { library.errorMessage != nil }, set: { if !$0 { library.errorMessage = nil } })) {
            Button("OK") { library.errorMessage = nil }
        } message: {
            Text(library.errorMessage ?? "")
        }
        .onChange(of: library.selectedDocument?.id) {
            let id = library.selectedDocument?.id.uuidString ?? ""
            if restoredDocument != id { restoredSession = "" }
            restoredDocument = id
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

private struct LearningHistoryRow: View {
    let session: LearningSession

    private var context: String {
        let category = session.delayedReview != nil ? "Delayed check" : session.chapter != nil ? "Chapter challenge" : "Lesson"
        let kind = session.studyTarget?.kind ?? session.lesson.exitCheck.kind
        let kindLabel: String? = switch kind {
        case .concept: "Concept"
        case .proof: "Proof"
        case .application: "Application"
        case nil: nil
        }
        return kindLabel.map { "\(category) · \($0)" } ?? category
    }

    private var startedAt: Date { session.delayedReview?.startedAt ?? session.createdAt }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(session.lesson.title, systemImage: session.delayedReview != nil ? "clock.arrow.circlepath" : session.passedExitCheck ? "checkmark.circle" : "book")
                .lineLimit(2)
            Text(context).font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text(session.progressLabel).font(.caption).foregroundStyle(.secondary)
            Text("Started \(startedAt.formatted(date: .abbreviated, time: .shortened))")
                .font(.caption2).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
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
