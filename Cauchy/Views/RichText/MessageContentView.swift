import SwiftUI

struct MessageContentView: View {
    let content: String
    var font: Font = .body
    var textColor: Color = .primary
    /// Results that exist in the open document. Empty leaves every citation as prose.
    var referenceKeys: Set<ReferenceKey> = []
    var referenceBlock: (DetectedReference) -> DocumentBlock? = { _ in nil }
    var onOpenReference: (DetectedReference) -> Void = { _ in }
    var onHoverReference: (DetectedReference) -> Void = { _ in }
    /// Assistant replies only. `[P1]` becomes a page chip, or disappears when
    /// there is no PDF location for that id.
    var interpretsSourceMarkers: Bool = false
    var sourceAnchors: [AnswerSourceAnchor] = []
    var onOpenSource: (AnswerSourceAnchor) -> Void = { _ in }

    private enum MarkerToken {
        case segment(MessageSegment)
        case chip(AnswerSourceMarkers.Chip)
    }

    var body: some View {
        let parsed = MessageRenderCache.parsed(for: content)
        if !parsed.needsRichRendering {
            linkedOrPlain(content)
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
            linkedOrPlain(value)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .displayMath(let latex):
            MathSegmentView(latex: latex, mode: .display, fontSize: 17, textColor: textColor)
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
                linkedOrPlain(value)
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
                MathSegmentView(latex: latex, mode: .inline, fontSize: 15, textColor: textColor)
                    .frame(maxWidth: .infinity, alignment: .leading)
            case .displayMath(let latex):
                MathSegmentView(latex: latex, mode: .display, fontSize: 17, textColor: textColor)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        } else if let mergedText = mergedText(from: merged) {
            linkedOrPlain(mergedText)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            let flowTokens = flowTokensKeepingCitations(merged)
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

    /// Word-splits prose but keeps "Theorem 3.2" in one token so it can be linked.
    private func flowTokensKeepingCitations(_ segments: [MessageSegment]) -> [MessageSegment] {
        segments.flatMap { segment -> [MessageSegment] in
            guard case .text(let value) = segment else {
                return MessageContentParser.flowTokens(from: [segment])
            }
            let matches = AssistantResponseValidator.linkableReferences(in: value, known: referenceKeys)
            guard !matches.isEmpty else {
                return MessageContentParser.flowTokens(from: [segment])
            }
            var tokens: [MessageSegment] = []
            var cursor = value.startIndex
            for match in matches {
                if cursor < match.range.lowerBound {
                    let prefix = String(value[cursor..<match.range.lowerBound])
                    tokens.append(contentsOf: MessageContentParser.flowTokens(from: [.text(prefix)]))
                }
                tokens.append(.text(String(value[match.range])))
                cursor = match.range.upperBound
            }
            if cursor < value.endIndex {
                tokens.append(contentsOf: MessageContentParser.flowTokens(from: [.text(String(value[cursor...]))]))
            }
            return tokens
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
            linkedOrPlain(value, wraps: false)
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
            Text(value)
                .font(.system(.body, design: .monospaced))
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(Color.secondary.opacity(0.2))
                .cornerRadius(4)
                .foregroundStyle(textColor)
                .textSelection(.enabled)
                .fixedSize(horizontal: true, vertical: true)
        case .inlineMath(let latex):
            MathSegmentView(latex: latex, mode: .inline, fontSize: 15, textColor: textColor)
        case .displayMath(let latex):
            MathSegmentView(latex: latex, mode: .display, fontSize: 17, textColor: textColor)
        }
    }

    @ViewBuilder
    private func linkedOrPlain(_ value: String, wraps: Bool = true) -> some View {
        // Word tokens inside a chip row must not be trimmed again. Only a
        // string that still contains a marker bracket is rewritten here.
        if interpretsSourceMarkers, value.contains("[") {
            let runs = AnswerSourceMarkers.runs(in: value, anchors: sourceAnchors)
            let hasChip = runs.contains { if case .chip = $0 { true } else { false } }
            if hasChip {
                markerFlow(runs)
            } else {
                linkedOrPlainBody(AnswerSourceMarkers.strippingMarkers(from: value), wraps: wraps)
            }
        } else {
            linkedOrPlainBody(value, wraps: wraps)
        }
    }

    private func markerTokens(_ runs: [AnswerSourceMarkers.Run]) -> [MarkerToken] {
        runs.flatMap { run -> [MarkerToken] in
            switch run {
            case .text(let value):
                return flowTokensKeepingCitations([.text(value)]).map { .segment($0) }
            case .chip(let chip):
                return [.chip(chip)]
            }
        }
    }

    @ViewBuilder
    private func markerFlow(_ runs: [AnswerSourceMarkers.Run]) -> some View {
        let tokens = markerTokens(runs)
        // Word tokens already carry their trailing space. A non-zero gap would
        // double it; the chip's own padding separates it from the words.
        InlineFlowLayout(horizontalSpacing: 0, verticalSpacing: 2) {
            ForEach(Array(tokens.enumerated()), id: \.offset) { _, token in
                switch token {
                case .segment(let segment):
                    // linkedOrPlain would call back into this flow and make the
                    // view's return type refer to itself. Markers are already split out.
                    markerSegment(segment)
                case .chip(let chip):
                    if let anchor = sourceAnchors.first(where: { $0.sourceID?.uppercased() == chip.sourceID }) {
                        Button {
                            onOpenSource(anchor)
                        } label: {
                            Text(chip.pageLabel)
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.accentColor.opacity(0.15), in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .fixedSize()
                        .help("Open PDF page \(anchor.pageIndex + 1)")
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func markerSegment(_ segment: MessageSegment) -> some View {
        switch segment {
        case .text(let value):
            linkedOrPlainBody(value, wraps: false)
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
            Text(value)
                .font(.system(.body, design: .monospaced))
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(Color.secondary.opacity(0.2))
                .cornerRadius(4)
                .foregroundStyle(textColor)
                .textSelection(.enabled)
                .fixedSize(horizontal: true, vertical: true)
        case .inlineMath(let latex):
            MathSegmentView(latex: latex, mode: .inline, fontSize: 15, textColor: textColor)
        case .displayMath(let latex):
            MathSegmentView(latex: latex, mode: .display, fontSize: 17, textColor: textColor)
        }
    }

    @ViewBuilder
    private func linkedOrPlainBody(_ value: String, wraps: Bool = true) -> some View {
        if referenceKeys.isEmpty || AssistantResponseValidator.linkableReferences(in: value, known: referenceKeys).isEmpty {
            if wraps {
                plainText(value)
            } else {
                Text(value)
                    .font(font)
                    .foregroundStyle(textColor)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: true, vertical: true)
            }
        } else {
            ReferenceLinkedText(
                text: value,
                font: font,
                textColor: textColor,
                knownKeys: referenceKeys,
                blockForReference: referenceBlock,
                onOpen: onOpenReference,
                onHover: onHoverReference
            )
        }
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
        Text(value)
            .font(.system(.body, design: .monospaced))
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .background(Color.secondary.opacity(0.2))
            .cornerRadius(4)
            .foregroundStyle(textColor)
            .textSelection(.enabled)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
    }
}
