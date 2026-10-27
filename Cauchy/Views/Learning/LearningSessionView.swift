import SwiftUI

struct LearningSessionView: View {
    @Bindable var document: LearningDocument
    var onShowStudyMap: () -> Void = {}
    @State private var sourceMode = SourceMode.currentPage
    @State private var firstPage = "1"
    @State private var lastPage = "1"
    @FocusState private var answerFocused: Bool
    @State private var assistantPreferenceRevision = 0
    private var assistantPresentation: AskPresentation {
        _ = assistantPreferenceRevision
        return AskPresentation.current()
    }
    private var assistantAvailable: Bool { document.isVerificationFixture || assistantPresentation.canAsk }
    @State private var showingFullLesson = false
    @State private var showingCriteria = false
    @State private var showingPracticeHelp = false
    @State private var clarificationContext: LearningClarificationContext?
    @FocusState private var clarificationActionFocused: Bool
    @FocusState private var feedbackActionFocused: Bool
    @State private var returningToFeedback = false
    @State private var chapterScroll = ScrollPosition()
    @State private var answerEditRequest = 0
    @State private var startingQuestionsShown: Set<UUID> = []
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var lessonTint: Color {
        switch learning.session?.phase {
        case .practice: .teal
        case .exitCheck, .complete: .purple
        default: .indigo
        }
    }

    private enum SourceMode: Hashable { case currentPage, selection, pages }
    private var learning: LearningViewModel { document.learning }
    private var sourceNeedsReview: Bool { document.selectedSourceReviewPage != nil }
    private var chapterUsesEarlierPath: Bool {
        guard let request = learning.session?.chapter?.request else { return false }
        return document.studyMap.map?.isCurrentChapterRequest(request) != true
    }
    private var selectedPassage: String? {
        guard let text = document.selectedPassage?.text, !text.isEmpty else { return nil }
        return text
    }
    private var pageRange: ClosedRange<Int>? {
        try? LearningSourceBuilder.pageRange(first: firstPage, last: lastPage, pageCount: document.pageCount)
    }
    private var canStart: Bool {
        assistantAvailable && !document.studyMap.isBusy
            && (sourceMode != .pages || pageRange != nil)
            && (sourceMode != .selection || selectedPassage != nil)
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if let error = document.saveError {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.secondary).textSelection(.enabled)
                    }
                    if let page = document.selectedSourceReviewPage { changedSourceContent(page: page) }
                    else if let error = learning.errorMessage, learning.session == nil || learning.session?.chapter != nil {
                        errorContent(error)
                    }
                    if let session = learning.session {
                        if let run = document.selectedStudyRun {
                            Text("Study session · \((run.currentIndex ?? 0) + 1) of \(run.items.count)")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        if let chapter = session.chapter { chapterContent(session, chapter: chapter) }
                        else { sessionContent(session) }
                    } else {
                        sections
                    }
                }
                .padding(24)
                .frame(maxWidth: 920, alignment: .leading)
                .frame(maxWidth: .infinity)
                .id("learningTop")
            }
            .scrollPosition($chapterScroll)
            .onScrollPhaseChange { _, phase, context in
                if phase == .idle && !sourceNeedsReview {
                    learning.setChapterScrollOffset(Double(max(0, context.geometry.contentOffset.y)))
                }
            }
            .onAppear {
                if let offset = learning.session?.chapter?.scrollOffset {
                    chapterScroll.scrollTo(y: offset)
                } else if learning.session?.chapter?.position == "reasoning" {
                    proxy.scrollTo("chapter-reasoning", anchor: .center)
                }
            }
            .onChange(of: learning.session?.phase) {
                showingPracticeHelp = false
                proxy.scrollTo("learningTop", anchor: .top)
                if document.notesVisible { learning.openedSource() }
                focusAnswerIfNeeded()
            }
            .onChange(of: learning.session?.currentLessonPartIndex) {
                proxy.scrollTo("learningTop", anchor: .top)
            }
            .onChange(of: answerEditRequest) {
                // Keep the question visible on arrival, but never leave the
                // learner typing into an editor below the visible viewport.
                if answerFocused, learning.session?.chapter == nil {
                    proxy.scrollTo("chapter-reasoning", anchor: .top)
                }
            }
            .onChange(of: learning.selectedSessionID) {
                if let offset = learning.session?.chapter?.scrollOffset {
                    chapterScroll.scrollTo(y: offset)
                } else if learning.session?.chapter?.position == "reasoning" {
                    proxy.scrollTo("chapter-reasoning", anchor: .center)
                } else { proxy.scrollTo("learningTop", anchor: .top) }
            }
        }
        .background { LearnAtmosphere(tint: lessonTint) }
        .safeAreaInset(edge: .bottom, spacing: 0) { actionBar }
        .animation(reduceMotion ? nil : .smooth(duration: 0.28), value: learning.session?.phase)
        .animation(reduceMotion ? nil : .smooth(duration: 0.28), value: learning.session?.currentLessonPartIndex)
        .animation(reduceMotion ? nil : .smooth(duration: 0.28), value: learning.session?.feedback != nil)
        .animation(reduceMotion ? nil : .smooth(duration: 0.28), value: showingPracticeHelp)
        .animation(reduceMotion ? nil : .smooth(duration: 0.28), value: startingQuestionsShown)
        .onAppear { assistantPreferenceRevision += 1; resetSource(); focusAnswerIfNeeded() }
        .onReceive(NotificationCenter.default.publisher(for: .assistantPreferencesChanged)) { _ in
            assistantPreferenceRevision += 1
        }
        .onChange(of: document.sourceRequestID) { resetSource() }
        .onChange(of: learning.selectedSessionID) {
            showingFullLesson = false
            showingCriteria = false
            showingPracticeHelp = false
            clarificationContext = nil
            if document.notesVisible { learning.openedSource() }
            focusAnswerIfNeeded()
        }
        .onChange(of: learning.session?.feedback == nil) {
            showingCriteria = false
            focusAnswerIfNeeded()
        }
        .sheet(isPresented: Binding(
            get: { learning.session?.chapter?.rescueVisible == true },
            set: { if !$0 { learning.returnToChapter() } }
        ), onDismiss: { focusAnswerIfNeeded() }) {
            if let session = learning.session, let chapter = session.chapter { prerequisiteRescue(session, chapter: chapter) }
        }
        .onChange(of: learning.session?.chapter?.rescueVisible) {
            if learning.session?.chapter?.rescueVisible == true { answerFocused = false }
        }
        .onChange(of: answerFocused) {
            if answerFocused && learning.session?.chapter?.rescueVisible == false { learning.setChapterPosition("reasoning") }
        }
        .sheet(isPresented: $showingFullLesson) {
            if let session = learning.session { fullLesson(session) }
        }
        .sheet(item: $clarificationContext, onDismiss: {
            focusAnswerIfNeeded()
            if returningToFeedback { feedbackActionFocused = true }
            else if learning.session?.phase == .lesson { clarificationActionFocused = true }
        }) { context in
            LearningClarificationView(document: document, context: context)
        }
    }

    private func errorContent(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: "exclamationmark.bubble")
                .font(.title2).foregroundStyle(.orange).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                Text("Couldn’t complete this step").font(.headline)
                Text(message).font(.callout).textSelection(.enabled)
                Text("Your notes and saved work are still here.")
                    .font(.caption).foregroundStyle(.secondary)
                if learning.session == nil {
                    Button("Learn from all your notes", action: onShowStudyMap).buttonStyle(.borderless)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .modifier(LearnSurface(tint: .orange, padding: 18))
    }

    private func changedSourceContent(page: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("This lesson’s source changed", systemImage: "doc.text.magnifyingglass").font(.headline)
            Text("Your saved lesson and answers are retained. Review the current notes on PDF page \(page + 1) before preparing new teaching or assessment.")
                .font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
        }
        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
    }

    private var sections: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Study a passage").font(.largeTitle.weight(.semibold))
                Text("Focus on a particular question or argument. To learn the whole document, use your learning path.")
                    .font(.body).foregroundStyle(.secondary)
                Button("Back to learning path", systemImage: "arrow.left", action: onShowStudyMap)
                    .buttonStyle(.borderless).disabled(learning.isBusy)
            }

            VStack(alignment: .leading, spacing: 12) {
                Text("Source").font(.headline)
                Button("Browse your notes", systemImage: "doc.text.magnifyingglass") { document.showNotes() }
                    .buttonStyle(.glass)
                Picker("Use text from", selection: $sourceMode) {
                    Text("Page \(document.sourcePageIndex + 1)").tag(SourceMode.currentPage)
                    if selectedPassage != nil {
                        Text("Selected passage").tag(SourceMode.selection)
                    }
                    Text("A page range").tag(SourceMode.pages)
                }
                .pickerStyle(.radioGroup)
                .labelsHidden()
                .disabled(learning.isBusy)

                if sourceMode == .selection, let selectedPassage {
                    Text(selectedPassage)
                        .font(.callout).foregroundStyle(.secondary)
                        .lineLimit(5).textSelection(.enabled)
                }
                if sourceMode == .pages {
                    HStack(alignment: .top, spacing: 12) {
                        pageField("From", text: $firstPage)
                        pageField("To", text: $lastPage)
                        Spacer(minLength: 0)
                    }
                    .disabled(learning.isBusy)
                    Text(pageRange == nil
                         ? "Enter a valid range of up to six pages (1–\(document.pageCount))."
                         : "PDF pages \(firstPage)–\(lastPage). Choose a range that contains one complete idea.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("How you’ll learn").font(.headline)
                Label("Explore the idea and a worked example.", systemImage: "book")
                Label("Practise with hints when you need them.", systemImage: "lightbulb")
                Label("Apply it to a different problem on your own.", systemImage: "pencil.and.outline")
            }
            .font(.callout).foregroundStyle(.secondary)

            if !assistantAvailable {
                Text(assistantPresentation.message ?? "Choose an assistant in Settings.")
                    .font(.callout).foregroundStyle(.secondary)
                SettingsLink { Text("Set up an assistant") }
            }

            DisclosureGroup("About tutor feedback") {
                Text("Your selected model creates the exercises and assesses your reasoning. Results describe performance on a problem. They don’t certify mastery or long-term retention.")
                    .font(.callout).foregroundStyle(.secondary).padding(.top, 8)
            }

        }
    }

    private func pageField(_ title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption)
            TextField(title, text: text)
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel("\(title) PDF page")
                .frame(width: 80)
        }
    }

    @ViewBuilder
    private func sessionContent(_ session: LearningSession) -> some View {
        if let review = session.delayedReview {
            VStack(alignment: .leading, spacing: 6) {
                Text("Delayed check · \(session.studyTarget?.kind.label ?? "Earlier requirement")").font(.headline)
                DisclosureGroup("Check details") {
                    Text("Started \(review.startedAt.formatted(date: .abbreviated, time: .shortened)), after a check due \(review.scheduledFor.formatted(date: .abbreviated, time: .shortened)). This is separate evidence on a fresh problem, not a guarantee of retention.")
                        .font(.caption).foregroundStyle(.secondary).padding(.top, 8)
                }
            }
        }
        lessonHeader(session)
        if document.selectedSourceReviewPage == nil, let error = learning.errorMessage { errorContent(error) }

        switch session.phase {
        case .lesson: lessonContent(session).modifier(LearnSurface(tint: lessonTint))
        case .diagnostic:
            if showsLessonIntroduction(session) { lessonIntroduction }
            else { questionContent(session) }
        case .practice, .exitCheck: questionContent(session)
        case .complete: evidenceContent(session).modifier(LearnSurface(tint: lessonTint))
        }
    }

    private func lessonHeader(_ session: LearningSession) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top, spacing: 18) {
                LearnEmblem(symbol: lessonStageSymbol(session), tint: lessonTint,
                            size: showsLessonIntroduction(session) ? 64 : 52)
                VStack(alignment: .leading, spacing: 8) {
                    Text(lessonStageTitle(session).uppercased())
                        .font(.system(size: 11, weight: .bold)).tracking(1.5)
                        .foregroundStyle(.secondary)
                        .contentTransition(.opacity)
                    Text(session.lesson.title)
                        .font(.system(showsLessonIntroduction(session) ? .largeTitle : .title, design: .rounded).weight(.semibold))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if showsLessonIntroduction(session) {
                MessageContentView(content: session.lesson.objective, font: .system(size: 15))
                lessonSourceAction(session)
            } else {
                HStack(alignment: .top, spacing: 16) {
                    DisclosureGroup("Learning goal") {
                        MessageContentView(content: session.lesson.objective)
                            .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 8)
                    }
                    lessonSourceAction(session).fixedSize()
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .modifier(LearnSurface(tint: lessonTint, emphasized: true,
                              padding: showsLessonIntroduction(session) ? 28 : 20))
    }

    @ViewBuilder private func lessonSourceAction(_ session: LearningSession) -> some View {
        if session.phase != .exitCheck {
            Button(session.source.label, systemImage: "doc.text") { openSource(session) }
                .buttonStyle(.glass).controlSize(.small)
                .help("Open the source page in your PDF")
                .disabled(learning.isBusy)
        }
    }

    private func showsLessonIntroduction(_ session: LearningSession) -> Bool {
        // Resuming work must reveal the original question, draft and help.
        session.phase == .diagnostic && session.chapter == nil && session.delayedReview == nil
            && session.answerDraft.isEmpty && session.feedback == nil && session.attempts.isEmpty
            && session.clarifications?.isEmpty != false
            && session.clarificationDrafts?.values.contains(where: { !$0.isEmpty }) != true
            && !startingQuestionsShown.contains(session.id)
    }

    private var lessonIntroduction: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Learn by working it out.").font(.title2.weight(.semibold))
            Text("Start with an explanation and a worked example. Then try it yourself, with hints whenever you need them.")
                .font(.body).foregroundStyle(.secondary)
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 24) { lessonPreview }
                VStack(alignment: .leading, spacing: 18) { lessonPreview }
            }
            Text("Already know some of this? Try the optional starting question first. It helps decide where to begin.")
                .font(.callout).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .modifier(LearnSurface(tint: lessonTint))
    }

    @ViewBuilder private var lessonPreview: some View {
        LearnPreviewItem(symbol: "book.pages", title: "Explore", detail: "An idea and an example", tint: .indigo)
        LearnPreviewItem(symbol: "pencil.and.outline", title: "Practise", detail: "Space to try, help nearby", tint: .teal)
        LearnPreviewItem(symbol: "sparkle.magnifyingglass", title: "Apply", detail: "A different problem", tint: .purple)
    }

    private func lessonStageTitle(_ session: LearningSession) -> String {
        switch session.phase {
        case .diagnostic: showsLessonIntroduction(session) ? "A new idea" : "Find your starting point"
        case .lesson: "Explore the idea"
        case .practice: "Guided practice"
        case .exitCheck: "Check your understanding"
        case .complete: "Your progress"
        }
    }

    private func lessonStageSymbol(_ session: LearningSession) -> String {
        switch session.phase {
        case .diagnostic: showsLessonIntroduction(session) ? "sparkle" : "questionmark.circle"
        case .lesson: "book"
        case .practice: "pencil.and.outline"
        case .exitCheck: "checkmark.circle"
        case .complete: "checkmark.seal"
        }
    }

    private func chapterContent(_ session: LearningSession, chapter: LearningChapterState) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Chapter challenge").font(.subheadline).foregroundStyle(.secondary)
            Text(chapter.challenge.title).font(.title.weight(.semibold))
                .lineLimit(2).accessibilityLabel(chapter.challenge.title)
            if chapterUsesEarlierPath && !sourceNeedsReview {
                VStack(alignment: .leading, spacing: 10) {
                    Label("Earlier learning path", systemImage: "clock.arrow.circlepath").font(.headline)
                    Text("This argument is saved with an earlier version of the chapter. You can review or finish it here. Prepare a current challenge from the learning path.")
                        .font(.callout).foregroundStyle(.secondary)
                    Button("Open current learning path", action: onShowStudyMap).buttonStyle(.glass)
                }
            }
            DisclosureGroup("Challenge details") {
                VStack(alignment: .leading, spacing: 10) {
                    Text(chapter.request.title).font(.headline).textSelection(.enabled)
                    Text(chapter.challenge.title).font(.headline).textSelection(.enabled)
                    MessageContentView(content: chapter.challenge.connection)
                }.frame(maxWidth: .infinity, alignment: .leading).padding(.top, 12)
                ForEach(chapter.challenge.ideas, id: \.unitID) { idea in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(idea.title).font(.headline)
                        Text(idea.sourceQuote).textSelection(.enabled)
                        Button("PDF page \(idea.pageIndex + 1)") { document.showNotes(at: idea.pageIndex) }
                            .buttonStyle(.borderless).disabled(learning.isBusy)
                    }.padding(.top, 12)
                }
            }
            if session.phase == .complete {
                evidenceContent(session)
                if !chapter.rescueAttempts.isEmpty {
                    DisclosureGroup("Prerequisite checks · \(chapter.rescueAttempts.count)") {
                        ForEach(chapter.rescueAttempts) { attempt in
                            VStack(alignment: .leading, spacing: 8) {
                                MessageContentView(content: attempt.question.prompt)
                                MessageContentView(content: attempt.answer)
                                MessageContentView(content: attempt.assessment.feedback)
                                Text("Supported practice · \(attempt.createdAt.formatted(date: .abbreviated, time: .shortened))")
                                    .font(.caption).foregroundStyle(.secondary)
                            }.padding(.top, 12)
                        }
                    }
                }
                Text("This records your work on this argument. Individual topic and proof checks stay open until separately supported; it does not establish chapter mastery.")
                    .font(.callout).foregroundStyle(.secondary)
                if chapter.hasUnsubmittedPrerequisiteDraft {
                    DisclosureGroup("Unsubmitted prerequisite draft") {
                        prerequisiteDraftContent(question: chapter.challenge.refresher.check.prompt, answer: chapter.rescueDraft)
                    }
                }
            } else {
                questionContent(session)
                if session.feedback == nil {
                    if let attempt = session.chapterRevisionAttempt {
                        chapterRevisionFeedback(attempt)
                    }
                    DisclosureGroup(session.assistanceUsed ? "Help with this argument · help recorded" : "Help with this argument") {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(session.assistanceUsed
                                 ? "This response records help. A fresh check can later provide independent evidence."
                                 : "Your argument stays here while you revisit a relevant idea. Using the refresher or reading a saved tutor reply records help on this response.")
                                .font(.caption).foregroundStyle(.secondary)
                            Button("Refresh a prerequisite", systemImage: "arrow.uturn.backward") {
                                answerFocused = false
                                learning.openPrerequisiteRescue()
                            }.buttonStyle(.glass).disabled(learning.isBusy || sourceNeedsReview)
                            if let exchanges = session.clarifications?.filter({ $0.context.attemptID != nil }), !exchanges.isEmpty {
                                DisclosureGroup("Saved feedback discussions (\(exchanges.count))") {
                                    ForEach(exchanges) { exchange in
                                        Button(exchange.question) { openClarification(exchange.context) }
                                            .buttonStyle(.borderless).disabled(learning.isBusy)
                                    }
                                }
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading).padding(.top, 10)
                    }
                }
            }
            if let drafts = chapter.prerequisiteDrafts, !drafts.isEmpty {
                DisclosureGroup("Earlier prerequisite drafts · \(drafts.count)") {
                    ForEach(drafts.reversed()) { draft in
                        DisclosureGroup {
                            Text("Saved \(draft.savedAt.formatted(date: .abbreviated, time: .shortened))")
                                .font(.caption).foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 12)
                            prerequisiteDraftContent(question: draft.refresher.check.prompt, answer: draft.answer)
                            DisclosureGroup("Original chapter question") {
                                MessageContentView(content: draft.chapterQuestion)
                                    .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 8)
                            }.padding(.top, 12)
                        } label: {
                            Text(draft.refresher.check.prompt).lineLimit(2)
                                .accessibilityLabel("Unsubmitted prerequisite draft: \(draft.refresher.check.prompt)")
                        }.padding(.top, 12)
                    }
                }
            }
        }.accessibilityElement(children: .contain)
    }

    private func prerequisiteDraftContent(question: String, answer: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Not submitted · no assessment").font(.caption).foregroundStyle(.secondary)
            MessageContentView(content: question)
            Text("Your draft").font(.headline)
            MessageContentView(content: answer)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(.top, 12)
    }

    private func prerequisiteRescue(_ session: LearningSession, chapter: LearningChapterState) -> some View {
        let refresher = chapter.challenge.refresher
        return VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("A prerequisite for your argument").font(.headline)
                Spacer()
                Button("Return to my argument") { learning.returnToChapter() }
                    .keyboardShortcut(.cancelAction)
            }.padding(24)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text(chapter.challenge.ideas.first(where: { $0.unitID == refresher.unitID })?.title ?? "Prerequisite")
                        .font(.title2.weight(.semibold))
                    MessageContentView(content: refresher.explanation)
                    DisclosureGroup("From your notes · PDF page \(refresher.pageIndex + 1)") {
                        Text(refresher.sourceQuote).textSelection(.enabled).padding(.top, 8)
                        Button("Review source") {
                            learning.returnToChapter()
                            document.showNotes(at: refresher.pageIndex)
                        }.buttonStyle(.borderless)
                    }
                    if sourceNeedsReview {
                        Text("This saved refresher uses earlier source text. Return to your argument to review the current notes.")
                            .font(.callout).foregroundStyle(.secondary)
                    } else if let message = learning.errorMessage {
                        Label(message, systemImage: "exclamationmark.circle").font(.callout).textSelection(.enabled)
                    }
                    Text("Quick check").font(.headline)
                    MessageContentView(content: refresher.check.prompt)
                    if sourceNeedsReview {
                        MessageContentView(content: chapter.rescueDraft.isEmpty ? "No refresher answer was saved." : chapter.rescueDraft)
                    } else {
                        TextEditor(text: Binding(get: { learning.rescueDraft }, set: { learning.rescueDraft = $0 }))
                            .font(.body).frame(minHeight: 120).padding(8)
                            .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color(nsColor: .separatorColor)))
                            .accessibilityLabel("Prerequisite reasoning")
                            .disabled(learning.isBusy || chapter.rescueFeedback != nil)
                    }
                    if let feedback = chapter.rescueFeedback {
                        Label(feedback.grade.label, systemImage: "text.bubble").font(.headline)
                        MessageContentView(content: feedback.feedback)
                        MessageContentView(content: feedback.nextStep)
                    }
                    Text("This supported check does not earn an independent result or complete a topic. Your original question and draft are saved.")
                        .font(.caption).foregroundStyle(.secondary)
                }.padding(24)
            }
            Divider()
            HStack {
                if learning.isBusy {
                    ProgressView().controlSize(.small)
                    Text("Checking the prerequisite…").font(.callout)
                    Spacer()
                    Button("Cancel check") { learning.cancel() }
                } else if sourceNeedsReview {
                    primaryAction("Return to my argument") { learning.returnToChapter() }
                } else if chapter.rescueFeedback == nil {
                    primaryAction("Check this step") { learning.submitAnswer() }
                        .disabled(chapter.rescueDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    Spacer()
                    Button("Return to my argument") { learning.returnToChapter() }
                } else {
                    primaryAction("Return to my argument") { learning.returnToChapter() }
                }
            }.padding(24)
        }.frame(minWidth: 560, idealWidth: 650, minHeight: 480, idealHeight: 650)
    }

    private func lessonContent(_ session: LearningSession) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Menu {
                    ForEach(Array(session.lesson.parts.enumerated()), id: \.offset) { index, part in
                        Button {
                            learning.selectLessonPart(index)
                        } label: {
                            if index == session.currentLessonPartIndex {
                                Label(part.label, systemImage: "checkmark")
                            } else { Text(part.label) }
                        }
                    }
                } label: {
                    Text("Part \(session.currentLessonPartIndex + 1) of \(session.lesson.parts.count)")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .accessibilityLabel("Choose a lesson part")
                Spacer()
                Button(session.lesson.proof == nil ? "Read full lesson" : "Read full proof") {
                    showingFullLesson = true
                }.buttonStyle(.borderless)
            }
            Text(session.currentLessonPart.label).font(.title2.weight(.semibold))
            switch session.currentLessonPart {
            case .idea:
                MessageContentView(content: session.lesson.explanation)
            case .proofOverview:
                if let proof = session.lesson.proof { proofOverview(proof) }
            case .proofStep(let index):
                if let proof = session.lesson.proof, proof.steps.indices.contains(index) {
                    proofStep(proof, at: index)
                }
            case .proofConclusion:
                if let proof = session.lesson.proof {
                    MessageContentView(content: proof.conclusion)
                    Button("Read the argument together") { showingFullLesson = true }
                        .buttonStyle(.borderless)
                }
            case .example:
                MessageContentView(content: session.lesson.workedExample)
            }
            clarificationAction(session)
            DisclosureGroup("From your notes") {
                Text(session.lesson.sourceQuote)
                    .font(.body).textSelection(.enabled).padding(.top, 8)
                ForEach(session.source.passages.compactMap(\.correction)) { correction in
                    Text("PDF page \(correction.pageIndex + 1) uses your verified transcription from \(correction.createdAt.formatted(date: .abbreviated, time: .shortened)). This is separate from original PDF text and assistant output.")
                        .font(.caption).foregroundStyle(.secondary)
                    Text(correction.note).font(.caption).textSelection(.enabled)
                }
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func proofOverview(_ proof: LearningProof) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("The statement").font(.headline)
            MessageContentView(content: proof.statement)
            Text("Assumptions").font(.headline)
            ForEach(Array(proof.assumptions.enumerated()), id: \.offset) { _, assumption in
                MessageContentView(content: assumption)
            }
            Text("Why this approach works").font(.headline)
            MessageContentView(content: proof.strategy)
        }.accessibilityElement(children: .contain)
    }

    private func proofStep(_ proof: LearningProof, at index: Int) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            if index > 0 {
                DisclosureGroup("Previous step · \(index)") {
                    MessageContentView(content: proof.steps[index - 1].claim).padding(.top, 8)
                    MessageContentView(content: proof.steps[index - 1].justification)
                }
            }
            MessageContentView(content: proof.steps[index].claim)
            Text("Why this follows").font(.headline)
            MessageContentView(content: proof.steps[index].justification)
            DisclosureGroup("Statement and approach") { proofOverview(proof).padding(.top, 8) }
        }.accessibilityElement(children: .contain)
    }

    private func fullLesson(_ session: LearningSession) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text(session.lesson.proof == nil ? "Complete lesson" : "Complete proof").font(.headline)
                Spacer()
                Button("Done") { showingFullLesson = false }.keyboardShortcut(.cancelAction)
            }.padding(20)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Text(session.lesson.title).font(.title.weight(.semibold))
                    if let proof = session.lesson.proof {
                        proofContent(proof)
                        DisclosureGroup("Additional explanation") {
                            MessageContentView(content: session.lesson.explanation).padding(.top, 8)
                        }
                    } else { MessageContentView(content: session.lesson.explanation) }
                    Text("Worked example").font(.headline)
                    MessageContentView(content: session.lesson.workedExample)
                }
                .accessibilityElement(children: .contain)
                .padding(24).frame(maxWidth: 760, alignment: .leading).frame(maxWidth: .infinity)
            }
        }.frame(minWidth: 620, idealWidth: 760, minHeight: 480, idealHeight: 680)
    }

    private func proofContent(_ proof: LearningProof) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("The statement").font(.headline)
            MessageContentView(content: proof.statement)
            Text("Assumptions").font(.headline)
            ForEach(Array(proof.assumptions.enumerated()), id: \.offset) { _, assumption in
                MessageContentView(content: assumption)
            }
            Text("Why this approach works").font(.headline)
            MessageContentView(content: proof.strategy)
            Text("The argument, step by step").font(.headline)
            ForEach(Array(proof.steps.enumerated()), id: \.offset) { index, step in
                VStack(alignment: .leading, spacing: 8) {
                    Text("Step \(index + 1)").font(.subheadline.weight(.semibold))
                    MessageContentView(content: step.claim)
                    MessageContentView(content: step.justification)
                }
                .accessibilityElement(children: .contain)
            }
            Text("What we have proved").font(.headline)
            MessageContentView(content: proof.conclusion)
        }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private func questionContent(_ session: LearningSession) -> some View {
        if let question = session.question {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 16) {
                    Label {
                        Text(session.phase == .practice ? "Try it yourself" : "Your question")
                    } icon: {
                        Image(systemName: "text.bubble").foregroundStyle(lessonTint)
                    }
                    .font(.subheadline.weight(.semibold))
                    if session.phase == .diagnostic && session.feedback == nil {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("A question before we begin").font(.title2.weight(.semibold))
                            Text("Try the question below and explain your thinking. It’s okay to be unsure — this helps choose your starting point. You can also go straight to the explanation.")
                                .font(.callout).foregroundStyle(.secondary)
                        }
                    }
                    MessageContentView(content: question.prompt, font: .system(size: 15))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .modifier(LearnSurface(tint: lessonTint))

                VStack(alignment: .leading, spacing: 14) {
                    Label("Your reasoning", systemImage: "pencil.line")
                        .font(.headline).id("chapter-reasoning")
                    if sourceNeedsReview {
                        MessageContentView(content: session.answerDraft.isEmpty ? "No answer draft was saved." : session.answerDraft)
                    } else {
                        TextEditor(text: Binding(get: { learning.answerDraft }, set: {
                            guard $0 != learning.answerDraft else { return }
                            learning.answerDraft = $0
                            answerEditRequest += 1
                        }))
                            .font(.system(size: 15))
                            .scrollContentBackground(.hidden)
                            .frame(minHeight: 112, maxHeight: 200)
                            .overlay(alignment: .topLeading) {
                                if session.answerDraft.isEmpty {
                                    Text("Start with what you know, then explain each step…")
                                        .font(.body).foregroundStyle(.secondary)
                                        .padding(.horizontal, 5).padding(.vertical, 8)
                                        .allowsHitTesting(false).accessibilityHidden(true)
                                }
                            }
                            .focused($answerFocused)
                            .accessibilityLabel("Your answer and reasoning")
                            .disabled(learning.isBusy || session.feedback != nil)
                    }
                    if session.answerDraft.count >= 10_000 {
                        Text("\(session.answerDraft.count.formatted()) / 12,000 characters")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .modifier(LearnSurface(tint: lessonTint))
                .overlay {
                    RoundedRectangle(cornerRadius: 24)
                        .strokeBorder(lessonTint.opacity(answerFocused ? 0.65 : 0), lineWidth: 1.5)
                        .allowsHitTesting(false)
                }
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: answerFocused)

                if let feedback = session.feedback {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("\(feedback.grade == .correct && !session.feedbackSupportsProgress ? "Saved tutor grade" : "Tutor feedback") · \(feedback.grade.label)",
                              systemImage: feedback.grade == .correct && session.feedbackSupportsProgress ? "checkmark.circle" : "text.bubble")
                            .font(.headline)
                        if feedback.grade == .correct && !session.feedbackSupportsProgress && session.feedbackAttempt?.setAsideAt == nil {
                            Text("This saved grade and its reasoning checks need checking. Your original answer and feedback are retained.")
                                .font(.callout).foregroundStyle(.secondary)
                        }
                        MessageContentView(content: feedback.feedback)
                        Text("Next step").font(.subheadline)
                        MessageContentView(content: feedback.nextStep)
                        if let criteria = feedback.criteria, let rubric = question.gradingCriteria {
                            DisclosureGroup("Reasoning checks · \(criteria.filter { $0.outcome == .met }.count) of \(rubric.count) met", isExpanded: $showingCriteria) {
                                ForEach(criteria, id: \.index) { criterion in
                                    if rubric.indices.contains(criterion.index) {
                                        VStack(alignment: .leading, spacing: 6) {
                                            Label(rubric[criterion.index], systemImage: criterion.outcome == .met ? "checkmark.circle" : "questionmark.circle")
                                                .font(.subheadline)
                                            if let chapter = session.chapter,
                                               let mapping = chapter.challenge.criteria.first(where: { $0.index == criterion.index }) {
                                                Text(mapping.unitIDs.compactMap { id in chapter.challenge.ideas.first { $0.unitID == id }?.title }.joined(separator: " + "))
                                                    .font(.caption).foregroundStyle(.secondary)
                                            }
                                            MessageContentView(content: criterion.feedback)
                                        }.padding(.top, 10)
                                    }
                                }
                            }
                        }
                        feedbackClarificationAction(session)
                        if let attempt = session.feedbackAttempt {
                            chapterRevisionAction(session, attempt: attempt)
                            LearningAssessmentReviewControl(learning: learning, sessionID: session.id, attempt: attempt)
                        }
                    }
                    .modifier(LearnSurface(tint: lessonTint))
                    .transition(.opacity.combined(with: .offset(y: reduceMotion ? 0 : 8)))
                }

                if session.phase == .practice {
                    practiceHelp(session, question: question)
                        .padding(16)
                        .background(lessonTint.opacity(0.07), in: RoundedRectangle(cornerRadius: 16))
                }
                else { clarificationAction(session) }
            }
        }
    }

    private func practiceHelp(_ session: LearningSession, question: LearningQuestion) -> some View {
        DisclosureGroup(isExpanded: $showingPracticeHelp) {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(Array(question.hints.prefix(session.hintsRevealed).enumerated()), id: \.offset) { index, hint in
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Hint \(index + 1)").font(.subheadline).foregroundStyle(.secondary)
                        MessageContentView(content: hint)
                    }
                }
                if session.hintsRevealed < question.hints.count && session.feedback == nil {
                    Button("Give me a hint", systemImage: "lightbulb") { learning.revealHint() }
                        .disabled(learning.isBusy || sourceNeedsReview)
                }
                if session.solutionRevealed {
                    Text("Tutor’s worked solution").font(.headline)
                    MessageContentView(content: question.expectedAnswer)
                } else if session.feedback != nil {
                    Button("Show worked solution") { learning.revealSolution() }
                        .disabled(learning.isBusy || sourceNeedsReview)
                }
                clarificationAction(session)
            }
            .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 12)
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text("Help with this question")
                if session.solutionRevealed {
                    Text("Worked solution viewed").font(.caption).foregroundStyle(.secondary)
                } else if session.clarificationHelpUsed == true {
                    Text("Tutor reply viewed").font(.caption).foregroundStyle(.secondary)
                } else if session.hintsRevealed > 0 {
                    Text("\(session.hintsRevealed) \(session.hintsRevealed == 1 ? "hint" : "hints") used")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func evidenceContent(_ session: LearningSession) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            Label(session.progressLabel, systemImage: session.passedExitCheck ? "checkmark.circle" : "text.bubble")
                .font(.headline)
            Text(resultExplanation(session)).font(.body).foregroundStyle(.secondary)
            if let exchanges = session.clarifications, !exchanges.isEmpty {
                DisclosureGroup("Saved explanations (\(exchanges.count))") {
                    ForEach(exchanges) { exchange in
                        Button(exchange.question) { openClarification(exchange.context) }
                            .buttonStyle(.borderless).padding(.top, 8)
                    }
                }
            }
            if let attempt = session.latestExitAttempt {
                Text("Your latest check").font(.headline)
                MessageContentView(content: attempt.question.prompt)
                MessageContentView(content: attempt.assessment.feedback)
                feedbackClarificationAction(session)
                chapterRevisionAction(session, attempt: attempt)
                LearningAssessmentReviewControl(learning: learning, sessionID: session.id, attempt: attempt)
                Text(attempt.assistanceUsed ? "Help was used on this answer." : "No help was reported or requested in this check.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            DisclosureGroup("Answers and feedback (\(session.attempts.count))") {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(session.attempts) { attempt in
                        DisclosureGroup("\(attempt.phase.label) · \(attempt.setAsideAt == nil ? attempt.assessment.grade.label : "Set aside by you · recorded " + attempt.assessment.grade.label)") {
                            VStack(alignment: .leading, spacing: 10) {
                                MessageContentView(content: attempt.question.prompt)
                                Text("Your answer").font(.subheadline)
                                MessageContentView(content: attempt.answer)
                                MessageContentView(content: attempt.assessment.feedback)
                                LearningAssessmentReviewControl(learning: learning, sessionID: session.id, attempt: attempt)
                                Text("\(attempt.assistanceUsed ? "Help used" : "No help reported") · \(attempt.createdAt.formatted(date: .abbreviated, time: .shortened))")
                                    .font(.caption).foregroundStyle(.secondary)
                                Text("Tutor: \(attempt.providerID)\(attempt.modelID.map { " / \($0)" } ?? "")")
                                    .font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                            }
                            .padding(.top, 8)
                        }
                    }
                }
                .padding(.top, 8)
            }
        }
    }

    private func resultExplanation(_ session: LearningSession) -> String {
        guard let attempt = session.latestExitAttempt else { return "There isn’t an exit result for this section yet." }
        if attempt.setAsideAt != nil {
            return "You set aside this assessment. Your answer and the original tutor feedback are saved, and this result does not count toward progress. Review the reasoning before deciding whether to use the recorded result again."
        }
        if attempt.assessment.grade == .correct, !attempt.assessmentCriteriaSatisfied {
            return attempt.question.kind == .proof
                ? "This proof assessment is incomplete. It does not establish that the essential steps were justified; the proof check remains open."
                : "The saved grade and reasoning checks do not establish a complete assessment. Your answer and feedback are retained; this requirement remains open."
        }
        switch attempt.assessment.grade {
        case .correct where attempt.assistanceUsed:
            return "You reached a correct answer with help. Review the idea, then try a different problem without support."
        case .correct:
            if session.delayedReview != nil {
                return "You answered a fresh question correctly after a delay without recorded help. This is evidence for this requirement on one delayed problem; it does not establish lasting retention or whole-subject mastery."
            }
            return "You applied this idea correctly on one problem. Come back later and try a fresh check to find out what you retain."
        case .uncertain:
            return "The tutor couldn’t reliably assess this answer. That isn’t evidence that your reasoning is wrong. Compare it with your notes and review what needs checking."
        case .partial, .incorrect:
            return "There’s a specific gap to work on. Use the feedback below, review the idea, and practise before trying a different problem."
        }
    }

    private var actionBar: some View {
        VStack(alignment: .leading, spacing: 0) {
            Group {
                if let operation = learning.operation {
                    HStack(spacing: 10) {
                        ProgressView().controlSize(.small)
                        Text(operation.label).font(.callout)
                        Spacer(minLength: 0)
                        Button("Cancel") { learning.cancel() }
                            .keyboardShortcut(.cancelAction)
                    }
                } else if let page = document.selectedSourceReviewPage {
                    VStack(alignment: .leading, spacing: 10) {
                        primaryAction("Review current source") { document.showNotes(at: page) }
                        Button("Back to learning path", action: onShowStudyMap).buttonStyle(.borderless)
                    }
                } else if let session = learning.session {
                    sessionActions(session)
                } else {
                    primaryAction("Start learning") { startLearning() }.disabled(!canStart)
                }
            }
            .controlSize(.large)
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 24))
        }
        .padding(.horizontal, 24).padding(.vertical, 12)
        .frame(maxWidth: 920)
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func sessionActions(_ session: LearningSession) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if session.chapter != nil && session.phase == .complete {
                if chapterUsesEarlierPath {
                    primaryAction("Open current learning path", action: onShowStudyMap)
                } else if session.passedExitCheck {
                    primaryAction("Continue learning", action: onShowStudyMap)
                    Button("Try a fresh challenge") { learning.freshChapterCheck() }
                } else {
                    primaryAction("Try a fresh challenge") { learning.freshChapterCheck() }
                    Button("Continue learning", action: onShowStudyMap)
                }
            } else {
            switch session.phase {
            case .lesson:
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 16) {
                        lessonStepActions(session)
                        Spacer(minLength: 16)
                        if session.currentLessonPart != .example { goToPractice }
                    }
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 16) { lessonStepActions(session) }
                        if session.currentLessonPart != .example { goToPractice }
                    }
                }
            case .diagnostic, .practice, .exitCheck:
                if showsLessonIntroduction(session) {
                    primaryAction("Start with the explanation") { learning.studyInstead() }
                    Button("Try a question first") {
                        startingQuestionsShown.insert(session.id)
                        focusAnswerIfNeeded()
                    }.buttonStyle(.borderless)
                } else if session.feedback == nil {
                    if session.phase == .exitCheck {
                        if document.notesVisible {
                            Text("Your source notes are open. This check will record that help was available.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        // Keep this beside submission, even when a long problem scrolls.
                        Toggle("I used notes or other help", isOn: Binding(
                            get: { learning.outsideHelpUsed }, set: { learning.outsideHelpUsed = $0 }
                        ))
                        .toggleStyle(.checkbox)
                        .help("Try without notes or hints, and record any help used for this response.")
                    }
                    primaryAction(learning.errorMessage == nil ? "Check my reasoning" : "Try checking again") {
                        answerFocused = false; learning.submitAnswer()
                    }
                        .disabled(session.answerDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    if session.phase == .diagnostic {
                        Button("Go straight to the explanation") { learning.studyInstead() }
                    }
                } else if session.phase == .practice && !session.feedbackSupportsProgress {
                    primaryAction("Revise my answer") { learning.tryAgain() }
                    Button("Review the idea") { learning.reviewIdea() }
                } else {
                    primaryAction(advanceLabel(session)) { learning.advance() }
                }
            case .complete:
                if let run = document.selectedStudyRun {
                    if document.canAdvanceStudyRun {
                        primaryAction(run.currentIndex == run.items.count - 1 ? "Finish study session" : "Next in session") {
                            if document.advanceStudyRun(), document.studyMap.currentStudyRun?.state == .finished {
                                onShowStudyMap()
                            }
                        }
                        Button("Review and practise again") { learning.practiseAgain() }
                    } else {
                        primaryAction("Review and practise again") { learning.practiseAgain() }
                        Button("Finish session here") { document.finishStudyRun(); onShowStudyMap() }
                    }
                } else if session.passedExitCheck {
                    if session.studyTarget != nil {
                        primaryAction("Continue learning", action: onShowStudyMap)
                    } else {
                        primaryAction("Learn another section") { learning.showSections() }
                    }
                    Button("Review and practise again") { learning.practiseAgain() }
                } else {
                    primaryAction("Review and practise again") { learning.practiseAgain() }
                    if session.studyTarget != nil {
                        Button("Back to learning path", action: onShowStudyMap)
                    } else {
                        Button("Learn another section") { learning.showSections() }
                    }
                }
            }
            }
        }
    }

    @ViewBuilder private func lessonStepActions(_ session: LearningSession) -> some View {
        if session.currentLessonPartIndex > 0 {
            Button("Back", systemImage: "chevron.left") {
                learning.selectLessonPart(session.currentLessonPartIndex - 1)
            }.buttonStyle(.glass).fixedSize()
        }
        primaryAction(session.currentLessonPart == .example ? "Practise this idea" : "Continue") {
            learning.continueLesson()
        }.fixedSize()
    }

    private var goToPractice: some View {
        Button("Go to practice") { learning.advance() }.buttonStyle(.borderless).fixedSize()
    }

    private func primaryAction(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(.glassProminent)
            .keyboardShortcut(.return, modifiers: .command)
            .help("\(title) (⌘Return)")
    }

    private func advanceLabel(_ session: LearningSession) -> String {
        switch session.phase {
        case .diagnostic: session.feedbackSupportsProgress ? "Try the exit check" : "Study the idea"
        case .practice: "Try the exit check"
        case .exitCheck: "See your result"
        default: "Continue"
        }
    }

    private func resetSource() {
        firstPage = String(max(1, (document.sourcePageIndex + 1)))
        lastPage = firstPage
        sourceMode = selectedPassage == nil ? .currentPage : .selection
    }

    private func focusAnswerIfNeeded() {
        answerFocused = learning.session?.question != nil && learning.session?.feedback == nil && !learning.isBusy
            && learning.session?.chapter?.rescueVisible != true && clarificationContext == nil && !sourceNeedsReview
            && learning.session.map { !showsLessonIntroduction($0) } == true
    }

    @ViewBuilder private func clarificationAction(_ session: LearningSession) -> some View {
        if let context = session.clarificationContext,
           session.feedback == nil || hasSavedClarification(for: context) {
            Button(session.clarificationHelpUsed == true ? "Review tutor help"
                   : context.phase == .lesson ? "Ask about this step" : "Ask about this question", systemImage: "bubble.left") {
                openClarification(context)
            }
            .buttonStyle(.borderless).focusable().focused($clarificationActionFocused)
            .onKeyPress(keys: [.space, .return], phases: .down) { key in
                guard key.modifiers.isEmpty else { return .ignored }
                openClarification(context)
                return .handled
            }
            .disabled(learning.isBusy || ((sourceNeedsReview || !assistantAvailable) && !hasSavedClarification(for: context)))
        }
    }

    private func hasSavedClarification(for context: LearningClarificationContext) -> Bool {
        (learning.session?.clarifications ?? []).contains { $0.context.id == context.id }
            || !learning.clarificationDraft(for: context).isEmpty
    }

    private func openClarification(_ context: LearningClarificationContext) {
        guard !learning.isBusy else { return }
        answerFocused = false
        clarificationActionFocused = false
        feedbackActionFocused = false
        returningToFeedback = context.attemptID != nil && (learning.session?.phase == .complete || learning.session?.feedback != nil)
        learning.openedClarifications(for: context)
        clarificationContext = context
    }

    @ViewBuilder private func chapterRevisionAction(_ session: LearningSession, attempt: LearningAttempt) -> some View {
        if session.chapter != nil && !chapterUsesEarlierPath {
            Button("Revise this argument", systemImage: "pencil") {
                learning.reviseChapterArgument(sessionID: session.id, attemptID: attempt.id)
                focusAnswerIfNeeded()
            }
            .buttonStyle(.borderless).disabled(learning.isBusy || sourceNeedsReview)
            .help("Keep the same question and revise your saved answer. Feedback is recorded as help; a fresh challenge can provide independent evidence.")
        }
    }

    private func chapterRevisionFeedback(_ attempt: LearningAttempt) -> some View {
        DisclosureGroup("Feedback for this revision") {
            VStack(alignment: .leading, spacing: 10) {
                Text("Recorded tutor grade: \(attempt.assessment.grade.label)").font(.subheadline)
                if attempt.setAsideAt != nil {
                    Text("You set this assessment aside. Its original feedback is retained.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                MessageContentView(content: attempt.assessment.feedback)
                Text("Next step").font(.subheadline)
                MessageContentView(content: attempt.assessment.nextStep)
                if let criteria = attempt.assessment.criteria, let rubric = attempt.question.gradingCriteria {
                    DisclosureGroup("Reasoning checks") {
                        ForEach(criteria, id: \.index) { criterion in
                            if rubric.indices.contains(criterion.index) {
                                VStack(alignment: .leading, spacing: 6) {
                                    Label(rubric[criterion.index], systemImage: criterion.outcome == .met ? "checkmark.circle" : "questionmark.circle")
                                        .font(.subheadline)
                                    Text(criterion.outcome == .met ? "Met" : criterion.outcome == .notMet ? "Not yet met" : "Needs checking")
                                        .font(.caption).foregroundStyle(.secondary)
                                    MessageContentView(content: criterion.feedback)
                                }.frame(maxWidth: .infinity, alignment: .leading).padding(.top, 8)
                            }
                        }
                    }
                }
                DisclosureGroup("Your earlier answer") {
                    MessageContentView(content: attempt.answer)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 8)
                }
            }.frame(maxWidth: .infinity, alignment: .leading).padding(.top, 8)
        }
    }

    @ViewBuilder private func feedbackClarificationAction(_ session: LearningSession) -> some View {
        if let context = session.feedbackClarificationContext {
            Button("Ask about this feedback", systemImage: "bubble.left") { openClarification(context) }
                .buttonStyle(.borderless).focusable().focused($feedbackActionFocused)
                .onKeyPress(keys: [.space, .return], phases: .down) { key in
                    guard key.modifiers.isEmpty else { return .ignored }
                    openClarification(context)
                    return .handled
                }
                .disabled(learning.isBusy || ((sourceNeedsReview || !assistantAvailable) && !hasSavedClarification(for: context)))
        }
    }

    private func startLearning() {
        let pdf = document.pdfDocument
        do {
            let source: LearningSource
            switch sourceMode {
            case .currentPage:
                source = try LearningSourceBuilder.pages((document.sourcePageIndex + 1)...(document.sourcePageIndex + 1), in: pdf, map: document.studyMap.map)
            case .selection:
                guard let passage = document.selectedPassage else { return }
                source = try LearningSourceBuilder.selection(passage.text, pageIndex: passage.pageIndex, in: pdf)
            case .pages:
                let range = try LearningSourceBuilder.pageRange(first: firstPage, last: lastPage, pageCount: pdf.pageCount)
                source = try LearningSourceBuilder.pages(range, in: pdf, map: document.studyMap.map)
            }
            learning.start(source: source)
        } catch { learning.errorMessage = error.localizedDescription }
    }

    private func openSource(_ session: LearningSession) {
        document.showNotes(at: session.source.passages.first?.pageIndex)
    }
}

/// Solid reading surfaces keep the lesson distinct from its glass controls.
private struct LearnSurface: ViewModifier {
    var tint: Color
    var emphasized = false
    var padding: CGFloat = 24
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: 24)
        content
            .padding(padding)
            .background {
                shape.fill(Color(nsColor: .windowBackgroundColor))
                shape.fill(Color.primary.opacity(scheme == .dark ? 0.045 : 0.015))
                if !reduceTransparency {
                    shape.fill(LinearGradient(
                        colors: [tint.opacity(emphasized ? 0.18 : 0.045), tint.opacity(0.015)],
                        startPoint: .topLeading, endPoint: .bottomTrailing))
                }
            }
            .overlay {
                shape.strokeBorder(Color.primary.opacity(contrast == .increased ? 0.3 : 0.09))
                    .allowsHitTesting(false)
            }
            .shadow(color: .black.opacity(scheme == .dark ? 0.12 : 0.04), radius: 16, y: 6)
    }
}

private struct LearnAtmosphere: View {
    var tint: Color
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)
            if !reduceTransparency && contrast != .increased {
                RadialGradient(colors: [tint.opacity(0.13), .clear],
                               center: .topLeading, startRadius: 0, endRadius: 650)
                RadialGradient(colors: [Color.teal.opacity(0.07), .clear],
                               center: .bottomTrailing, startRadius: 0, endRadius: 500)
            }
        }
        .allowsHitTesting(false).accessibilityHidden(true)
    }
}

private struct LearnEmblem: View {
    var symbol: String
    var tint: Color
    var size: CGFloat = 64

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.4, weight: .medium))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(tint.gradient, in: RoundedRectangle(cornerRadius: size / 3))
            .overlay {
                RoundedRectangle(cornerRadius: size / 3).strokeBorder(.white.opacity(0.25))
            }
            .shadow(color: tint.opacity(0.2), radius: 12, y: 5)
            .accessibilityHidden(true)
    }
}

private struct LearnPreviewItem: View {
    var symbol: String
    var title: String
    var detail: String
    var tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: symbol).font(.title2).foregroundStyle(tint).accessibilityHidden(true)
            Text(title).font(.headline)
            Text(detail).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
