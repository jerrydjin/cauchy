import SwiftUI

struct LearningStudyMapView: View {
    @Bindable var document: LearningDocument
    var onStudyPassage: () -> Void = {}
    var onPlanStudySession: () -> Void = {}
    @State private var assistantPreferenceRevision = 0
    private var assistantPresentation: AskPresentation {
        _ = assistantPreferenceRevision
        return AskPresentation.current()
    }
    private var assistantAvailable: Bool { document.isVerificationFixture || assistantPresentation.canAsk }
    @State private var expandedUnitID: UUID?
    @State private var localOCR: [Int: String] = [:]
    @State private var recognizingPage: Int?
    @State private var chaptersExpanded = false
    @State private var chapterNavigationRequest = 0
    @State private var reviewClock = Date()
    @State private var syllabusText = ""
    @State private var syllabusProvenance = ""
    @State private var syllabusKinds: Set<LearningStudyKind> = [.concept, .proof, .application]
    @State private var syllabusMapping: LearningSyllabusSelection?
    @State private var historyTarget: LearningStudyTarget?
    @State private var goalSelection: LearningGoalSelection?
    @State private var goalHistoryVisible = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var planner: LearningStudyMapViewModel { document.studyMap }
    private var nextStudy: LearningStudyRecommendation? {
        guard planner.map?.course != nil else { return nil }
        return planner.map?.nextStudy(sessions: document.learning.sessions)
    }
    private var visibleStudyRun: LearningStudyRun? {
        guard let run = planner.currentStudyRun, run.state != .finished || run.summaryAcknowledgedAt == nil else { return nil }
        return run
    }

    var body: some View {
        Group {
            if let map = planner.map, let course = map.course {
                courseContent(course, map: map)
            } else if let map = planner.map, let run = visibleStudyRun {
                ScrollView {
                    VStack(alignment: .leading, spacing: 28) {
                        Text(document.title.replacingOccurrences(of: "_", with: " ")).font(.largeTitle.weight(.semibold))
                        errors
                        LearningStudyRunCard(document: document, run: run, map: map, assistantAvailable: assistantAvailable)
                        goalHistoryButton(map)
                    }
                    .padding(32).frame(maxWidth: 824, alignment: .leading).frame(maxWidth: .infinity)
                }
            } else {
                preparation
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if document.isBusy, planner.map?.course != nil || visibleStudyRun != nil { actionBar }
        }
        .onReceive(NotificationCenter.default.publisher(for: .assistantPreferencesChanged)) { _ in
            assistantPreferenceRevision += 1
        }
        .onReceive(Timer.publish(every: 60, on: .main, in: .common).autoconnect()) { reviewClock = $0 }
        .onAppear { reviewClock = Date() }
        .sheet(item: $syllabusMapping) { selection in
            LearningSyllabusMappingEditor(document: document, requirement: selection.requirement, kind: selection.kind)
        }
        .sheet(item: $historyTarget) { target in
            LearningRequirementHistoryView(document: document, target: target)
        }
        .sheet(item: $goalSelection) { selection in
            LearningGoalEditor(document: document, unit: selection.unit, target: selection.target)
        }
        .sheet(isPresented: $goalHistoryVisible) {
            LearningGoalHistoryView(document: document)
        }
    }

    private var preparation: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 22) {
                    preparationArtwork
                    VStack(spacing: 8) {
                        Text(preparationTitle).font(.largeTitle.weight(.semibold))
                        Text(document.title.replacingOccurrences(of: "_", with: " "))
                            .font(.callout).foregroundStyle(.secondary).lineLimit(2)
                        if planner.map == nil {
                            Text("All \(document.pageCount) pages. Proofs, ideas and practice.")
                                .font(.body).foregroundStyle(.secondary)
                        }
                    }
                    if let map = planner.map {
                        VStack(spacing: 10) {
                            if planner.isConnectingTopics {
                                ProgressView().controlSize(.small)
                                Text("Shaping your learning path").font(.callout).foregroundStyle(.secondary)
                            } else {
                                ProgressView(value: Double(map.resolvedPageCount), total: Double(max(1, map.pages.count)))
                                    .tint(.accentColor)
                                Text("\(map.resolvedPageCount) of \(map.pages.count) pages ready")
                                    .font(.callout.monospacedDigit()).foregroundStyle(.secondary)
                            }
                            if planner.isBusy, let topic = planner.recentTopicTitle {
                                Text(topic).font(.subheadline).lineLimit(2).multilineTextAlignment(.center)
                                    .id(topic)
                                    .transition(.opacity)
                            } else if planner.errorMessage != nil {
                                Text("Progress saved. Continue to try again.")
                                    .font(.callout).foregroundStyle(.secondary)
                            }
                        }
                        .frame(maxWidth: 340)
                        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: map.units.count)
                    }
                    if planner.isBusy {
                        Button("Pause") { planner.cancel() }
                            .buttonStyle(.glass).keyboardShortcut(.cancelAction)
                    } else {
                        Button(planner.map == nil ? "Start learning" : "Continue") {
                            planner.build(document: document.pdfDocument)
                        }
                        .buttonStyle(.glassProminent).controlSize(.large)
                        .keyboardShortcut(.return, modifiers: .command)
                        .disabled(!assistantAvailable)
                    }
                    if !assistantAvailable {
                        SettingsLink { Text("Choose an assistant") }
                    }
                    DisclosureGroup("Details") {
                        VStack(alignment: .leading, spacing: 14) {
                            errors
                            Text("Your selected assistant reads the PDF text. Completed pages are saved; unresolved pages and missing proofs stay visible.")
                                .font(.callout).foregroundStyle(.secondary)
                            if let map = planner.map {
                                Text("\(map.units.count) topics identified").font(.callout)
                                goalHistoryButton(map)
                                let attention = map.pages.filter { $0.status != .pending && !$0.status.isResolved }
                                if !attention.isEmpty {
                                    DisclosureGroup("\(attention.count) pages to review") {
                                        ForEach(attention) { page in
                                            HStack(alignment: .top) {
                                                Button("Page \(page.pageIndex + 1)") { document.showNotes(at: page.pageIndex) }
                                                    .buttonStyle(.borderless)
                                                Text(page.reason).font(.callout).foregroundStyle(.secondary)
                                            }.padding(.top, 8)
                                        }
                                    }
                                }
                            }
                            Button("Study a passage instead", action: onStudyPassage)
                                .buttonStyle(.borderless).disabled(document.isBusy)
                        }.padding(.top, 12)
                    }.frame(maxWidth: 420)
                }
                .accessibilityElement(children: .contain)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 500)
                .padding(32)
                .frame(maxWidth: .infinity, minHeight: geometry.size.height)
            }
        }
    }

    private var preparationTitle: String {
        if planner.isConnectingTopics { return "Connecting the ideas" }
        if planner.isBusy { return "Finding the big picture" }
        if planner.errorMessage != nil { return "Preparation paused" }
        return planner.map == nil ? "Learn your notes" : "Ready when you are"
    }

    private var preparationArtwork: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18)
                .fill(Color.accentColor.opacity(0.14))
                .frame(width: 124, height: 156).rotationEffect(.degrees(-9)).offset(x: -12, y: 4)
            RoundedRectangle(cornerRadius: 18)
                .fill(Color.accentColor.opacity(0.22))
                .frame(width: 124, height: 156).rotationEffect(.degrees(8)).offset(x: 12, y: 2)
            RoundedRectangle(cornerRadius: 18)
                .fill(Color(nsColor: .textBackgroundColor))
                .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Color(nsColor: .separatorColor)))
                .frame(width: 124, height: 156)
            Image(systemName: planner.isConnectingTopics ? "point.3.connected.trianglepath.dotted" : "book.pages")
                .font(.system(size: 44, weight: .light)).foregroundStyle(.tint)
                .symbolEffect(.pulse, options: .repeating, isActive: planner.isBusy && !reduceMotion)
        }
        .frame(width: 180, height: 190)
        .accessibilityHidden(true)
    }

    @ViewBuilder private var errors: some View {
        if let error = document.saveError {
            Label(error, systemImage: "exclamationmark.triangle").textSelection(.enabled)
        }
        if let error = planner.errorMessage ?? document.learning.errorMessage {
            Label(error, systemImage: "exclamationmark.circle")
                .font(.callout).textSelection(.enabled)
        }
    }

    private func courseContent(_ course: LearningCourse, map: LearningStudyMap) -> some View {
        ScrollViewReader { scroll in
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(course.title).font(.largeTitle.weight(.semibold))
                    Text("Learning path · \(course.modules.count) chapters · \(document.pageCount) PDF pages")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                errors
                Divider()
                if let run = visibleStudyRun {
                    LearningStudyRunCard(document: document, run: run, map: map, assistantAvailable: assistantAvailable)
                } else if let review = map.nextDelayedReview(sessions: document.learning.sessions, now: reviewClock) {
                    let sourcePage = document.sourceReviewPage(for: review.previous)
                    VStack(alignment: .leading, spacing: 12) {
                        Text(sourcePage != nil ? "Review this check’s source" : review.activeSessionID == nil ? "Revisit an earlier idea" : "Continue your delayed check")
                            .font(.title2.weight(.semibold))
                        Text(review.unit.title).font(.headline).lineLimit(2).accessibilityLabel(review.unit.title)
                        Text("\(review.target.kind.label) · due \(review.dueAt.formatted(date: .abbreviated, time: .omitted))")
                            .font(.caption).foregroundStyle(.secondary)
                        DisclosureGroup("About this check") {
                            VStack(alignment: .leading, spacing: 10) {
                                Text(review.unit.title).font(.headline).textSelection(.enabled)
                                MessageContentView(content: review.target.objective)
                                Text("A different question for the same requirement. Immediate and delayed evidence are recorded separately.")
                                    .font(.callout).foregroundStyle(.secondary)
                            }.frame(maxWidth: .infinity, alignment: .leading).padding(.top, 8)
                        }
                        if let sourcePage {
                            savedSourceRecovery(review.previous, page: sourcePage)
                        } else {
                            Button(review.activeSessionID == nil ? "Try a delayed check" : "Continue delayed check", systemImage: "clock.arrow.circlepath") {
                                document.learning.startDelayedReview(review)
                            }
                            .buttonStyle(.glassProminent).controlSize(.large)
                            .keyboardShortcut(.return, modifiers: .command)
                            .disabled(document.isBusy || (review.activeSessionID == nil && !assistantAvailable))
                        }
                    }
                } else if let openChapter = document.learning.sessions.first(where: {
                    $0.phase != .complete && $0.chapter.map { map.isCurrentChapterRequest($0.request) } == true
                }) {
                    let sourcePage = document.sourceReviewPage(for: openChapter)
                    Text(sourcePage != nil ? "Review this challenge’s source" : "Continue your chapter argument").font(.title2.weight(.semibold))
                    let title = openChapter.chapter?.challenge.title ?? openChapter.lesson.title
                    Text(title).font(.headline).lineLimit(2).accessibilityLabel(title)
                    DisclosureGroup("Challenge details") {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(title).font(.headline).textSelection(.enabled)
                            MessageContentView(content: openChapter.chapter?.challenge.connection ?? openChapter.lesson.objective)
                        }.frame(maxWidth: .infinity, alignment: .leading).padding(.top, 8)
                    }
                    if let sourcePage {
                        savedSourceRecovery(openChapter, page: sourcePage)
                    } else {
                        Button("Continue challenge", systemImage: "arrow.right") { document.learning.select(openChapter.id) }
                            .buttonStyle(.glassProminent).controlSize(.large)
                            .keyboardShortcut(.return, modifiers: .command).disabled(document.isBusy)
                    }
                } else if let ready = course.modules.first(where: { module in
                    guard let request = map.chapterRequest(for: module),
                          document.savedChapter(for: request) == nil else { return false }
                    return request.units.allSatisfy { $0.hasEvidenceForEveryTarget(sessions: document.learning.sessions) }
                }), let request = map.chapterRequest(for: ready) {
                    Text("Bring the chapter together").font(.title2.weight(.semibold))
                    Text(ready.title).font(.headline).lineLimit(2).accessibilityLabel(ready.title)
                    DisclosureGroup("Challenge details") {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(ready.title).font(.headline).textSelection(.enabled)
                            MessageContentView(content: request.connection)
                            ForEach(request.units) { unit in
                                Text(unit.title).font(.subheadline).textSelection(.enabled)
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading).padding(.top, 8)
                    }
                    Button("Try the chapter challenge", systemImage: "point.3.connected.trianglepath.dotted") { startChapter(request) }
                        .buttonStyle(.glassProminent).controlSize(.large)
                        .keyboardShortcut(.return, modifiers: .command)
                        .disabled(document.isBusy || !assistantAvailable)
                } else if let nextStudy {
                    recommendation(nextStudy, course: course) {
                        chaptersExpanded = true
                        chapterNavigationRequest += 1
                    }
                } else {
                    Text("Available checks passed. Review source gaps, and return later to check retention.")
                        .font(.callout).foregroundStyle(.secondary)
                }
                if planner.currentStudyRun == nil || (planner.currentStudyRun?.state == .finished && planner.currentStudyRun?.summaryAcknowledgedAt != nil) {
                    Button("Plan a study session…", systemImage: "list.bullet.clipboard", action: onPlanStudySession)
                        .buttonStyle(.borderless).disabled(document.isBusy || !assistantAvailable)
                }
                Divider()
                DisclosureGroup("Explore \(course.modules.count) chapters", isExpanded: $chaptersExpanded) {
                    ForEach(Array(course.modules.enumerated()), id: \.element.id) { index, module in
                        let units = module.unitIDs.compactMap { id in map.units.first { $0.id == id } }
                        let checks = units.reduce(0) { $0 + $1.learningTargets.count }
                        let checked = units.reduce(0) { $0 + $1.checkedTargetCount(sessions: document.learning.sessions) }
                        let gaps = units.reduce(0) { $0 + $1.openGapCount }
                        Divider()
                        DisclosureGroup {
                            VStack(alignment: .leading, spacing: 18) {
                                MessageContentView(content: module.goal)
                                let connections = course.connections.filter { module.unitIDs.contains($0.toUnitID) }
                                if !connections.isEmpty {
                                    DisclosureGroup("How the ideas connect") {
                                        ForEach(Array(connections.enumerated()), id: \.offset) { _, connection in
                                            let from = map.units.first { $0.id == connection.fromUnitID }?.title ?? ""
                                            let to = map.units.first { $0.id == connection.toUnitID }?.title ?? ""
                                            VStack(alignment: .leading, spacing: 6) {
                                                Text("\(from) → \(to)").font(.subheadline.weight(.medium))
                                                MessageContentView(content: connection.reason)
                                            }.padding(.top, 10)
                                        }
                                    }
                                }
                                let request = map.chapterRequest(for: module)
                                let saved = request.flatMap { document.savedChapter(for: $0) }
                                if let saved {
                                    Button("Continue chapter challenge", systemImage: "arrow.right") { document.learning.select(saved.id) }
                                        .buttonStyle(.glass).disabled(document.isBusy)
                                } else if let request {
                                    Button("Try the chapter challenge", systemImage: "point.3.connected.trianglepath.dotted") { startChapter(request) }
                                        .buttonStyle(.glass).disabled(document.isBusy || !assistantAvailable)
                                    Text("Connect \(request.units.map(\.title).joined(separator: " and ")). Each source and proof requirement stays separate.")
                                        .font(.caption).foregroundStyle(.secondary)
                                } else {
                                    chapterRecovery(module, map: map)
                                }
                                let earlier = document.learning.sessions.filter {
                                    $0.chapter?.request.moduleID == module.id && $0.id != saved?.id
                                }
                                if !earlier.isEmpty {
                                    Menu("Earlier challenges (\(earlier.count))", systemImage: "clock.arrow.circlepath") {
                                        ForEach(Array(earlier.enumerated()), id: \.element.id) { index, session in
                                            Button {
                                                document.learning.select(session.id)
                                            } label: {
                                                Text("\(earlier.count - index). \(session.chapter?.challenge.title ?? session.lesson.title) · \(session.phase.label) · \(session.createdAt.formatted(date: .abbreviated, time: .shortened))")
                                            }
                                        }
                                    }.disabled(document.isBusy)
                                    Text("Earlier questions, answers and feedback remain saved with their original requirements and source.")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                ForEach(units) { unit in unitRow(unit).id(unit.id) }
                            }.padding(.top, 16)
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("\(index + 1). \(module.title)").font(.title3.weight(.medium))
                                Text("\(units.count) \(units.count == 1 ? "topic" : "topics") · \(checked) of \(checks) checks")
                                    .font(.caption).foregroundStyle(.secondary)
                                if gaps > 0 {
                                    Label("\(gaps) source \(gaps == 1 ? "gap" : "gaps") still open", systemImage: "questionmark.circle")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
                .id("learning-chapters")
                Divider()
                courseDetails(course, map: map)
            }
            .accessibilityElement(children: .contain)
            .padding(32).frame(maxWidth: 824, alignment: .leading).frame(maxWidth: .infinity)
        }
        .onChange(of: chapterNavigationRequest) {
            // Scroll from the updated view tree, after opening the existing
            // chapter disclosure, including repeated requests when it is open.
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
                scroll.scrollTo("learning-chapters", anchor: .top)
            }
        }
        .onChange(of: expandedUnitID) {
            if let id = expandedUnitID {
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) { scroll.scrollTo(id, anchor: .top) }
            }
        }
        }
    }

    private func savedSourceRecovery(_ session: LearningSession, page: Int) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Your saved work is retained. Review the current notes on PDF page \(page + 1).")
                .font(.callout).foregroundStyle(.secondary)
            Button("Review current source", systemImage: "doc.text.magnifyingglass") { document.showNotes(at: page) }
                .buttonStyle(.glassProminent).controlSize(.large)
                .keyboardShortcut(.return, modifiers: .command).disabled(document.isBusy)
            Button("Inspect saved work") { document.learning.select(session.id) }
                .buttonStyle(.borderless).disabled(document.isBusy)
        }
    }

    private func courseDetails(_ course: LearningCourse, map: LearningStudyMap) -> some View {
        let gaps = map.units.reduce(0) { $0 + $1.openGapCount }
        return DisclosureGroup {
            VStack(alignment: .leading, spacing: 20) {
                DisclosureGroup("Overview") {
                    MessageContentView(content: course.overview).padding(.top, 8)
                }
                sourceReview(map)
                syllabusReview(map)
                goalHistoryButton(map)
                if let runs = map.studyRuns?.filter({ $0.state == .finished }), !runs.isEmpty {
                    DisclosureGroup("Past study sessions") {
                        ForEach(runs.reversed()) { run in
                            DisclosureGroup(run.startedAt.formatted(date: .abbreviated, time: .shortened)) {
                                LearningStudyRunRecord(run: run, sessions: document.learning.sessions).padding(.top, 10)
                            }.padding(.top, 8)
                        }
                    }
                }
                DisclosureGroup("Coverage details") {
                    coverage(map).padding(.top, 12)
                    if !map.unresolvedPages.isEmpty {
                        Button("Retry unresolved pages") { planner.build(document: document.pdfDocument) }
                            .buttonStyle(.borderless).disabled(document.isBusy || !assistantAvailable)
                    }
                }
            }.padding(.top, 16)
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                Text("Course details")
                if gaps > 0 || !map.unresolvedPages.isEmpty {
                    let issues = gaps == 1 ? "1 source issue open" : "\(gaps) source issues open"
                    let pages = map.unresolvedPages.count == 1 ? "1 page to review" : "\(map.unresolvedPages.count) pages to review"
                    Text([gaps > 0 ? issues : nil, map.unresolvedPages.isEmpty ? nil : pages].compactMap { $0 }.joined(separator: " · "))
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("Sources, syllabus and coverage").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder private func goalHistoryButton(_ map: LearningStudyMap) -> some View {
        let count = LearningGoalHistory.entries(in: map).count
        if count > 0 {
            Button("Review goal revisions (\(count))", systemImage: "clock.arrow.circlepath") {
                goalHistoryVisible = true
            }.buttonStyle(.borderless)
        }
    }

    private func syllabusReview(_ map: LearningStudyMap) -> some View {
        DisclosureGroup("Compare with your syllabus") {
            VStack(alignment: .leading, spacing: 14) {
                Text("Record what your course requires, then map each kind of work to the notes. You make and review these mappings; source coverage and learner evidence remain separate.")
                    .font(.callout).foregroundStyle(.secondary)
                if let syllabus = map.syllabus {
                    let coverage = syllabus.coverage(in: map, sessions: document.learning.sessions)
                    Text("\(coverage.sourceMapped) of \(coverage.required) syllabus obligations mapped to usable source")
                        .font(.subheadline.weight(.medium))
                    Text("\(coverage.checked) have an immediate unassisted correct check on every mapped requirement. This does not establish whole-subject mastery or retention.")
                        .font(.caption).foregroundStyle(.secondary)
                    ForEach(syllabus.requirements) { requirement in
                        DisclosureGroup(requirement.text) {
                            Text("Added from: \(requirement.provenance)").font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                            ForEach(requirement.kinds, id: \.self) { kind in
                                let mapping = syllabus.latestMapping(for: requirement, kind: kind)
                                let current = mapping.flatMap { syllabus.sourceTargets(for: $0, in: map) } != nil
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(kind.label).font(.subheadline.weight(.medium))
                                    Text(current ? "Mapped to usable source" : mapping?.status == .absent ? "Absent from these notes — your source review" : "Unresolved — review the mapping or source obligations")
                                        .font(.caption).foregroundStyle(.secondary)
                                    if let mapping {
                                        Text(mapping.note).font(.callout).textSelection(.enabled)
                                        ForEach(mapping.references, id: \.target.id) { reference in
                                            Text(reference.target.objective).font(.caption).textSelection(.enabled)
                                        }
                                    }
                                    Button("Review \(kind.label.lowercased()) mapping") {
                                        syllabusMapping = .init(requirement: requirement, kind: kind)
                                    }.buttonStyle(.borderless).disabled(document.isBusy)
                                }.padding(.top, 8)
                            }
                        }
                    }
                }
                DisclosureGroup("Add required syllabus items") {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("One requirement per line").font(.caption)
                        TextEditor(text: $syllabusText).frame(minHeight: 100).accessibilityLabel("Syllabus requirements, one per line")
                        TextField("Where do these requirements come from?", text: $syllabusProvenance)
                            .textFieldStyle(.roundedBorder).accessibilityLabel("Syllabus provenance")
                        ForEach(LearningStudyKind.allCases, id: \.self) { kind in
                            Toggle(kind.label, isOn: Binding(get: { syllabusKinds.contains(kind) }, set: { checked in
                                if checked { syllabusKinds.insert(kind) } else { syllabusKinds.remove(kind) }
                            }))
                        }
                        Button("Add requirements") {
                            do {
                                try planner.addSyllabusRequirements(syllabusText,
                                    kinds: LearningStudyKind.allCases.filter { syllabusKinds.contains($0) }, provenance: syllabusProvenance)
                                syllabusText = ""
                            } catch { planner.errorMessage = error.localizedDescription }
                        }.disabled(document.isBusy || syllabusKinds.isEmpty || syllabusText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }.padding(.top, 8)
                }
            }.padding(.top, 10)
        }
    }

    private func chapterRecovery(_ module: LearningCourse.Module, map: LearningStudyMap) -> some View {
        let availability = map.chapterAvailability(for: module)
        return VStack(alignment: .leading, spacing: 10) {
            Text("Chapter challenge unavailable").font(.subheadline.weight(.medium))
            Text("Source support needs attention. This does not assess your understanding.")
                .font(.caption).foregroundStyle(.secondary)
            DisclosureGroup("What needs attention (\(availability.blockers.count))") {
                ForEach(availability.blockers) { blocker in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(blocker.reason).font(.callout).textSelection(.enabled)
                        if let page = blocker.pageIndex {
                            Button("Review source · PDF page \(page + 1)", systemImage: "doc.text.magnifyingglass") {
                                expandedUnitID = blocker.unitID
                                document.showNotes(at: page)
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel("Review source for \(blocker.unitID.flatMap { id in map.units.first { $0.id == id }?.title } ?? module.title), PDF page \(page + 1)")
                        }
                    }.padding(.top, 8)
                }
            }
        }
    }

    private func unitRow(_ unit: LearningStudyUnit) -> some View {
        DisclosureGroup(isExpanded: Binding(
            get: { expandedUnitID == unit.id },
            set: { expandedUnitID = $0 ? unit.id : nil }
        )) {
            unitContent(unit).padding(.top, 16)
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                Text(unit.title).font(.headline)
                Text("PDF page \(unit.anchorPage + 1) · \(unit.learningTargets.count) learning checks")
                    .font(.caption).foregroundStyle(.secondary)
                if unit.needsSourceReview {
                    Text("Source review needed for new lessons").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func recommendation(_ next: LearningStudyRecommendation, course: LearningCourse,
                                chooseAnotherLesson: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            let module = course.modules.first { $0.unitIDs.contains(next.unit.id) }
            HStack(alignment: .top, spacing: 16) {
                Image(systemName: next.target.kind.symbol)
                    .font(.system(size: 25, weight: .light)).foregroundStyle(.tint)
                    .frame(width: 56, height: 56)
                    .background(Color.accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 14))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 6) {
                    Text(next.label).font(.subheadline).foregroundStyle(.secondary)
                    Text(next.unit.title).font(.title2.weight(.semibold))
                        .lineLimit(2).accessibilityLabel(next.unit.title)
                    Text(module.map { "\($0.title) · \(next.target.kind.label)" } ?? next.target.kind.label)
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            DisclosureGroup("Lesson goal") {
                VStack(alignment: .leading, spacing: 10) {
                    Text(next.unit.title).font(.headline).textSelection(.enabled)
                    MessageContentView(content: next.target.objective)
                }.frame(maxWidth: .infinity, alignment: .leading).padding(.top, 8)
            }
            if let session = next.session {
                Text(next.requiresRevisedLesson ? "Your earlier lesson and answers remain saved." : "\(session.phase.label) · your saved work is ready")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if next.requiresSourceReview {
                Text("The extracted mathematics needs checking. Review PDF page \(next.sourceReviewPageIndex + 1); this requirement stays open.")
                    .font(.callout).foregroundStyle(.secondary)
                gapDetails(next.unit)
            } else if next.unit.needsSourceReview {
                Text("Your saved lesson is available. The source issue still needs review before preparing new teaching.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Button(next.actionLabel, systemImage: next.actionSymbol) {
                if next.requiresSourceReview {
                    document.showNotes(at: next.sourceReviewPageIndex)
                } else {
                    study(next.target, unit: next.unit, prepareNew: next.requiresRevisedLesson)
                }
            }
            .buttonStyle(.glassProminent).controlSize(.large)
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(!next.canPerformAction(assistantAvailable: assistantAvailable, isBusy: document.isBusy))
            if next.requiresRevisedLesson, let previous = next.session {
                Button("Inspect previous lesson and answers") { document.learning.select(previous.id) }
                    .buttonStyle(.borderless).disabled(document.isBusy)
            }
            if next.requiresSourceReview {
                let otherWork = planner.map?.availableStudyChoices(sessions: document.learning.sessions)
                    .filter { $0.target.id != next.target.id } ?? []
                Button(otherWork.isEmpty ? "Explore chapters" : "Choose another lesson", action: chooseAnotherLesson)
                    .buttonStyle(.borderless)
                Text(otherWork.isEmpty
                     ? "No other unchecked lessons are available. You can revisit saved lessons from the sidebar."
                     : "Choosing other work leaves this source review open. Check that topic’s prerequisites before starting.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }.accessibilityElement(children: .contain)
    }

    private var actionBar: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 12) {
                if planner.isBusy {
                    ProgressView().controlSize(.small)
                    Text(planner.isReconciling ? "Checking source references · \(planner.reconciliationCompleted) topics saved"
                         : planner.isConnectingTopics ? "Connecting ideas across your notes…"
                         : "Reviewing your notes…")
                        .font(.callout)
                    Spacer()
                    Button("Cancel") { planner.cancel() }.keyboardShortcut(.cancelAction)
                } else if document.learning.isBusy {
                    ProgressView().controlSize(.small)
                    Text("Preparing your lesson…")
                    Spacer()
                    Button("Cancel") { document.learning.cancel() }.keyboardShortcut(.cancelAction)
                }
            }
            .padding(.horizontal, 32).padding(.vertical, 20)
            .frame(maxWidth: 824).frame(maxWidth: .infinity)
        }.background(Color(nsColor: .windowBackgroundColor))
    }

    private func coverage(_ map: LearningStudyMap) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("\(map.resolvedPageCount) of \(map.pages.count) PDF pages accounted for").font(.headline)
            let targets = map.units.reduce(0) { $0 + $1.learningTargets.count }
            let checked = map.units.reduce(0) { $0 + $1.checkedTargetCount(sessions: document.learning.sessions) }
            if targets > 0 {
                Text("\(checked) of \(targets) study requirements have an unassisted correct check.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            DisclosureGroup("About coverage and learning evidence") {
                Text("This map inventories your supplied notes. Source coverage and evidence of learning are separate; an AI map can still miss material. Compare it with your syllabus and the notes. An unassisted correct check is evidence on one problem, not a guarantee of retention.")
                    .font(.callout).foregroundStyle(.secondary).padding(.top, 8)
            }
            if !map.unresolvedPages.isEmpty {
                DisclosureGroup("Pages still needing attention (\(map.unresolvedPages.count))") {
                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(map.unresolvedPages) { page in
                            HStack(alignment: .top) {
                                Button("Page \(page.pageIndex + 1)") { document.showNotes(at: page.pageIndex) }
                                    .buttonStyle(.borderless)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(page.status.label).font(.callout.weight(.medium))
                                    if !page.reason.isEmpty { Text(page.reason).font(.caption).foregroundStyle(.secondary) }
                                }
                            }
                        }
                    }.padding(.top, 10)
                }
            }
            let excluded = map.pages.filter { $0.status == .nonInstructional }
            if !excluded.isEmpty {
                DisclosureGroup("Pages without study material (\(excluded.count))") {
                    ForEach(excluded) { page in
                        HStack(alignment: .top) {
                            Button("Page \(page.pageIndex + 1)") { document.showNotes(at: page.pageIndex) }
                                .buttonStyle(.borderless)
                            Text(page.reason).font(.callout).foregroundStyle(.secondary)
                        }.padding(.top, 8)
                    }
                }
            }
        }
    }

    private func unitContent(_ unit: LearningStudyUnit) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Button("PDF page \(unit.anchorPage + 1)", systemImage: "doc.text") { document.showNotes(at: unit.anchorPage) }
                    .buttonStyle(.borderless)
                Spacer()
                Text("\(unit.checkedTargetCount(sessions: document.learning.sessions)) of \(unit.learningTargets.count) checks")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if !unit.prerequisites.isEmpty {
                DisclosureGroup("Prerequisites") {
                    ForEach(Array(unit.prerequisites.enumerated()), id: \.offset) { _, prerequisite in
                        MessageContentView(content: prerequisite).padding(.top, 6)
                    }
                }
            }
            if !unit.gaps.isEmpty || unit.hasUnlocatedProof || unit.pendingSourceCorrection == true { gapDetails(unit) }
            ForEach(unit.learningTargets) { target in
                HStack(alignment: .top, spacing: 16) {
                    Image(systemName: target.kind.symbol).foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(target.kind.label).font(.subheadline.weight(.semibold))
                        MessageContentView(content: target.objective)
                        if target.revisionID != nil {
                            Text("Goal revised by you").font(.caption).foregroundStyle(.secondary)
                        }
                        Text(status(target, unit: unit)).font(.caption).foregroundStyle(.secondary)
                        HStack(spacing: 14) {
                            if !LearningRequirementHistory.sessions(for: target, in: document.learning.sessions).isEmpty {
                                Button("Review my work", systemImage: "clock.arrow.circlepath") { historyTarget = target }
                                    .buttonStyle(.borderless).disabled(document.isBusy)
                                    .accessibilityLabel("Review my work · \(target.kind.label)")
                            }
                            Button("Revise goal", systemImage: "pencil") {
                                goalSelection = .init(unit: unit, target: target)
                            }
                            .buttonStyle(.borderless).disabled(document.isBusy)
                            .accessibilityLabel("Revise goal · \(target.kind.label)")
                        }
                    }
                    Spacer(minLength: 0)
                    Button(actionLabel(target)) { study(target, unit: unit) }
                        .disabled(!canStudy(target) || (unit.needsSourceReview && savedLesson(for: target) == nil))
                }
                if !unit.needsSourceReview,
                   let saved = savedLesson(for: target),
                   !LearningSourceBuilder.matches(saved.source, document: document.pdfDocument, map: planner.map) {
                    Button("Prepare a lesson from the revised source", systemImage: "arrow.clockwise") {
                        study(target, unit: unit, prepareNew: true)
                    }
                    .buttonStyle(.borderless).disabled(document.isBusy || !assistantAvailable)
                    Text("Your earlier lesson and answers remain saved. The revised lesson has its own source record and learning checks.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            DisclosureGroup("Source reference") {
                Text(unit.teachingAnchor.quote).font(.callout).textSelection(.enabled).padding(.top, 8)
                if let anchor = unit.reconciliation?.revisedAnchor {
                    Text("User-verified transcription · revision \(anchor.correctionID?.uuidString ?? "unavailable")")
                        .font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                    DisclosureGroup("Original extracted anchor — retained") {
                        Text(unit.sourceQuote).font(.callout).textSelection(.enabled)
                    }
                }
            }
        }
    }

    private func status(_ target: LearningStudyTarget, unit: LearningStudyUnit) -> String {
        guard let attempt = unit.evidence(for: target, sessions: document.learning.sessions) else {
            if savedLesson(for: target) != nil { return "In progress — no exit evidence yet" }
            if LearningRequirementHistory.sessions(for: target, in: document.learning.sessions)
                .contains(where: { !target.matchesRequirement($0.studyTarget) }) {
                return "Not checked — requirement changed; earlier work is saved"
            }
            return "Not checked"
        }
        if attempt.setAsideAt != nil { return "Assessment set aside by you — requirement remains open" }
        switch attempt.assessment.grade {
        case .correct:
            if !attempt.assessmentCriteriaSatisfied {
                return target.kind == .proof ? "Proof assessment incomplete — check remains open" : "Assessment needs checking — requirement remains open"
            }
            return attempt.assistanceUsed ? "Correct with help — independent check still open" : "Correct on one unassisted check — retention not yet established"
        case .partial, .incorrect: return "More practice needed"
        case .uncertain: return "Assessment inconclusive"
        }
    }

    private func actionLabel(_ target: LearningStudyTarget) -> String {
        savedLesson(for: target) != nil ? "Open lesson" : "Study"
    }

    private func savedLesson(for target: LearningStudyTarget) -> LearningSession? {
        document.learning.sessions.first {
            $0.chapter == nil && $0.delayedReview == nil && target.matchesRequirement($0.studyTarget)
        }
    }

    private func startChapter(_ request: LearningChapterRequest) {
        guard !document.isBusy, let map = planner.map else { return }
        let indices = Array(Set(request.units.flatMap(\.learningPageIndices))).sorted()
        let passages = indices.compactMap { index -> LearningSourcePassage? in
            guard map.pageSignatures.indices.contains(index), let text = document.pdfDocument.page(at: index)?.string,
                  LearningStudyInput.signature(text) == map.pageSignatures[index] else { return nil }
            return try? map.passage(pageIndex: index, originalText: text)
        }
        guard passages.count == indices.count else {
            document.learning.errorMessage = LearningError.sourceChanged.localizedDescription
            return
        }
        document.learning.startChapter(request: request, source: .init(passages: passages))
    }

    private func canStudy(_ target: LearningStudyTarget) -> Bool {
        !document.isBusy && (assistantAvailable || savedLesson(for: target) != nil)
    }

    private func study(_ target: LearningStudyTarget, unit: LearningStudyUnit, prepareNew: Bool = false) {
        document.study(target, unit: unit, prepareNew: prepareNew)
    }

    private func sourceReview(_ map: LearningStudyMap) -> some View {
        let candidates = map.units.filter { !$0.gaps.isEmpty || $0.pendingSourceCorrection == true }
        let reviewed = candidates.filter { $0.reconciliation != nil && $0.pendingSourceCorrection != true }.count
        let open = map.units.reduce(0) { $0 + $1.openGapCount }
        return DisclosureGroup("Source review · \(open) \(open == 1 ? "issue" : "issues") open") {
            VStack(alignment: .leading, spacing: 12) {
                Text("\(reviewed) of \(candidates.count) topics checked against document references. Located sources do not count as learning checks.")
                    .font(.callout).foregroundStyle(.secondary)
                let missingProofs = map.units.filter(\.hasUnlocatedProof).count
                if missingProofs > 0 {
                    Text("\(missingProofs) proof obligations still need a complete usable source argument.")
                        .font(.callout).foregroundStyle(.secondary)
                }
                if reviewed < candidates.count {
                    Button(reviewed == 0 ? "Check source references" : "Continue source review") {
                        planner.reconcile(document: document.pdfDocument)
                    }.disabled(document.isBusy || !assistantAvailable)
                }
                if planner.isReconciling, let topic = planner.recentTopicTitle {
                    Text("Checking \(topic)").font(.caption).foregroundStyle(.secondary)
                }
                ForEach(LearningGapDisposition.allCases, id: \.self) { disposition in
                    let count = map.units.flatMap { $0.reconciliation?.issues ?? [] }.filter { $0.disposition == disposition }.count
                    if count > 0 { Text("\(disposition.label): \(count)").font(.caption).foregroundStyle(.secondary) }
                }
                Text("Search examines every page’s text; retrieved pages and followed references receive model review. A search miss does not establish omission. Open a chapter and topic for exact evidence.")
                    .font(.caption).foregroundStyle(.secondary)
            }.padding(.top, 10)
        }
    }

    private func gapDetails(_ unit: LearningStudyUnit) -> some View {
        DisclosureGroup("Source issues · \(unit.openGapCount) open") {
            VStack(alignment: .leading, spacing: 14) {
                if unit.reconciliation == nil || unit.pendingSourceCorrection == true {
                    if unit.pendingSourceCorrection == true {
                        Text("A user-verified transcription is saved. Recheck this topic’s teaching sources and proof obligations; previous lessons and answers remain inspectable.")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                    Button("Check these source issues") {
                        planner.reconcile(document: document.pdfDocument, unitID: unit.id)
                    }.disabled(document.isBusy || !assistantAvailable)
                }
                ForEach(Array(unit.gaps.enumerated()), id: \.offset) { index, gap in
                    let review = unit.reconciliation?.issues.first { $0.gapIndex == index }
                    VStack(alignment: .leading, spacing: 8) {
                        Text(review?.disposition == .foundElsewhere && review?.evidence.contains(where: { $0.correctionID != nil }) == true
                             ? "User transcription reviewed" : review?.disposition.label ?? "Candidate warning — not reconciled")
                            .font(.subheadline.weight(.medium))
                        Text(review?.explanation ?? gap).font(.callout).textSelection(.enabled)
                        if let review {
                            DisclosureGroup("Evidence and original warning") {
                                Text(gap).font(.caption).foregroundStyle(.secondary)
                                ForEach(Array(review.evidence.enumerated()), id: \.offset) { _, evidence in
                                    if let correctionID = evidence.correctionID {
                                        Text("User-verified transcription · revision \(correctionID.uuidString)")
                                            .font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                                    } else {
                                        Text("Original PDF extraction").font(.caption).foregroundStyle(.secondary)
                                    }
                                    Button("PDF page \(evidence.pageIndex + 1)") { document.showNotes(at: evidence.pageIndex) }
                                        .buttonStyle(.borderless)
                                    Text(evidence.quote).font(.callout).textSelection(.enabled)
                                }
                            }
                        }
                    }
                }
                if unit.needsSourceReview {
                    Button("Compare local OCR of page \(unit.anchorPage + 1)") {
                        recognizeForInspection(unit.anchorPage)
                    }.disabled(recognizingPage != nil)
                    if let text = localOCR[unit.anchorPage] {
                        DisclosureGroup("Local OCR — unverified, inspection only") {
                            Text(text).font(.callout).textSelection(.enabled)
                            Text("Compare with the rendered page. OCR does not correct the source or unlock lessons.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                if let reconciliation = unit.reconciliation {
                    DisclosureGroup("Review scope") {
                        Text("Text searched: \(reconciliation.searchedPageCount) pages. Pages supplied for review: \(reconciliation.inspectedPageIndices.map { String($0 + 1) }.joined(separator: ", ")). Assistant: \(reconciliation.modelID ?? reconciliation.providerID).")
                            .font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                    }
                }
                Text("Open issues and proof obligations remain even if available checks pass.")
                    .font(.caption).foregroundStyle(.secondary)
                if unit.hasUnlocatedProof {
                    Text("Proof still required. No complete usable source argument is available for a proof lesson yet.")
                        .font(.callout).foregroundStyle(.secondary)
                }
            }.padding(.top, 10)
        }
    }

    private func recognizeForInspection(_ pageIndex: Int) {
        guard let page = document.pdfDocument.page(at: pageIndex),
              let image = PDFRegionRenderer.renderFullPage(page) else { return }
        recognizingPage = pageIndex
        Task { @MainActor in
            do { localOCR[pageIndex] = try await OCRService.shared.recognizeText(in: image).rawText }
            catch { localOCR[pageIndex] = "Local OCR failed: \(error.localizedDescription)" }
            recognizingPage = nil
        }
    }
}

private struct LearningSyllabusSelection: Identifiable {
    var id: String { "\(requirement.id):\(kind.rawValue)" }
    let requirement: LearningSyllabus.Requirement
    let kind: LearningStudyKind
}

private struct LearningSyllabusMappingEditor: View {
    @Bindable var document: LearningDocument
    let requirement: LearningSyllabus.Requirement
    let kind: LearningStudyKind
    @State private var selected: Set<UUID>
    @State private var status: LearningSyllabus.Status
    @State private var note = ""
    @State private var error: String?
    @Environment(\.dismiss) private var dismiss

    init(document: LearningDocument, requirement: LearningSyllabus.Requirement, kind: LearningStudyKind) {
        self.document = document
        self.requirement = requirement
        self.kind = kind
        let previous = document.studyMap.map?.syllabus?.latestMapping(for: requirement, kind: kind)
        _selected = State(initialValue: Set(previous?.references.map(\.target.id) ?? []))
        _status = State(initialValue: previous?.status ?? .mapped)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Review syllabus mapping").font(.title2.weight(.semibold))
            Text(requirement.text).font(.headline).textSelection(.enabled)
            Text(kind.label).font(.subheadline).foregroundStyle(.secondary)
            Picker("Source finding", selection: $status) {
                ForEach(LearningSyllabus.Status.allCases, id: \.self) { Text($0.label).tag($0) }
            }
            if status == .mapped {
                Text("Select every source requirement needed for this obligation. Missing proof targets cannot be replaced by concept or application checks.")
                    .font(.callout).foregroundStyle(.secondary)
                List {
                    ForEach(document.studyMap.map?.units ?? []) { unit in
                        let targets = unit.learningTargets.filter { $0.kind == kind }
                        if !targets.isEmpty {
                            Section("\(unit.title) · PDF page \(unit.anchorPage + 1)") {
                                ForEach(targets) { target in
                                    Toggle(target.objective, isOn: Binding(get: { selected.contains(target.id) }, set: { checked in
                                        if checked { selected.insert(target.id) } else { selected.remove(target.id) }
                                    })).disabled(unit.needsSourceReview && !selected.contains(target.id))
                                }
                                if unit.needsSourceReview || unit.openGapCount > 0 {
                                    Text("Source obligations remain open; this mapping will not count as usable source coverage yet.")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }.frame(minHeight: 200)
            } else {
                Text(status == .absent ? "This records your source review. It leaves the required curriculum item open and does not certify that the material is absent from every possible source."
                     : "Keep the requirement visible while you decide which source and study obligations support it.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            TextField("Why is this mapping correct, absent, or unresolved?", text: $note, axis: .vertical)
                .textFieldStyle(.roundedBorder).lineLimit(2...4).accessibilityLabel("Mapping decision and provenance note")
            if let history = document.studyMap.map?.syllabus?.history.filter({ $0.requirementID == requirement.id && $0.kind == kind }), !history.isEmpty {
                DisclosureGroup("Previous mapping decisions (\(history.count))") {
                    ScrollView {
                        ForEach(history.reversed()) { mapping in
                            VStack(alignment: .leading, spacing: 4) {
                                Text("\(mapping.createdAt.formatted(date: .abbreviated, time: .shortened)) · \(mapping.status.label)").font(.caption)
                                Text(mapping.note).font(.callout).textSelection(.enabled)
                                ForEach(mapping.references, id: \.target.id) { Text($0.target.objective).font(.caption) }
                            }.padding(.bottom, 10)
                        }
                    }.frame(maxHeight: 160)
                }
            }
            if let error { Text(error).font(.callout).foregroundStyle(.secondary) }
            HStack {
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Save mapping decision") {
                    do {
                        try document.studyMap.mapSyllabusRequirement(requirement.id, kind: kind,
                            targetIDs: status == .mapped ? Array(selected) : [], status: status, note: note)
                        dismiss()
                    } catch { self.error = error.localizedDescription }
                }
                .buttonStyle(.glassProminent).keyboardShortcut(.defaultAction)
                .disabled(document.isBusy || note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || (status == .mapped && selected.isEmpty))
            }
        }.padding(24).frame(minWidth: 600, idealWidth: 720, minHeight: 560)
    }
}

private struct LearningGoalSelection: Identifiable {
    var id: UUID { target.id }
    let unit: LearningStudyUnit
    let target: LearningStudyTarget
}

private struct LearningGoalRevisionRecord: View {
    let revision: LearningGoalRevision

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(revision.unitTitle) · \(revision.previous.kind.label)").font(.subheadline.weight(.medium))
            Text("Revised by you · \(revision.createdAt.formatted(date: .abbreviated, time: .shortened))")
                .font(.caption).foregroundStyle(.secondary)
            MessageContentView(content: revision.objective)
            Text(revision.note).font(.callout).textSelection(.enabled)
            DisclosureGroup("Previous goal and source reference") {
                VStack(alignment: .leading, spacing: 8) {
                    MessageContentView(content: revision.previous.objective)
                    Text("PDF page \(revision.source.pageIndex + 1)").font(.caption).foregroundStyle(.secondary)
                    Text(revision.source.quote).font(.callout).textSelection(.enabled)
                    if revision.source.correctionID != nil {
                        Text("Source reference uses a user-verified transcription.").font(.caption).foregroundStyle(.secondary)
                    }
                }.padding(.top, 8)
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct LearningGoalEditor: View {
    let document: LearningDocument
    let unit: LearningStudyUnit
    let target: LearningStudyTarget
    @State private var objective: String
    @State private var note = ""
    @State private var error: String?
    @Environment(\.dismiss) private var dismiss

    init(document: LearningDocument, unit: LearningStudyUnit, target: LearningStudyTarget) {
        self.document = document
        self.unit = unit
        self.target = target
        _objective = State(initialValue: target.objective)
    }

    private var canSave: Bool {
        !document.isBusy && !objective.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && objective.trimmingCharacters(in: .whitespacesAndNewlines).count <= 2_000
            && LearningSource.normalized(objective) != LearningSource.normalized(target.objective)
            && !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && note.trimmingCharacters(in: .whitespacesAndNewlines).count <= 2_000
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Revise study goal").font(.title2.weight(.semibold))
            Text("\(unit.title) · \(target.kind.label)").font(.subheadline).foregroundStyle(.secondary)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Correct the wording to describe what you need to learn from this source.").font(.callout)
                    Text("Study goal").font(.headline)
                    TextEditor(text: $objective).font(.body).frame(minHeight: 100, idealHeight: 140)
                        .padding(6).background(.background, in: RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(.separator))
                        .accessibilityLabel("Revised study goal")
                    TextField("Why are you revising this goal?", text: $note, axis: .vertical)
                        .textFieldStyle(.roundedBorder).lineLimit(2...4).accessibilityLabel("Goal revision reason")
                    Text("The revised goal starts unchecked. Earlier lessons, answers and feedback stay saved. Source issues, proof obligations and syllabus requirements remain; review any syllabus mapping that used this goal.")
                        .font(.callout).foregroundStyle(.secondary)
                    DisclosureGroup("Current goal and source reference") {
                        VStack(alignment: .leading, spacing: 8) {
                            MessageContentView(content: target.objective)
                            Text("PDF page \(unit.teachingAnchor.pageIndex + 1)").font(.caption).foregroundStyle(.secondary)
                            Text(unit.teachingAnchor.quote).font(.callout).textSelection(.enabled)
                        }.padding(.top, 8)
                    }
                    let revisions = unit.goalRevisions?.filter { $0.previous.id == target.id } ?? []
                    if !revisions.isEmpty {
                        DisclosureGroup("Previous goal revisions (\(revisions.count))") {
                            ForEach(revisions.reversed()) { revision in
                                LearningGoalRevisionRecord(revision: revision).padding(.top, 12)
                            }
                        }
                    }
                    if let error { Text(error).font(.callout).foregroundStyle(.secondary).textSelection(.enabled) }
                }.padding(2)
            }
            HStack {
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Save revised goal") {
                    guard !document.isBusy else { return }
                    do {
                        try document.studyMap.reviseGoal(target, in: unit, objective: objective, note: note, document: document.pdfDocument)
                        dismiss()
                    } catch { self.error = error.localizedDescription }
                }
                .buttonStyle(.glassProminent).keyboardShortcut(.return, modifiers: .command).disabled(!canSave)
            }
        }.padding(24).frame(minWidth: 560, idealWidth: 640, minHeight: 480, idealHeight: 600)
    }
}

private struct LearningGoalHistoryView: View {
    let document: LearningDocument
    @State private var selection: UUID?
    @State private var detailScroll = ScrollPosition()
    @State private var detailOffset: CGFloat = 0
    private enum Pane: Hashable { case list, details }
    @FocusState private var focusedPane: Pane?
    @Environment(\.dismiss) private var dismiss

    private var entries: [LearningGoalHistory.Entry] {
        document.studyMap.map.map { LearningGoalHistory.entries(in: $0) } ?? []
    }
    private var selected: LearningGoalHistory.Entry? { entries.first { $0.id == selection } }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Your goal revisions").font(.title2.weight(.semibold))
            Text("Saved wording decisions, most recent first.").font(.callout).foregroundStyle(.secondary)
            HSplitView {
                List(selection: $selection) {
                    ForEach(entries) { entry in
                        VStack(alignment: .leading, spacing: 5) {
                            Text(entry.revision.unitTitle).font(.subheadline.weight(.medium))
                            Text(entry.revision.previous.kind.label).font(.callout)
                            Text(entry.status.label).font(.caption)
                            Text(entry.revision.createdAt.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption).foregroundStyle(.secondary)
                        }.padding(.vertical, 4).tag(entry.id)
                    }
                }
                .accessibilityLabel("Saved goal revisions").focused($focusedPane, equals: .list)
                .frame(minWidth: 210, idealWidth: 230, maxWidth: 280)
                ScrollView {
                    if let selected {
                        VStack(alignment: .leading, spacing: 16) {
                            Text(selected.status.label).font(.headline)
                            if selected.status == .earlierSource {
                                Text("This decision refers to earlier source text. Its page reference may differ from the current PDF.")
                                    .font(.callout).foregroundStyle(.secondary)
                            } else if selected.status == .earlierGoal {
                                Text("This decision is kept for reference. It does not replace the current goal.")
                                    .font(.callout).foregroundStyle(.secondary)
                            }
                            LearningGoalRevisionRecord(revision: selected.revision)
                        }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        Text("No saved goal revisions.").foregroundStyle(.secondary).padding(24)
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
            }
            HStack {
                Button("Close") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button(focusedPane == .details ? "Choose another revision" : "Read selected revision") {
                    focusedPane = focusedPane == .details ? .list : .details
                }
                .buttonStyle(.borderless).keyboardShortcut("r", modifiers: .command)
                .help(focusedPane == .details ? "Choose another revision (⌘R)" : "Read and scroll the selected revision (⌘R)")
                .disabled(selected == nil)
            }
        }
        .padding(24).frame(minWidth: 720, idealWidth: 820, minHeight: 520, idealHeight: 600)
        .multilineTextAlignment(.leading)
        .onAppear { selection = entries.first?.id; focusedPane = .list }
        .onChange(of: entries.map(\.id)) {
            if !entries.contains(where: { $0.id == selection }) { selection = entries.first?.id }
        }
    }
}
