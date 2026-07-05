import SwiftUI

extension View {
    /// Liquid Glass sidebar title bar — transparent so scroll-edge fade can show through.
    func sidebarToolbarChrome() -> some View {
        toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
    }

    /// Progressive blur where sidebar content meets the top toolbar.
    func sidebarScrollEdgeEffect() -> some View {
        scrollEdgeEffectStyle(.soft, for: .top)
    }

    /// Lets scroll content extend under the transparent title bar for edge fade.
    func sidebarScrollContentInsets() -> some View {
        contentMargins(.top, 0, for: .scrollContent)
    }

    /// Strong frosted blur for the main document toolbar.
    func mainToolbarChrome() -> some View {
        toolbarBackgroundVisibility(.visible, for: .windowToolbar)
            .toolbarBackground(.ultraThickMaterial, for: .windowToolbar)
            .toolbarColorScheme(.dark, for: .windowToolbar)
    }
}
