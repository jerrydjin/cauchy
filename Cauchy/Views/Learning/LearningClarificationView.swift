import SwiftUI

struct LearningClarificationView: View {
    @Bindable var document: LearningDocument
    let context: LearningClarificationContext
    @Environment(\.dismiss) private var dismiss
    @FocusState private var questionFocused: Bool
    @State private var availability = ReadingAssistantFactory.availability
    @State private var showingContext = false
    private var learning: LearningViewModel { document.learning }
    private var exchanges: [LearningClarification] {
        (learning.session?.clarifications ?? []).filter { $0.context.id == context.id }
    }
    private var isCurrent: Bool { learning.session?.canAskClarification(for: context) == true }
    private var subject: String { context.attemptID != nil ? "feedback" : context.phase == .lesson ? "step" : "question" }
    private var draft: Binding<String> {
        Binding(get: { learning.clarificationDraft(for: context) },
                set: { learning.setClarificationDraft($0, for: context) })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Ask about this \(subject)").font(.headline)
                    Text(context.title).font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Return to \(context.attemptID != nil ? "feedback" : context.phase == .lesson ? "lesson" : "my answer")") {
                    learning.cancelClarification()
                    dismiss()
                }.keyboardShortcut(.cancelAction)
            }.padding(24)
            Divider()
            ScrollViewReader { scroll in
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        DisclosureGroup(context.attemptID != nil ? "Assessed answer and feedback" : "Current \(subject)", isExpanded: $showingContext) {
                            MessageContentView(content: context.content).padding(.top, 8)
                        }
                        if let latest = exchanges.last {
                            if exchanges.count > 1 {
                                DisclosureGroup("Earlier questions (\(exchanges.count - 1))") {
                                    ForEach(exchanges.dropLast()) { exchange in
                                        exchangeContent(exchange).padding(.top, 16)
                                    }
                                }
                            }
                            exchangeContent(latest).id(latest.id)
                        }
                        if let error = learning.clarificationErrorMessage {
                            Label(error, systemImage: "exclamationmark.circle")
                                .font(.callout).textSelection(.enabled)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading).padding(24)
                }
                .onChange(of: exchanges.last?.id) {
                    if let id = exchanges.last?.id { scroll.scrollTo(id, anchor: .top) }
                    showingContext = exchanges.isEmpty
                    questionFocused = true
                }
            }
            if isCurrent {
                Divider()
                VStack(alignment: .leading, spacing: 10) {
                    Text("Your question").font(.subheadline.weight(.medium))
                    TextEditor(text: draft)
                        .font(.body).scrollContentBackground(.hidden)
                        .frame(minHeight: 72, maxHeight: 120).padding(8)
                        .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color(nsColor: .separatorColor)))
                        .accessibilityLabel("Question about this \(context.attemptID != nil ? "feedback" : context.phase == .lesson ? "lesson step" : "problem")")
                        .focused($questionFocused).disabled(learning.isBusy)
                    if context.attemptID != nil {
                        Text("This discussion keeps your saved answer and assessment unchanged.")
                            .font(.caption).foregroundStyle(.secondary)
                    } else if context.phase != .lesson {
                        Text("Tutor replies here are recorded as help on this answer.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    HStack(spacing: 12) {
                        if learning.operation == .clarification {
                            ProgressView().controlSize(.small)
                            Text("Thinking about your question…").font(.callout)
                            Spacer()
                            Button("Cancel") { learning.cancelClarification(); questionFocused = true }
                        } else {
                            Button("Ask", systemImage: "arrow.up") {
                                questionFocused = false
                                learning.askClarification(for: context)
                            }
                            .buttonStyle(.glassProminent).keyboardShortcut(.return, modifiers: .command)
                            .disabled(learning.isBusy || (!document.isVerificationFixture && !availability.isAvailable)
                                      || draft.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            if !document.isVerificationFixture && !availability.isAvailable {
                                SettingsLink { Text("Choose an assistant") }
                            }
                            Spacer()
                            if draft.wrappedValue.count >= 1_800 {
                                Text("\(draft.wrappedValue.count.formatted()) / 2,000 characters")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }.padding(24)
            }
        }
        .frame(minWidth: 560, idealWidth: 680, minHeight: 480, idealHeight: exchanges.isEmpty ? 480 : 560)
        .onAppear { questionFocused = isCurrent; showingContext = exchanges.isEmpty }
        .onChange(of: learning.clarificationErrorMessage) {
            if learning.clarificationErrorMessage != nil { questionFocused = isCurrent }
        }
        .onReceive(NotificationCenter.default.publisher(for: .assistantPreferencesChanged)) { _ in
            availability = ReadingAssistantFactory.availability
        }
        .onDisappear { learning.cancelClarification() }
    }

    private func exchangeContent(_ exchange: LearningClarification) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(exchange.question).font(.headline).textSelection(.enabled)
            Text("Tutor explanation").font(.caption).foregroundStyle(.secondary)
            MessageContentView(content: exchange.reply.answer)
            if exchange.reply.basis != .suppliedNotes {
                Label(exchange.reply.basis.label, systemImage: exchange.reply.basis == .insufficientSource ? "doc.text.magnifyingglass" : "text.bubble")
                    .font(.caption).foregroundStyle(.secondary)
            }
            DisclosureGroup("Source details") {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Model-declared basis: \(exchange.reply.basis.label). Exact quotations locate the source; they do not verify the explanation.")
                        .font(.caption).foregroundStyle(.secondary)
                    ForEach(Array(exchange.reply.citations.enumerated()), id: \.offset) { _, citation in
                        VStack(alignment: .leading, spacing: 6) {
                            Button("PDF page \(citation.pageIndex + 1)") {
                                document.showNotes(at: citation.pageIndex)
                                dismiss()
                            }.buttonStyle(.borderless)
                            Text(citation.quote).font(.callout).textSelection(.enabled)
                            if let id = citation.correctionID {
                                Text("User-verified transcription · revision \(id.uuidString)")
                                    .font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                            }
                        }
                    }
                    Text("\(exchange.createdAt.formatted(date: .abbreviated, time: .shortened)) · \(exchange.modelID ?? exchange.providerID)")
                        .font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                    Text("Supplied PDF pages: \(exchange.suppliedPageIndices.map { String($0 + 1) }.joined(separator: ", ")). Earlier replies supplied: \(exchange.previousExchangeIDs.count).")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 8)
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}
