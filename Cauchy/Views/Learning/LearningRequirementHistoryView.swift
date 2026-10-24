import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct LearningRequirementHistoryView: View {
    @Bindable var document: LearningDocument
    let target: LearningStudyTarget
    @Environment(\.dismiss) private var dismiss
    @State private var selection: String?
    @State private var exportError: String?
    private struct ExportWindow { weak var value: NSWindow? }
    @State private var exportWindow = ExportWindow()
    @State private var isExporting = false
    private enum Pane: Hashable { case list, details }
    @FocusState private var focusedPane: Pane?
    @State private var detailScroll = ScrollPosition()
    @State private var detailOffset: CGFloat = 0
    private var entries: [LearningRequirementHistory.Entry] {
        LearningRequirementHistory.entries(for: target, in: document.learning.sessions)
    }
    private var selected: LearningRequirementHistory.Entry? { entries.first { $0.id == selection } }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Review my work").font(.title2.weight(.semibold))
            Text(target.kind.label).font(.callout).foregroundStyle(.secondary)
            DisclosureGroup("Learning requirement") {
                ScrollView { MessageContentView(content: target.objective).padding(.top, 8) }.frame(height: 100)
            }
            HSplitView {
                List(selection: $selection) {
                    ForEach(entries) { entry in
                        VStack(alignment: .leading, spacing: 5) {
                            Text(entry.activity).font(.subheadline.weight(.medium))
                            Text(entry.status).font(.callout)
                            Text(entry.date.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4).tag(entry.id).contentShape(Rectangle())
                        .onTapGesture(count: 2) { open(entry) }
                    }
                }
                .accessibilityLabel("Saved reasoning for this requirement")
                .focused($focusedPane, equals: .list).frame(minWidth: 210, idealWidth: 230, maxWidth: 280)
                ScrollView {
                    if let selected {
                        details(selected).padding(16)
                    } else {
                        Text("No saved reasoning for this requirement yet.").foregroundStyle(.secondary).padding(24)
                    }
                }
                .scrollPosition($detailScroll)
                .onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.y } action: { _, offset in detailOffset = offset }
                .focusable().focused($focusedPane, equals: .details)
                .onKeyPress(keys: [.space, .pageUp, .pageDown], phases: [.down, .repeat]) { key in
                    guard key.modifiers.isEmpty || (key.key == .space && key.modifiers == .shift) else { return .ignored }
                    let backwards = key.key == .pageUp || key.modifiers.contains(.shift)
                    detailScroll.scrollTo(y: max(0, detailOffset + (backwards ? -340 : 340)))
                    return .handled
                }
                .onChange(of: selection) { detailScroll.scrollTo(edge: .top) }
                .frame(minWidth: 350)
            }.frame(height: 400)
            HStack {
                Button("Close") { dismiss() }.keyboardShortcut(.cancelAction)
                readingFocusButton
                Menu("Export work", systemImage: "square.and.arrow.up") {
                    Button("Save selected record…") { if let selection { exportWork(entryID: selection) } }
                        .disabled(selected == nil)
                    Button("Save requirement history…") { exportWork(entryID: nil) }
                }
                .disabled(document.isBusy || entries.isEmpty || isExporting || exportWindow.value == nil)
                .help("Save your reasoning and tutor feedback as Markdown")
                Spacer()
                Button("Open saved lesson") { if let selected { open(selected) } }
                    .buttonStyle(.glassProminent).keyboardShortcut(.defaultAction)
                    .disabled(document.isBusy || selected == nil)
            }
        }
        .padding(24).frame(width: 800)
        .background(WindowAccessor { window in
            if exportWindow.value !== window { exportWindow = ExportWindow(value: window) }
        })
        .onAppear { selection = entries.first?.id; focusedPane = .list }
        .alert("Couldn’t export your work", isPresented: Binding(
            get: { exportError != nil }, set: { if !$0 { exportError = nil } }
        )) {
            Button("OK") { exportError = nil }
        } message: { Text(exportError ?? "") }
    }

    @ViewBuilder private var readingFocusButton: some View {
        if focusedPane == .details {
            Button("Choose another record") { focusedPane = .list }
                .buttonStyle(.borderless).keyboardShortcut("r", modifiers: .command)
                .help("Return to the saved records (⌘R)")
        } else {
            Button("Read selected work") { focusedPane = .details }
                .buttonStyle(.borderless).keyboardShortcut("r", modifiers: .command)
                .help("Read and scroll the selected work (⌘R)")
                .disabled(selected == nil)
        }
    }

    private func details(_ entry: LearningRequirementHistory.Entry) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(entry.lessonTitle).font(.headline).textSelection(.enabled)
            Text("\(entry.activity) · \(entry.status)").font(.callout).foregroundStyle(.secondary)
            if let session = document.learning.sessions.first(where: { $0.id == entry.sessionID }),
               !target.matchesRequirement(session.studyTarget) {
                DisclosureGroup(entry.requirementObjective != target.objective ? "Earlier requirement wording" : "Earlier requirement version") {
                    MessageContentView(content: entry.requirementObjective).padding(.top, 8)
                    Text("This saved work does not establish the current requirement.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            if entry.phase != .lesson {
                Text(entry.assistanceUsed ? "Help was recorded for this \(entry.isDraft ? "question" : "answer")."
                     : "No help was recorded for this \(entry.isDraft ? "question" : "answer").")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let session = document.learning.sessions.first(where: { $0.id == entry.sessionID }),
               document.sourceReviewPage(for: session) != nil {
                Text("This saved work uses earlier source text. Open the saved lesson to review the current notes.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            if !entry.isDraft, entry.recordedKind != target.kind {
                Text(entry.recordedKind == nil ? "The question’s requirement kind was not recorded."
                     : "The saved question has a different requirement kind. This record does not establish this requirement.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Text(entry.phase == .lesson ? "Learning goal" : "Question").font(.subheadline.weight(.semibold))
            MessageContentView(content: entry.question)
            if entry.phase != .lesson {
                Text(entry.isDraft ? "Your saved draft" : "Your answer").font(.subheadline.weight(.semibold))
                MessageContentView(content: entry.answer.isEmpty ? "No answer was saved." : entry.answer)
            }
            if let assessment = entry.assessment {
                Text("Tutor feedback").font(.subheadline.weight(.semibold))
                if entry.incompleteCriteriaAssessment || entry.setAsideAt != nil {
                    Text("Recorded tutor grade: \(assessment.grade.label)." + (entry.incompleteCriteriaAssessment
                        ? " The reasoning checks do not support a complete assessment." : ""))
                        .font(.caption).foregroundStyle(.secondary)
                }
                MessageContentView(content: assessment.feedback)
                if let attemptID = entry.attemptID,
                   let attempt = document.learning.sessions.first(where: { $0.id == entry.sessionID })?.attempts.first(where: { $0.id == attemptID }) {
                    LearningAssessmentReviewControl(learning: document.learning, sessionID: entry.sessionID, attempt: attempt)
                }
                Text("Next step").font(.subheadline.weight(.semibold))
                MessageContentView(content: assessment.nextStep)
                if let criteria = assessment.criteria, !criteria.isEmpty {
                    DisclosureGroup("Reasoning checks") {
                        ForEach(Array(criteria.enumerated()), id: \.offset) { _, criterion in
                            VStack(alignment: .leading, spacing: 6) {
                                if entry.rubric.indices.contains(criterion.index) {
                                    Text(entry.rubric[criterion.index]).font(.subheadline.weight(.medium))
                                } else {
                                    Text("Recorded check index: \(criterion.index)").font(.subheadline.weight(.medium))
                                }
                                Text(criterion.outcome == .met ? "Met" : criterion.outcome == .notMet ? "Not met" : "Uncertain")
                                    .font(.caption).foregroundStyle(.secondary)
                                MessageContentView(content: criterion.feedback)
                            }.padding(.top, 10)
                        }
                    }
                }
                DisclosureGroup("Assessment details") {
                    Text("\(entry.date.formatted(date: .abbreviated, time: .shortened)) · \(entry.providerID)\(entry.modelID.map { " / \($0)" } ?? "")")
                        .font(.caption).foregroundStyle(.secondary).textSelection(.enabled).padding(.top, 8)
                }
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private func open(_ entry: LearningRequirementHistory.Entry) {
        guard !document.isBusy else { return }
        document.learning.select(entry.sessionID)
        dismiss()
    }

    private func exportWork(entryID: String?) {
        guard !isExporting, let hostWindow = exportWindow.value,
            let text = LearningRequirementHistoryExport.markdown(documentTitle: document.title, target: target,
            sessions: document.learning.sessions, selectedEntryID: entryID,
            sourceIsCurrent: { document.sourceReviewPage(for: $0) == nil }) else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText]
        panel.title = "Export learning work"
        panel.message = entryID == nil ? "Save your work and tutor feedback for this requirement." : "Save the selected question, answer and feedback."
        panel.nameFieldStringValue = "\(document.title.prefix(60)) — \(target.kind.rawValue) \(entryID == nil ? "history" : "record").md"
        panel.prompt = "Export"
        isExporting = true
        panel.beginSheetModal(for: hostWindow) { response in
            panel.orderOut(nil)
            isExporting = false
            guard response == .OK, let url = panel.url else { return }
            do { try text.write(to: url, atomically: true, encoding: .utf8) }
            catch { exportError = error.localizedDescription }
        }
    }
}
