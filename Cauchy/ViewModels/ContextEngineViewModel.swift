import Foundation
import Observation

enum ContextPanelTab: String, Equatable {
    case highlights
    case reference
}

enum HighlightPanelRoute: Equatable {
    case list
    case detail(UUID)
    case composeDraft
}

@MainActor
@Observable
final class ContextEngineViewModel {
    var route: HighlightPanelRoute = .list
    var selectedTab: ContextPanelTab = .highlights
    var passiveBlock: DocumentBlock?
    var draftSelection: TextSelectionContext?

    func showList() {
        route = .list
        draftSelection = nil
    }

    func showDetail(_ id: UUID) {
        route = .detail(id)
        draftSelection = nil
    }

    func showComposeDraft(_ context: TextSelectionContext) {
        route = .composeDraft
        draftSelection = context
    }

    func showReferencePreview(block: DocumentBlock) {
        passiveBlock = block
        selectedTab = .reference
    }

    func reset() {
        route = .list
        selectedTab = .highlights
        passiveBlock = nil
        draftSelection = nil
    }
}
