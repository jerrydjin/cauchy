import SwiftUI

/// Liquid Glass chrome where the OS has it, and a material stand-in where it
/// does not. The reading layout stays the same; only the surface treatment
/// changes.
enum ReaderGlassKind {
    case plain
    case regular
    case interactive
}

extension View {
    @ViewBuilder
    func readerGlass<S: Shape>(_ kind: ReaderGlassKind = .plain, in shape: S) -> some View {
        if #available(macOS 26, *) {
            switch kind {
            case .plain:
                self.glassEffect(in: shape)
            case .regular:
                self.glassEffect(.regular, in: shape)
            case .interactive:
                self.glassEffect(.regular.interactive(), in: shape)
            }
        } else {
            self.background(.regularMaterial, in: shape)
        }
    }

    @ViewBuilder
    func readerGlassID(_ id: String, namespace: Namespace.ID) -> some View {
        if #available(macOS 26, *) {
            self.glassEffectID(id, in: namespace)
        } else {
            self
        }
    }

    @ViewBuilder
    func readerGlassButtonStyle(prominent: Bool = false) -> some View {
        if #available(macOS 26, *) {
            if prominent {
                self.buttonStyle(.glassProminent)
            } else {
                self.buttonStyle(.glass)
            }
        } else if prominent {
            self.buttonStyle(.borderedProminent)
        } else {
            self.buttonStyle(.bordered)
        }
    }

    /// Messages run under the header and composer on macOS 26, and sit between
    /// them on earlier systems.
    @ViewBuilder
    func readerConversationBars<H: View, F: View>(
        @ViewBuilder header: () -> H,
        @ViewBuilder footer: () -> F
    ) -> some View {
        if #available(macOS 26, *) {
            self
                .safeAreaBar(edge: .top, content: header)
                .safeAreaBar(edge: .bottom, content: footer)
                .scrollEdgeEffectStyle(.soft, for: .top)
                .scrollEdgeEffectStyle(.soft, for: .bottom)
        } else {
            self
                .safeAreaInset(edge: .top, spacing: 0, content: header)
                .safeAreaInset(edge: .bottom, spacing: 0, content: footer)
        }
    }

    /// The system sidebar toggle is part of the macOS 26 toolbar. Earlier
    /// systems keep the split view's own control.
    @ViewBuilder
    func readerRemoveSidebarToggle() -> some View {
        if #available(macOS 26, *) {
            self.toolbar(removing: .sidebarToggle)
        } else {
            self
        }
    }
}

extension ToolbarContent {
    /// Liquid Glass draws a shared capsule behind neighboring toolbar items.
    /// A status pill opts out. Earlier systems have no shared capsule.
    @ToolbarContentBuilder
    func readerHideSharedBackground() -> some ToolbarContent {
        if #available(macOS 26, *) {
            self.sharedBackgroundVisibility(.hidden)
        } else {
            self
        }
    }
}

/// Groups glass shapes so they can morph together on macOS 26+, and is a
/// plain container on earlier systems.
struct ReaderGlassContainer<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        if #available(macOS 26, *) {
            GlassEffectContainer {
                content()
            }
        } else {
            content()
        }
    }
}
