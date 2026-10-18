import SwiftUI

extension View {
    /// Liquid Glass sidebar title bar — transparent so scroll-edge fade can show through.
    @ViewBuilder
    func sidebarToolbarChrome() -> some View {
        if #available(macOS 26, *) {
            self.toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        } else {
            self.toolbarBackground(.hidden, for: .windowToolbar)
        }
    }

    /// Progressive blur where sidebar content meets the top toolbar.
    @ViewBuilder
    func sidebarScrollEdgeEffect() -> some View {
        if #available(macOS 26, *) {
            self.scrollEdgeEffectStyle(.soft, for: .top)
        } else {
            self
        }
    }

    /// Lets scroll content extend under the transparent title bar for edge fade.
    func sidebarScrollContentInsets() -> some View {
        contentMargins(.top, 0, for: .scrollContent)
    }

    /// Strong frosted blur for the main document toolbar.
    @ViewBuilder
    func mainToolbarChrome() -> some View {
        if #available(macOS 26, *) {
            self.toolbarBackgroundVisibility(.visible, for: .windowToolbar)
                .toolbarBackground(.ultraThickMaterial, for: .windowToolbar)
                .toolbarColorScheme(.dark, for: .windowToolbar)
        } else {
            self.toolbarBackground(.visible, for: .windowToolbar)
                .toolbarBackground(.ultraThickMaterial, for: .windowToolbar)
                .toolbarColorScheme(.dark, for: .windowToolbar)
        }
    }
}
