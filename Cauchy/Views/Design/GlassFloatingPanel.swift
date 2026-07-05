import SwiftUI

struct GlassFloatingPanel<Content: View>: View {
    let title: String
    @ViewBuilder var content: () -> Content
    var onClose: (() -> Void)?

    @Namespace private var namespace

    var body: some View {
        GlassEffectContainer {
            VStack(spacing: 0) {
                HStack {
                    Text(title)
                        .font(.headline)
                    Spacer()
                    if let onClose {
                        GlassIconButton(
                            systemName: "xmark",
                            accessibilityLabel: "Close",
                            action: onClose
                        )
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)

                content()
            }
            .glassEffect(in: .rect(cornerRadius: 16))
            .glassEffectID("secondaryPanel", in: namespace)
        }
        .shadow(radius: 12, y: 4)
    }
}
