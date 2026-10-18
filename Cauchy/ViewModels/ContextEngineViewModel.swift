import Foundation
import Observation

enum ContextPanelTab: String, Hashable {
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
    /// The highlight list yields to the whole-document conversation. Not a new
    /// tab or mode — the same panel, with the ask box still at the bottom.
    var showsDocumentConversation = false

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

    /// Same statement the Reference tab shows, without leaving the conversation.
    func stageReferencePreview(block: DocumentBlock) {
        passiveBlock = block
    }

    func reset() {
        route = .list
        selectedTab = .highlights
        passiveBlock = nil
        draftSelection = nil
        showsDocumentConversation = false
    }
}
