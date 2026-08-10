import SwiftUI

struct ConversationComposer: View {
    @Binding var question: String
    var isResponding: Bool
    var isEnabled: Bool
    var onSend: () -> Void
    var onStop: () -> Void = {}
    var onModelChange: () -> Void = {}

    var body: some View {
        // One bar: the question on top, the model selector tucked underneath it.
        // Return sends, so there is no send button.
        VStack(alignment: .leading, spacing: 6) {
            TextField("Ask a question…", text: $question, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...4)
                .disabled(isResponding || !isEnabled)
                .onSubmit(onSend)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 6) {
                ModelPicker(onChange: onModelChange)

                Spacer(minLength: 0)

                // A slow CLI provider can always be interrupted without waiting
                // it out — the only button the bar still needs.
                if isResponding {
                    Button(action: onStop) {
                        Image(systemName: "stop.fill")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .padding(5)
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Stop generating")
                    .help("Stop generating")
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .glassEffect(in: .rect(cornerRadius: ConversationChrome.composerCornerRadius))
    }
}
