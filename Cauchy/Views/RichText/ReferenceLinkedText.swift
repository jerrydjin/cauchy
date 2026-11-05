import AppKit
import SwiftUI

extension CitationChrome {
    static var tint: Color { Color(red: linkRed, green: linkGreen, blue: linkBlue) }
    static var wash: Color { Color.accentColor.opacity(washOpacity) }
}

/// Prose with the document's own results as quiet inline links. A labelled
/// reference is one run. The comma after it stays on that run, in the body colour.
struct ReferenceLinkedText: View {
    let text: String
    var font: Font = .body
    var textColor: Color = .primary
    var knownKeys: Set<ReferenceKey> = []
    var chips: [AnswerSourceMarkers.Chip] = []
    var sourceAnchors: [AnswerSourceAnchor] = []
    /// The designer snapshot draws the hover underline. Live hover uses the pointer.
    var linkShowsHover = false
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
                showsHover: linkShowsHover,
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
    /// Draws the hover underline without a pointer. Snapshots set this.
    var showsHover = false
    var reference: DetectedReference
    var action: () -> Void

    private var citation: String {
        label.trimmingCharacters(in: .whitespaces)
    }

    private var trailingSpace: String {
        guard label.hasPrefix(citation) else { return "" }
        return String(label.dropFirst(citation.count))
    }

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                if !citation.isEmpty {
                    CitationLinkText.tinted(citation, underlined: isHovered || showsHover)
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
        .citationLinkHover($isHovered)
        .accessibilityLabel(reference.displayName)
        .help(reference.displayName)
    }
}

/// A page tag at the end of a claim, or one entry in the sources line.
/// The number comes first, then the arrow: "39 ↗", or "37–39 ↗" for a span.
/// The tint alone marks the link at rest. Hover underlines the number
/// and shows the pointing hand. The arrow is omitted for in-sentence
/// references.
struct PageTagButton: View {
    let chip: AnswerSourceMarkers.Chip
    var anchor: AnswerSourceAnchor?
    var onOpen: (AnswerSourceAnchor) -> Void
    var font: Font = .body
    var leadingPadding: CGFloat = 6

    @State private var isHovered = false

    var body: some View {
        Button {
            if let anchor { onOpen(anchor) }
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                CitationLinkText.tinted(chip.pageLabel, underlined: isHovered)
                Text(Image(systemName: "arrow.up.right"))
                    .font(font)
                    .foregroundStyle(CitationChrome.tint)
                    .accessibilityHidden(true)
            }
            .font(font)
            .padding(.vertical, 3)
            .padding(.horizontal, 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .citationLinkHover($isHovered)
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

/// Muted tint. At rest there is no underline. Hover may underline the
/// link text only; punctuation stays outside this, and a name that is not
/// a jump target never reaches this style.
enum CitationLinkText {
    static func tinted(_ string: String, underlined: Bool = false) -> Text {
        var attributed = AttributedString(string)
        attributed.foregroundColor = CitationChrome.tint
        if underlined {
            attributed.underlineStyle = Text.LineStyle(
                pattern: .solid,
                color: CitationChrome.tint
            )
        }
        return Text(attributed)
    }
}

/// Hover for a reader-chat link: a solid underline, drawn by the caller,
/// and the pointing-hand cursor. The resting view is unchanged.
struct CitationLinkHover: ViewModifier {
    @Binding var isHovered: Bool

    func body(content: Content) -> some View {
        content
            .onHover { hovering in
                if isHovered != hovering {
                    isHovered = hovering
                }
                if hovering {
                    NSCursor.pointingHand.set()
                } else {
                    NSCursor.arrow.set()
                }
            }
            .modifier(CitationPointerStyle())
    }
}

extension View {
    func citationLinkHover(_ isHovered: Binding<Bool>) -> some View {
        modifier(CitationLinkHover(isHovered: isHovered))
    }
}

/// `pointerStyle` is the system pointing hand. The snapshot tool still
/// builds for macOS 14, where that modifier does not exist; the cursor
/// there comes from `NSCursor.pointingHand` in the hover handler.
private struct CitationPointerStyle: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 15.0, *) {
            content.pointerStyle(.link)
        } else {
            content
        }
    }
}
