import SwiftUI

struct GlassIconButton: View {
    let systemName: String
    var accessibilityLabel: String
    var prominent: Bool = false
    var action: () -> Void

    var body: some View {
        Group {
            if prominent {
                styledButton
                    .readerGlassButtonStyle(prominent: true)
            } else {
                styledButton
                    .readerGlassButtonStyle()
            }
        }
        .buttonBorderShape(.circle)
        .clipShape(Circle())
        .accessibilityLabel(accessibilityLabel)
    }

    private var styledButton: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.body.weight(.semibold))
                .frame(width: 28, height: 28)
        }
    }
}
