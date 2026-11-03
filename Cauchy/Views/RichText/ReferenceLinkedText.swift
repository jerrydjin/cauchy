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

    private var citation: String {
        label.trimmingCharacters(in: .whitespaces)
    }

    private var trailingSpace: String {
        guard label.hasPrefix(citation) else { return "" }
        return String(label.dropFirst(citation.count))
    }

    var body: some View {
        Button(action: action) {
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                if !citation.isEmpty {
                    CitationLinkText.tinted(citation)
                }
                if !trailingSpace.isEmpty {
                    Text(trailingSpace)
                        .foregroundStyle(CitationChrome.tint)
                }
                if !suffix.isEmpty {
                    Text(suffix)
                        .foregroundStyle(textColor)
                }
            }
            .font(font)
            .fixedSize()
            .padding(.vertical, 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(reference.displayName)
        .help(reference.displayName)
    }
}

/// A page tag at the end of a claim, or one entry in the sources line.
/// The number comes first, then the arrow: "39 ↗", or "37–39 ↗" for a span.
/// The tint alone marks the link. The arrow is omitted for in-sentence
/// references.
struct PageTagButton: View {
    let chip: AnswerSourceMarkers.Chip
    var anchor: AnswerSourceAnchor?
    var onOpen: (AnswerSourceAnchor) -> Void
    var font: Font = .body
    var leadingPadding: CGFloat = 6

    var body: some View {
        Button {
            if let anchor { onOpen(anchor) }
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                CitationLinkText.tinted(chip.pageLabel)
                Text("↗")
                    .font(.system(size: 10, weight: .medium))
                    .baselineOffset(3)
                    .foregroundStyle(CitationChrome.tint)
                    .accessibilityHidden(true)
            }
            .font(font)
            .padding(.vertical, 3)
            .padding(.horizontal, 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.leading, leadingPadding)
        .fixedSize()
        .accessibilityLabel(CitationPageLabel.voiceOver(
            firstPageIndex: chip.pageIndex,
            lastPageIndex: chip.pageIndex
        ))
        .accessibilityAddTraits(.isLink)
        .help("Open the passage on page \(chip.pageIndex + 1)")
    }
}

/// Muted tint, with no underline. Punctuation stays outside this, and a
/// name that is not a jump target never reaches this style.
enum CitationLinkText {
    static func tinted(_ string: String) -> Text {
        var attributed = AttributedString(string)
        attributed.foregroundColor = CitationChrome.tint
        return Text(attributed)
    }
}
