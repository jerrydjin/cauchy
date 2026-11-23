import AppKit
import SwiftUI

/// An open arc that turns. `ProgressView` is an AppKit control, and
/// `ImageRenderer` paints a prohibited sign where it cannot draw one, so the
/// thread list and the designer panels share this shape. At the default size
/// it matches the caption preview beside it, in that line's secondary colour.
struct ArcSpinner: View {
    var diameter: CGFloat?

    @ScaledMetric(relativeTo: .caption) private var captionDiameter: CGFloat = 10

    private var side: CGFloat { diameter ?? captionDiameter }
    private var lineWidth: CGFloat { max(1.25, side * 0.12) }

    var body: some View {
        TimelineView(AnimationTimelineSchedule(minimumInterval: 1.0 / 30.0)) { context in
            let period = 0.8
            let turn = context.date.timeIntervalSinceReferenceDate
                .truncatingRemainder(dividingBy: period) / period
            Circle()
                .trim(from: 0.12, to: 0.72)
                .stroke(
                    .secondary,
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .frame(width: side, height: side)
                .rotationEffect(.degrees(turn * 360))
        }
        .accessibilityHidden(true)
    }
}

/// One thread per row: its name, the latest answer (or a spinner while that
/// answer is still arriving), and the page it lives on. Plain rows rather
/// than cards — a list of twenty glass panes is both noisy and against Apple's
/// advice on how many Liquid Glass effects to put on screen at once. The glass
/// in this panel is reserved for the controls above.
struct HighlightThreadRow: View {
    let highlight: Highlight
    var isAnswering: Bool
    var onOpen: () -> Void
    var onRetry: () -> Void
    var onRename: () -> Void
    var onRecolour: (HighlightColor) -> Void
    var onCopyMarkdown: () -> Void
    var onDelete: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Button(action: onOpen) {
                HStack(alignment: .top, spacing: 10) {
                    HighlightColorDot(color: highlight.color)
                        .padding(.top, 4)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(highlight.displayName)
                            .font(.body)
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .truncationMode(.tail)

                        statusLine
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if highlight.note?.isEmpty == false {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.tertiary)
                    .accessibilityLabel("Has a note")
                    .padding(.top, 4)
            }

            HStack(spacing: 3) {
                Image(systemName: "doc.text")
                    .font(.system(size: 10, weight: .medium))
                Text("\(highlight.pageIndex + 1)")
                    .font(.caption.monospacedDigit())
            }
            .foregroundStyle(.tertiary)
            .padding(.top, 4)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.primary.opacity(isHovering ? 0.07 : 0))
        }
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovering)
        .help(highlight.selectedText)
        .accessibilityLabel(accessibilityLabel)
        .contextMenu {
            Button("Rename with AI", action: onRename)
            HighlightColorMenu(current: highlight.color, onSelect: onRecolour)
            Divider()
            Button("Copy Passage") { copyPassage() }
            Button("Copy as Markdown", action: onCopyMarkdown)
            Divider()
            Button("Delete", role: .destructive, action: onDelete)
        }
    }

    /// The second line is the answer preview. While the reply is in flight
    /// that slot is a spinner; after a failure it is the retry control.
    @ViewBuilder
    private var statusLine: some View {
        if isAnswering {
            HStack(spacing: 6) {
                ArcSpinner()
                Text("Answering…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Answering")
        } else if let failure = highlight.askFailure, !failure.isEmpty {
            HStack(spacing: 8) {
                Text(failure)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Button(action: onRetry) {
                    Text("Retry")
                        .font(.caption)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 1)
                        .overlay {
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .strokeBorder(Color.secondary.opacity(0.55), lineWidth: 1)
                        }
                }
                .buttonStyle(.plain)
            }
        } else if let preview = highlight.answerPreview {
            Text(preview)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    /// VoiceOver reads the row as one thing: what the thread is called, where
    /// it is, and its colour — which is otherwise only a dot.
    private var accessibilityLabel: String {
        var parts = [highlight.displayName, "page \(highlight.pageIndex + 1)", highlight.color.displayName]
        if isAnswering {
            parts.append("answering")
        } else if highlight.askFailure?.isEmpty == false {
            parts.append("could not answer")
        }
        if highlight.note?.isEmpty == false {
            parts.append("has a note")
        }
        return parts.joined(separator: ", ")
    }

    private func copyPassage() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(highlight.selectedText, forType: .string)
    }
}
