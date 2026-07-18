import SwiftUI

struct ConversationComposer: View {
    @Binding var question: String
    var isResponding: Bool
    var isEnabled: Bool
    var onSend: () -> Void
    var onModelChange: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ModelPickerMenu(onChange: onModelChange)
                .padding(.leading, 2)

            HStack(alignment: .bottom, spacing: 8) {
                TextField("Ask a question…", text: $question, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...4)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .disabled(isResponding || !isEnabled)
                    .onSubmit(onSend)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .glassEffect(in: .rect(cornerRadius: ConversationChrome.composerCornerRadius))

                GlassIconButton(
                    systemName: "arrow.up",
                    accessibilityLabel: "Send",
                    prominent: canSend,
                    action: onSend
                )
                .disabled(!canSend)
            }
        }
    }

    private var canSend: Bool {
        !question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !isResponding
            && isEnabled
    }
}
