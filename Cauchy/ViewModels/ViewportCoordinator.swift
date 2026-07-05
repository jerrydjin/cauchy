import Foundation
import Observation

@MainActor
@Observable
final class ViewportCoordinator {
    var viewport: ViewportState = .default
    var applyTrigger = UUID()

    private let syncGuard = ViewportSyncGuard()
    private let debouncer = Debouncer(delay: 0.05)

    var onPageChanged: ((Int) -> Void)?

    func handleViewportChange(state: ViewportState) {
        guard !syncGuard.isApplyingProgrammaticChange else { return }

        debouncer.schedule { [weak self] in
            MainActor.assumeIsolated {
                self?.applyUserChange(state: state)
            }
        }
    }

    private func applyUserChange(state: ViewportState) {
        guard syncGuard.acquire(.primary) else { return }
        defer { syncGuard.release(.primary) }

        let previousPage = viewport.pageIndex
        viewport = mergedState(current: viewport, incoming: state)
        if viewport.pageIndex != previousPage {
            onPageChanged?(viewport.pageIndex)
        }
    }

    func applyProgrammaticViewport(_ state: ViewportState) {
        guard syncGuard.acquire(.primary) else { return }
        defer { syncGuard.release(.primary) }

        let previousPage = viewport.pageIndex
        viewport = state
        applyTrigger = UUID()
        if viewport.pageIndex != previousPage {
            onPageChanged?(viewport.pageIndex)
        }
    }

    func navigateToHighlight(_ highlight: Highlight) {
        var state = viewport
        state.pageIndex = highlight.pageIndex
        if let bounds = highlight.bounds {
            state.visibleRectNormalized = bounds
        }
        applyProgrammaticViewport(state)
    }

    func navigateToPage(_ pageIndex: Int) {
        var state = viewport
        state.pageIndex = max(0, pageIndex)
        state.visibleRectNormalized = nil
        applyProgrammaticViewport(state)
    }

    private func mergedState(current: ViewportState, incoming: ViewportState) -> ViewportState {
        var merged = current
        merged.pageIndex = incoming.pageIndex
        merged.scaleFactor = incoming.scaleFactor
        if let visible = incoming.visibleRectNormalized {
            merged.visibleRectNormalized = visible
        }
        return merged
    }
}
