import SwiftUI
import UniformTypeIdentifiers

enum AskAvailabilityMessage {
    static func text(for availability: ReadingAssistantAvailability) -> String? {
        guard !availability.isAvailable else { return nil }
        switch availability {
        case .deviceNotEligible:
            return "Apple Intelligence is not supported on this Mac."
        case .intelligenceNotEnabled:
            return "Enable Apple Intelligence in System Settings to ask questions."
        case .modelNotReady:
            return "The on-device model is downloading. Try again soon."
        case .apiKeyMissing(let provider):
            return "Add your \(provider.vendor) API key in Settings to ask questions."
        case .cliNotInstalled(let provider):
            return "\(provider.connector.name) is not set up. \(provider.connector.setupHint)"
        default:
            return "Ask is unavailable right now."
        }
    }
}

struct ConversationComposer: View {
    @Binding var question: String
    var isResponding: Bool
    var isEnabled: Bool
    var highlightTag: String?
    var sheetTag: String?
    var onSend: () -> Void
    var onStop: () -> Void = {}
    var onModelChange: () -> Void = {}
    var onRemoveHighlight: () -> Void = {}
    var onRemoveSheet: () -> Void = {}
    var onAttach: () -> Void = {}
    var onDropProviders: ([NSItemProvider]) -> Void = { _ in }

    @State private var isDropTargeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if highlightTag != nil || sheetTag != nil {
                AskContextTags(
                    highlightTag: highlightTag,
                    sheetTag: sheetTag,
                    onRemoveHighlight: onRemoveHighlight,
                    onRemoveSheet: onRemoveSheet
                )
            }

            // One bar: the question on top, the model selector tucked underneath it.
            // Return sends, so there is no send button.
            composerBar
        }
    }

    private var composerBar: some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField("Ask a question…", text: $question, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...4)
                .disabled(isResponding || !isEnabled)
                .onSubmit(onSend)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 6) {
                ModelPicker(onChange: onModelChange)

                Button(action: onAttach) {
                    Image(systemName: "paperclip")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .disabled(!isEnabled || isResponding)
                .accessibilityLabel("Attach problem sheet")
                .help("Attach a problem sheet PDF or a screenshot")

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
        .overlay {
            if isDropTargeted {
                RoundedRectangle(cornerRadius: ConversationChrome.composerCornerRadius)
                    .strokeBorder(Color.accentColor, lineWidth: 1.5)
            }
        }
        .onDrop(of: [.fileURL, .pdf, .image], isTargeted: $isDropTargeted) { providers in
            guard isEnabled else { return false }
            onDropProviders(providers)
            return true
        }
    }
}

/// Small removable chips above the ask box. No chip means the question is
/// about the whole document.
private struct AskContextTags: View {
    var highlightTag: String?
    var sheetTag: String?
    var onRemoveHighlight: () -> Void
    var onRemoveSheet: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            if let highlightTag {
                AskTag(title: highlightTag, systemImage: "highlighter", onRemove: onRemoveHighlight)
            }
            if let sheetTag {
                AskTag(title: sheetTag, systemImage: "doc", onRemove: onRemoveSheet)
            }
            Spacer(minLength: 0)
        }
    }
}

private struct AskTag: View {
    let title: String
    let systemImage: String
    var onRemove: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: systemImage)
                .font(.system(size: 9, weight: .semibold))
            Text(title)
                .lineLimit(1)
                .truncationMode(.middle)
            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove \(title)")
        }
        .font(.caption2)
        .foregroundStyle(.primary)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.secondary.opacity(0.15), in: Capsule())
        .help(title)
    }
}
