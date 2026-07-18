import Foundation

/// One-shot commands that must reach the AppKit PDFView inside the
/// representable (they act on view state SwiftUI doesn't own, like PDFKit's
/// link-navigation history or the print machinery). Delivered alongside a
/// revision UUID, same pattern as `applyTrigger`/`findRevision`.
enum PDFViewCommand {
    case goBack
    case goForward
    case print
}
