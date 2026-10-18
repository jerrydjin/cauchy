import SwiftUI

/// Renders prose with the document's own results as links. A number that is
/// not in the reference index stays plain text — see
/// `AssistantResponseValidator.linkableReferences`.
struct ReferenceLinkedText: View {
    let text: String
    var font: Font = .body
    var textColor: Color = .primary
    var knownKeys: Set<ReferenceKey>
    var blockForReference: (DetectedReference) -> DocumentBlock?
    var onOpen: (DetectedReference) -> Void
    var onHover: (DetectedReference) -> Void

    var body: some View {
        let matches = AssistantResponseValidator.linkableReferences(in: text, known: knownKeys)
        if matches.isEmpty {
            Text(text)
                .font(font)
                .foregroundStyle(textColor)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            WrappingReferenceText(
                lines: lines(matching: matches),
                font: font,
                textColor: textColor,
                blockForReference: blockForReference,
                onOpen: onOpen,
                onHover: onHover
            )
        }
    }

    private func pieces(matching matches: [DetectedReferenceMatch]) -> [ReferenceTextPiece] {
        var pieces: [ReferenceTextPiece] = []
        var cursor = text.startIndex
        for match in matches {
            if cursor < match.range.lowerBound {
                pieces.append(.text(String(text[cursor..<match.range.lowerBound])))
            }
            pieces.append(.reference(match.reference, String(text[match.range])))
            cursor = match.range.upperBound
        }
        if cursor < text.endIndex {
            pieces.append(.text(String(text[cursor...])))
        }
        return pieces
    }

    /// One flow row per source line so a citation in the middle of a paragraph
    /// still wraps with the words around it.
    private func lines(matching matches: [DetectedReferenceMatch]) -> [[ReferenceTextPiece]] {
        var lines: [[ReferenceTextPiece]] = [[]]
        for piece in pieces(matching: matches) {
            switch piece {
            case .reference:
                lines[lines.count - 1].append(piece)
            case .text(let value):
                let parts = value.split(separator: "\n", omittingEmptySubsequences: false)
                for (index, part) in parts.enumerated() {
                    if index > 0 { lines.append([]) }
                    lines[lines.count - 1].append(contentsOf: wordPieces(String(part)))
                }
            }
        }
        return lines.filter { !$0.isEmpty }
    }

    private func wordPieces(_ text: String) -> [ReferenceTextPiece] {
        guard !text.isEmpty else { return [] }
        var pieces: [ReferenceTextPiece] = []
        var index = text.startIndex
        while index < text.endIndex {
            if text[index].isWhitespace {
                let start = index
                while index < text.endIndex, text[index].isWhitespace {
                    index = text.index(after: index)
                }
                pieces.append(.text(String(text[start..<index])))
                continue
            }
            let start = index
            while index < text.endIndex, !text[index].isWhitespace {
                index = text.index(after: index)
            }
            pieces.append(.text(String(text[start..<index])))
        }
        return pieces
    }
}

enum ReferenceTextPiece: Identifiable {
    case text(String)
    case reference(DetectedReference, String)

    var id: String {
        switch self {
        case .text(let value):
            return "t:\(value)"
        case .reference(let reference, let label):
            return "r:\(reference.kind.rawValue):\(reference.number):\(label)"
        }
    }
}

/// Plain runs stay selectable paragraphs. Each cited result is a link with the
/// statement in a hover popover — the same preview the reference panel shows.
private struct WrappingReferenceText: View {
    let lines: [[ReferenceTextPiece]]
    var font: Font
    var textColor: Color
    var blockForReference: (DetectedReference) -> DocumentBlock?
    var onOpen: (DetectedReference) -> Void
    var onHover: (DetectedReference) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                InlineFlowLayout(horizontalSpacing: 0, verticalSpacing: 2) {
                    ForEach(Array(line.enumerated()), id: \.offset) { _, piece in
                        switch piece {
                        case .text(let value):
                            Text(value)
                                .font(font)
                                .foregroundStyle(textColor)
                                .textSelection(.enabled)
                                .fixedSize(horizontal: true, vertical: true)
                        case .reference(let reference, let label):
                            ReferenceLinkButton(
                                label: label,
                                font: font,
                                block: blockForReference(reference),
                                onOpen: { onOpen(reference) },
                                onHover: { onHover(reference) }
                            )
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ReferenceLinkButton: View {
    let label: String
    var font: Font
    var block: DocumentBlock?
    var onOpen: () -> Void
    var onHover: () -> Void

    @State private var showsPreview = false

    var body: some View {
        Button(action: onOpen) {
            Text(label)
                .font(font)
                .foregroundStyle(Color.accentColor)
                .underline()
                .fixedSize(horizontal: true, vertical: true)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            showsPreview = hovering && block != nil
            if hovering { onHover() }
        }
        .popover(isPresented: $showsPreview, arrowEdge: .bottom) {
            if let block {
                ReferenceCitationPreview(block: block)
            }
        }
        .help(block.map { "\($0.title) · p. \($0.pageIndex + 1)" } ?? label)
        .accessibilityLabel(block?.title ?? label)
        .accessibilityHint("Shows the statement. Click to jump to it in the document.")
    }
}

/// Compact form of the reference panel's statement, used as the hover preview
/// on a citation inside an answer.
private struct ReferenceCitationPreview: View {
    let block: DocumentBlock

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(block.title)
                .font(.headline)
            Text("p. \(block.pageIndex + 1)")
                .font(.caption)
                .foregroundStyle(.secondary)
            let body = previewBody
            if !body.isEmpty {
                Text(body)
                    .font(.callout)
                    .textSelection(.enabled)
                    .frame(maxWidth: 280, alignment: .leading)
            }
        }
        .padding(12)
        .frame(maxWidth: 320, alignment: .leading)
    }

    private var previewBody: String {
        let source = block.evidence?.sourceExcerpt.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !source.isEmpty { return source }
        return block.formattedBody.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
