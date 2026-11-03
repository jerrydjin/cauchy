import SwiftUI

struct MessageContentView: View {
    let content: String
    var font: Font = .body
    var textColor: Color = .primary
    /// Chat keeps code and failed math in a monospace chip. The reference
    /// card turns this off so a broken span stays in the body font.
    var allowsMonospace = true
    /// Results that exist in the open document. Empty leaves every citation as prose.
    var referenceKeys: Set<ReferenceKey> = []
    var onOpenReference: (DetectedReference) -> Void = { _ in }
    /// Assistant replies only. `[R1]` becomes a page tag at the end of its claim.
    var interpretsSourceMarkers: Bool = false
    var sourceAnchors: [AnswerSourceAnchor] = []
    var onOpenSource: (AnswerSourceAnchor) -> Void = { _ in }

    private var usesCitationLayout: Bool {
        let hasLink = !referenceKeys.isEmpty
            && !AssistantResponseValidator.linkableReferences(in: content, known: referenceKeys).isEmpty
        let hasMarker = interpretsSourceMarkers && AnswerSourceMarkers.containsMarker(in: content)
        return hasLink || hasMarker
    }

    var body: some View {
        if usesCitationLayout {
            citedBody
        } else {
            classicBody
        }
    }

    @ViewBuilder
    private var classicBody: some View {
        let parsed = MessageRenderCache.parsed(for: content)
        if !parsed.needsRichRendering {
            plainText(content)
        } else {
            // Blocks are keyed by offset deliberately: content-derived IDs would
            // recreate every block view each time a streaming block grows.
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(parsed.blocks.enumerated()), id: \.offset) { _, block in
                    blockView(block)
                }
            }
        }
    }

    @ViewBuilder
    private func blockView(_ block: MessageBlock) -> some View {
        switch block {
        case .text(let value):
            plainText(value)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .displayMath(let latex):
            mathView(latex: latex, mode: .display, fontSize: 17)
                .frame(maxWidth: .infinity, alignment: .center)
        case .inlineLine(let segments):
            inlineLineView(segments)
        }
    }

    @ViewBuilder
    private func inlineLineView(_ segments: [MessageSegment]) -> some View {
        let merged = MessageContentParser.mergeAdjacentText(segments)

        if merged.count == 1 {
            switch merged[0] {
            case .text(let value):
                plainText(value)
                    .frame(maxWidth: .infinity, alignment: .leading)
            case .bold(let value):
                plainText(value).bold()
                    .frame(maxWidth: .infinity, alignment: .leading)
            case .italic(let value):
                plainText(value).italic()
                    .frame(maxWidth: .infinity, alignment: .leading)
            case .code(let value):
                codeText(value)
                    .frame(maxWidth: .infinity, alignment: .leading)
            case .inlineMath(let latex):
                mathView(latex: latex, mode: .inline, fontSize: 15)
                    .frame(maxWidth: .infinity, alignment: .leading)
            case .displayMath(let latex):
                mathView(latex: latex, mode: .display, fontSize: 17)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        } else if let mergedText = mergedText(from: merged) {
            plainText(mergedText)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            let flowTokens = MessageContentParser.flowTokens(from: merged)
            // Word tokens carry their own trailing space, so extra spacing
            // between them would render as a double space.
            InlineFlowLayout(horizontalSpacing: 0, verticalSpacing: 2) {
                ForEach(Array(flowTokens.enumerated()), id: \.offset) { _, segment in
                    flowSegmentView(segment)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func mergedText(from segments: [MessageSegment]) -> String? {
        guard !segments.isEmpty else { return nil }
        guard segments.allSatisfy({ if case .text = $0 { true } else { false } }) else { return nil }
        return segments.compactMap { if case .text(let value) = $0 { value } else { nil } }.joined()
    }

    @ViewBuilder
    private func flowSegmentView(_ segment: MessageSegment) -> some View {
        switch segment {
        case .text(let value):
            Text(value)
                .font(font)
                .foregroundStyle(textColor)
                .textSelection(.enabled)
                .fixedSize(horizontal: true, vertical: true)
        case .bold(let value):
            Text(value)
                .font(font)
                .bold()
                .foregroundStyle(textColor)
                .textSelection(.enabled)
                .fixedSize(horizontal: true, vertical: true)
        case .italic(let value):
            Text(value)
                .font(font)
                .italic()
                .foregroundStyle(textColor)
                .textSelection(.enabled)
                .fixedSize(horizontal: true, vertical: true)
        case .code(let value):
            codeLabel(value, fixedWidth: true)
        case .inlineMath(let latex):
            mathView(latex: latex, mode: .inline, fontSize: 15)
        case .displayMath(let latex):
            mathView(latex: latex, mode: .display, fontSize: 17)
        }
    }

    private func mathView(latex: String, mode: MathSegmentView.Mode, fontSize: CGFloat) -> MathSegmentView {
        MathSegmentView(
            latex: latex,
            mode: mode,
            fontSize: fontSize,
            textColor: textColor,
            fallbackFont: allowsMonospace ? .system(.callout, design: .monospaced) : font
        )
    }

    private func plainText(_ value: String) -> some View {
        Text(value)
            .font(font)
            .foregroundStyle(textColor)
            .textSelection(.enabled)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func codeText(_ value: String) -> some View {
        codeLabel(value, fixedWidth: false)
    }

    @ViewBuilder
    private func codeLabel(_ value: String, fixedWidth: Bool) -> some View {
        let label = Text(value)
            .font(allowsMonospace ? .system(.body, design: .monospaced) : font)
            .foregroundStyle(textColor)
            .textSelection(.enabled)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: fixedWidth, vertical: true)
        if allowsMonospace {
            label
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(Color.secondary.opacity(0.2))
                .cornerRadius(4)
        } else {
            label
        }
    }

    private var citedBody: some View {
        let lines = AnswerCitationLayout.claimLines(
            in: content,
            anchors: interpretsSourceMarkers ? sourceAnchors : []
        )
        return VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                claimRow(line)
            }
        }
    }

    @ViewBuilder
    private func claimRow(_ line: AnswerCitationLayout.ClaimLine) -> some View {
        let parsed = MessageRenderCache.parsed(for: line.text)
        if !parsed.needsRichRendering {
            ReferenceLinkedText(
                text: line.text,
                font: font,
                textColor: textColor,
                knownKeys: referenceKeys,
                chips: line.chips,
                sourceAnchors: sourceAnchors,
                onOpenReference: onOpenReference,
                onOpenSource: onOpenSource
            )
        } else {
            let lastTextual = parsed.blocks.lastIndex { block in
                if case .displayMath = block { return false }
                return true
            }
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(parsed.blocks.enumerated()), id: \.offset) { index, block in
                    citedBlock(block, chips: index == lastTextual ? line.chips : [])
                }
                if lastTextual == nil, !line.chips.isEmpty {
                    chipRow(line.chips)
                }
            }
        }
    }

    @ViewBuilder
    private func citedBlock(_ block: MessageBlock, chips: [AnswerSourceMarkers.Chip]) -> some View {
        switch block {
        case .text(let value):
            ReferenceLinkedText(
                text: value,
                font: font,
                textColor: textColor,
                knownKeys: referenceKeys,
                chips: chips,
                sourceAnchors: sourceAnchors,
                onOpenReference: onOpenReference,
                onOpenSource: onOpenSource
            )
        case .displayMath(let latex):
            mathView(latex: latex, mode: .display, fontSize: 17)
                .frame(maxWidth: .infinity, alignment: .center)
        case .inlineLine(let segments):
            citedInlineLine(segments, chips: chips)
        }
    }

    private func citedInlineLine(_ segments: [MessageSegment], chips: [AnswerSourceMarkers.Chip]) -> some View {
        let merged = MessageContentParser.mergeAdjacentText(segments)
        let tokens = citedTokens(from: merged)
        return InlineFlowLayout(horizontalSpacing: 0, verticalSpacing: 2) {
            ForEach(Array(tokens.enumerated()), id: \.offset) { _, token in
                citedTokenView(token)
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

    private enum CitedToken {
        case text(String)
        case link(String, String, DetectedReference)
        case segment(MessageSegment)
    }

    private func citedTokens(from segments: [MessageSegment]) -> [CitedToken] {
        segments.flatMap { segment -> [CitedToken] in
            guard case .text(let value) = segment else { return [.segment(segment)] }
            let matches = AssistantResponseValidator.linkableReferences(in: value, known: referenceKeys)
            return InlineReferenceFlow.pieces(in: value, matches: matches).map { piece in
                switch piece {
                case .text(let text): return .text(text)
                case .link(let label, let suffix, let reference): return .link(label, suffix, reference)
                }
            }
        }
    }

    @ViewBuilder
    private func citedTokenView(_ token: CitedToken) -> some View {
        switch token {
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
        case .segment(let segment):
            switch segment {
            case .bold(let value):
                Text(value).font(font).bold().foregroundStyle(textColor)
                    .fixedSize(horizontal: true, vertical: true)
            case .italic(let value):
                Text(value).font(font).italic().foregroundStyle(textColor)
                    .fixedSize(horizontal: true, vertical: true)
            case .code(let value):
                codeLabel(value, fixedWidth: true)
            case .inlineMath(let latex):
                mathView(latex: latex, mode: .inline, fontSize: 15)
            case .displayMath(let latex):
                mathView(latex: latex, mode: .display, fontSize: 17)
            case .text:
                EmptyView()
            }
        }
    }

    private func chipRow(_ chips: [AnswerSourceMarkers.Chip]) -> some View {
        HStack(spacing: 6) {
            ForEach(Array(chips.enumerated()), id: \.offset) { _, chip in
                PageTagButton(
                    chip: chip,
                    anchor: sourceAnchors.first { $0.sourceID?.uppercased() == chip.sourceID },
                    onOpen: onOpenSource
                )
            }
        }
    }
}
