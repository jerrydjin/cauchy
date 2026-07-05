import SwiftUI

struct HighlightRowView: View {
    let highlight: Highlight
    let isSelected: Bool
    var onSelect: () -> Void
    var onNavigate: () -> Void
    var onDelete: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "highlighter")
                .foregroundStyle(.yellow)
                .font(.caption)

            VStack(alignment: .leading, spacing: 2) {
                Text(highlight.label)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                Text("Page \(highlight.pageIndex + 1)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if !highlight.messages.isEmpty {
                Image(systemName: "bubble.left")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }

            Button(action: onNavigate) {
                Image(systemName: "arrow.right.circle")
            }
            .buttonStyle(.borderless)
            .help("Go to highlight")
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(isSelected ? Color.accentColor.opacity(0.12) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .contextMenu {
            Button("Go to Highlight", action: onNavigate)
            Divider()
            Button("Delete", role: .destructive, action: onDelete)
        }
    }
}
