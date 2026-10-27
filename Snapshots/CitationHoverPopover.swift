import SwiftUI

/// Plain bibliography hover. The reader shows this string in the system tooltip.
/// A title that needs math uses `ReferenceHoverLabel` instead (see
/// `reference-hover-statement-math.png`); this target is compiled without SwiftMath.
struct CitationHoverPopover: View {
    var text: String

    var body: some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(.primary)
            .multilineTextAlignment(.leading)
            .lineSpacing(2)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(width: 420, alignment: .leading)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.12))
            }
    }
}
