import Foundation

/// Prevents feedback loops between programmatic viewport changes and the
/// PDFView notifications they trigger. All viewport sync happens on the main
/// actor, so plain isolated state suffices.
@MainActor
final class ViewportSyncGuard {
    private var drivingRole: ViewportRole?

    var isApplyingProgrammaticChange: Bool {
        drivingRole != nil
    }

    func acquire(_ role: ViewportRole) -> Bool {
        guard drivingRole == nil else { return false }
        drivingRole = role
        return true
    }

    func release(_ role: ViewportRole) {
        if drivingRole == role {
            drivingRole = nil
        }
    }
}
