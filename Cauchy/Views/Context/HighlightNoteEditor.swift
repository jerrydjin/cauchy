import SwiftUI

/// The reader's own note on a highlight — what they thought, as opposed to what
/// they asked the model. Saved on submit and whenever focus leaves, so a note
/// typed and then abandoned by clicking away is still there afterwards.
struct HighlightNoteEditor: View {
    @Bindable var workspace: WorkspaceViewModel
    let highlightID: UUID

    @State private var draft = ""
    @FocusState private var isFocused: Bool

    private var savedNote: String {
        workspace.highlightStore.highlights
            .first { $0.id == highlightID }?
            .note ?? ""
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "square.and.pencil")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .padding(.top, 3)
                .accessibilityHidden(true)

            TextField("Note to self", text: $draft, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.callout)
                .lineLimit(1...5)
                .focused($isFocused)
                .accessibilityLabel("Note on this highlight")
                .onSubmit { commit() }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .glassEffect(.regular, in: .rect(cornerRadius: 10))
        .task(id: highlightID) { draft = savedNote }
        .onChange(of: isFocused) { _, focused in
            if !focused { commit() }
        }
        .onDisappear { commit() }
    }

    private func commit() {
        guard draft != savedNote else { return }
        workspace.setNote(draft, for: highlightID)
    }
}
