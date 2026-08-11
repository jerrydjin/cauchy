import SwiftUI

struct ContextPanelResizeHandle: View {
    @Binding var width: CGFloat

    private let minWidth: CGFloat = 300
    private let maxWidth: CGFloat = 640

    @State private var dragStartWidth: CGFloat?
    @State private var isHovering = false

    var body: some View {
        Rectangle()
            .fill(.clear)
            .frame(width: 8)
            // Only under the cursor. Page and panel share one backdrop, so a
            // permanent rule here reads as a grey stripe splitting the window
            // rather than as a grip. The resize cursor is the real affordance.
            .overlay {
                Capsule()
                    .fill(.separator)
                    .frame(width: 2)
                    .opacity(isHovering || dragStartWidth != nil ? 1 : 0)
                    .animation(.easeOut(duration: 0.12), value: isHovering)
            }
            .contentShape(Rectangle())
            .onHover { hovering in
                isHovering = hovering
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
