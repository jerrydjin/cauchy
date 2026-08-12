import SwiftUI

struct ReadingBlockCard: View {
    let block: DocumentBlock
    let displayBody: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if block.reference.kind != .equation {
                Text(block.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            MessageContentView(content: displayBody, font: .body)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .background(ContentSurface.bubble, in: RoundedRectangle(cornerRadius: 12))
    }
}
