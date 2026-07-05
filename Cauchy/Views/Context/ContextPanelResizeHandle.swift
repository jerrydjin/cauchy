import SwiftUI

struct ContextPanelResizeHandle: View {
    @Binding var width: CGFloat

    private let minWidth: CGFloat = 300
    private let maxWidth: CGFloat = 640

    @State private var dragStartWidth: CGFloat?

    var body: some View {
        Rectangle()
            .fill(.clear)
            .frame(width: 8)
            .overlay {
                Capsule()
                    .fill(.separator.opacity(0.35))
                    .frame(width: 2)
            }
            .contentShape(Rectangle())
            .onHover { hovering in
                if hovering {
                    NSCursor.resizeLeftRight.push()
                } else {
                    NSCursor.pop()
                }
            }
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        if dragStartWidth == nil {
                            dragStartWidth = width
                        }
                        let start = dragStartWidth ?? width
                        width = min(maxWidth, max(minWidth, start - value.translation.width))
                    }
                    .onEnded { _ in
                        dragStartWidth = nil
                    }
            )
            .help("Drag to resize chat panel")
    }
}
