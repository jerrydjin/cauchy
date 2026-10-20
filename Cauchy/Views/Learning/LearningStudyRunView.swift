import SwiftUI

struct LearningStudyRunPlanView: View {
    @Bindable var document: LearningDocument
    @Environment(\.dismiss) private var dismiss
    @State private var count = 2
    @State private var selectedRequirement: (index: Int, item: LearningStudyRun.Item)?
    @FocusState private var focusedRequirementID: UUID?
    @FocusState private var requirementDetailsFocused: Bool
    @State private var requirementScroll = ScrollPosition()
    @State private var requirementScrollOffset: CGFloat = 0
    private var plan: LearningStudyRun? {
        document.studyMap.map.flatMap { LearningStudyRun.plan(map: $0, sessions: document.learning.sessions, count: count, now: Date()) }
    }

    var body: some View {
        Group {
            if let selection = selectedRequirement {
                requirementDetails(selection.item, index: selection.index)
            } else {
                preview
            }
        }.padding(24).frame(width: 480)
    }

    private var preview: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text("Plan a study session").font(.title2.weight(.semibold))
            Picker("Requirements", selection: $count) {
                Text("Up to 2").tag(2)
                Text("Up to 3").tag(3)
            }.pickerStyle(.segmented)
            if let plan {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(Array(plan.items.enumerated()), id: \.element.target.id) { index, item in
                        HStack(alignment: .top, spacing: 12) {
                            Text("\(index + 1)").font(.callout.monospacedDigit()).foregroundStyle(.secondary)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.title).font(.headline).lineLimit(2)
                                Text(item.mode == .delayedReview ? "Delayed check · \(item.target.kind.label)" : item.target.kind.label)
                                    .font(.caption).foregroundStyle(.secondary)
                                Text(item.target.objective).font(.callout).lineLimit(3)
                            }.frame(maxWidth: .infinity, alignment: .leading)
                            Button("Read full requirement \(index + 1)", systemImage: "info.circle") {
                                selectedRequirement = (index, item)
                            }
                            .labelStyle(.iconOnly).buttonStyle(.borderless)
                            .focusable().focused($focusedRequirementID, equals: item.target.id)
                            .onKeyPress(keys: [.space], phases: .down) { key in
                                guard key.modifiers.isEmpty else { return .ignored }
                                selectedRequirement = (index, item)
                                return .handled
                            }
                            .help("Read the full title and learning goal")
                        }
                    }
                }
                Text("Stop after \(plan.items.count) \(plan.items.count == 1 ? "requirement" : "requirements"), or pause whenever you need.")
                    .font(.callout).foregroundStyle(.secondary)
                DisclosureGroup("Why this order?") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("A due check comes first. New work follows your learning path: concept, proof, then application. Each requirement keeps its complete lesson and argument.")
                        Text("Open source issues and earlier requirements stay in the path. Unfinished work remains open when you stop.")
                    }.font(.callout).foregroundStyle(.secondary).padding(.top, 8)
                }
            } else {
                Text("No requirements are available to plan right now.").foregroundStyle(.secondary)
            }
            HStack {
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Start session") {
                    guard let plan else { return }
                    dismiss()
                    document.beginStudyRun(plan)
                }
                .buttonStyle(.glassProminent).keyboardShortcut(.defaultAction)
                .disabled(plan == nil || document.isBusy)
            }
        }
    }

    private func requirementDetails(_ item: LearningStudyRun.Item, index: Int) -> some View {
        VStack(alignment: .leading, spacing: 22) {
            Text("Requirement \(index + 1)").font(.title2.weight(.semibold))
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text(item.title).font(.headline)
                    Text(item.mode == .delayedReview ? "Delayed check · \(item.target.kind.label)" : item.target.kind.label)
                        .font(.caption).foregroundStyle(.secondary)
                    Text(item.target.objective).font(.body).textSelection(.enabled)
                }
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: 320).scrollIndicators(.visible)
            .scrollPosition($requirementScroll)
            .onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.y } action: { _, offset in
                requirementScrollOffset = offset
            }
            .focusable().focused($requirementDetailsFocused)
            .onAppear {
                requirementDetailsFocused = true
                requirementScroll.scrollTo(edge: .top)
            }
            .onKeyPress(keys: [.upArrow, .downArrow, .space, .pageUp, .pageDown, .home, .end], phases: [.down, .repeat]) { key in
                guard key.modifiers.isEmpty || (key.key == .space && key.modifiers == .shift) else { return .ignored }
                switch key.key {
                case .home: requirementScroll.scrollTo(edge: .top)
                case .end: requirementScroll.scrollTo(edge: .bottom)
                default:
                    let backwards = key.key == .upArrow || key.key == .pageUp || key.modifiers.contains(.shift)
                    let distance: CGFloat = key.key == .upArrow || key.key == .downArrow ? 40 : 280
                    requirementScroll.scrollTo(y: max(0, requirementScrollOffset + (backwards ? -distance : distance)))
                }
                return .handled
            }
            Button("Back to plan", systemImage: "arrow.left") {
                selectedRequirement = nil
                focusedRequirementID = item.target.id
            }
            .buttonStyle(.glass).keyboardShortcut(.cancelAction)
        }
    }
}

struct LearningStudyRunCard: View {
    @Bindable var document: LearningDocument
    let run: LearningStudyRun
    let map: LearningStudyMap
    let assistantAvailable: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if run.state == .finished {
                Text("Study session finished").font(.title2.weight(.semibold))
                Text("\(run.attemptedCount) \(run.attemptedCount == 1 ? "exit check" : "exit checks") recorded · \(run.items.count) \(run.items.count == 1 ? "requirement" : "requirements") planned")
                    .font(.callout).foregroundStyle(.secondary)
                DisclosureGroup("Session record") {
                    LearningStudyRunRecord(run: run).padding(.top, 10)
                }
                Button("Back to learning path", systemImage: "arrow.right") {
                    document.studyMap.updateStudyRun(run.id) { $0.summaryAcknowledgedAt = Date() }
                }
                .buttonStyle(.glassProminent).controlSize(.large)
                .keyboardShortcut(.return, modifiers: .command).disabled(document.isBusy)
            } else if let item = run.currentItem {
                Text(run.state == .paused ? "Your study session is paused" : "Your study session")
                    .font(.title2.weight(.semibold))
                Text("\((run.currentIndex ?? 0) + 1) of \(run.items.count) · \(item.target.kind.label)")
                    .font(.caption).foregroundStyle(.secondary)
                Text(item.title).font(.headline).lineLimit(2).accessibilityLabel(item.title)
                DisclosureGroup("Requirement details") {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(item.title).font(.subheadline.weight(.medium))
                        Text(item.target.objective).font(.body)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 8)
                }
                if let blocker = run.blocker(in: map, sessions: document.learning.sessions) {
                    Text(blocker.message).font(.callout).foregroundStyle(.secondary)
                    switch blocker {
                    case .sourceReview:
                        continueButton("Review source", symbol: "doc.text.magnifyingglass", needsAssistant: false)
                    case .earlierRequirement:
                        continueButton("Open earlier requirement", symbol: "arrow.left", needsAssistant: true)
                    case .changedSource, .changedRequirement:
                        finishButton(prominent: true)
                    }
                    if case .sourceReview = blocker { finishButton(prominent: false) }
                    if case .earlierRequirement = blocker { finishButton(prominent: false) }
                } else {
                    continueButton(run.state == .paused ? "Resume session" : "Continue session", symbol: "arrow.right",
                        needsAssistant: item.session(in: document.learning.sessions) == nil)
                    finishButton(prominent: false)
                }
            }
        }
    }

    private func continueButton(_ title: String, symbol: String, needsAssistant: Bool) -> some View {
        Button(title, systemImage: symbol) { document.continueStudyRun() }
            .buttonStyle(.glassProminent).controlSize(.large)
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(document.isBusy || (needsAssistant && !assistantAvailable))
    }

    @ViewBuilder private func finishButton(prominent: Bool) -> some View {
        if prominent {
            Button("Finish session") { document.finishStudyRun() }
                .buttonStyle(.glassProminent).controlSize(.large)
                .keyboardShortcut(.return, modifiers: .command).disabled(document.studyMap.isBusy)
        } else {
            Button("Finish session here") { document.finishStudyRun() }
                .buttonStyle(.borderless).disabled(document.studyMap.isBusy)
        }
    }

}

struct LearningStudyRunRecord: View {
    let run: LearningStudyRun

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(run.items) { item in
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(item.title) · \(item.target.kind.label)").font(.subheadline.weight(.medium))
                    Text(result(item)).font(.callout).foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func result(_ item: LearningStudyRun.Item) -> String {
        guard let outcome = item.outcome else { return "No new exit check · requirement left open" }
        let work = item.mode == .delayedReview ? "Delayed check" : "Exit check"
        if outcome.independentCorrect { return "\(work) · correct without help" }
        let grade: String = switch outcome.grade {
        case .correct: "correct"
        case .partial: "partially correct"
        case .incorrect: "needs more practice"
        case .uncertain: "assessment inconclusive"
        }
        if outcome.assistanceUsed { return "\(work) · \(grade) with help · requirement left open" }
        return "\(work) · \(grade) · requirement left open"
    }
}
