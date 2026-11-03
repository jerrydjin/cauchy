import SwiftUI

extension CitationChrome {
    static var tint: Color { Color.accentColor.opacity(tintOpacity) }
    static var wash: Color { Color.accentColor.opacity(washOpacity) }
}

/// Prose with the document's own results as quiet inline links. Words of a
/// citation wrap with the sentence; the comma after one stays on its last word.
struct ReferenceLinkedText: View {
    let text: String
    var font: Font = .body
    var textColor: Color = .primary
    var knownKeys: Set<ReferenceKey> = []
    var chips: [AnswerSourceMarkers.Chip] = []
    var sourceAnchors: [AnswerSourceAnchor] = []
    var onOpenReference: (DetectedReference) -> Void = { _ in }
    var onOpenSource: (AnswerSourceAnchor) -> Void = { _ in }

    var body: some View {
        let matches = AssistantResponseValidator.linkableReferences(in: text, known: knownKeys)
        let pieces = InlineReferenceFlow.pieces(in: text, matches: matches)
        InlineFlowLayout(horizontalSpacing: 0, verticalSpacing: 2) {
            ForEach(Array(pieces.enumerated()), id: \.offset) { _, piece in
                pieceView(piece)
            }
            ForEach(Array(chips.enumerated()), id: \.offset) { _, chip in
                PageTagButton(
                    chip: chip,
                    anchor: sourceAnchors.first { $0.sourceID?.uppercased() == chip.sourceID },
                    onOpen: onOpenSource
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func pieceView(_ piece: InlineReferenceFlow.Piece) -> some View {
        switch piece {
        case .text(let value):
            Text(value)
                .font(font)
                .foregroundStyle(textColor)
                .textSelection(.enabled)
                .fixedSize(horizontal: true, vertical: true)
        case .link(let label, let suffix, let reference):
            InlineReferenceLink(
                label: label,
                suffix: suffix,
                font: font,
                textColor: textColor,
                reference: reference,
                action: { onOpenReference(reference) }
            )
        }
    }
}

/// The citation and the punctuation that follows it are one unbreakable
/// token, so the comma cannot wrap onto its own line. Only the citation
/// takes the link tint.
struct InlineReferenceLink: View {
    var label: String
    var suffix: String = ""
    var font: Font = .body
    var textColor: Color = .primary
    var reference: DetectedReference
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 0) {
                if !label.isEmpty {
                    Text(label)
                        .foregroundStyle(CitationChrome.tint)
                }
                if !suffix.isEmpty {
                    Text(suffix)
                        .foregroundStyle(textColor)
                }
            }
            .font(font)
            .fixedSize()
        }
        .buttonStyle(.plain)
        .accessibilityLabel(reference.displayName)
        .help(reference.displayName)
    }
}

/// The page tag at the end of a claim. Same quiet tint as the inline links.
struct PageTagButton: View {
    let chip: AnswerSourceMarkers.Chip
    var anchor: AnswerSourceAnchor?
    var onOpen: (AnswerSourceAnchor) -> Void

    var body: some View {
        Button {
            if let anchor { onOpen(anchor) }
        } label: {
            Text(chip.pageLabel)
                .font(.caption)
                .foregroundStyle(CitationChrome.tint)
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(CitationChrome.tint.opacity(0.16), in: Capsule())
        }
        .buttonStyle(.plain)
        .padding(.leading, 6)
        .fixedSize()
        .accessibilityLabel("Page \(chip.pageIndex + 1)")
        .help("Open the passage on page \(chip.pageIndex + 1)")
    }
}
