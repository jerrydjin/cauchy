import Foundation

final class ViewportSyncGuard: @unchecked Sendable {
    private var drivingRole: ViewportRole?
    private let lock = NSLock()

    var isApplyingProgrammaticChange: Bool {
        lock.lock()
        defer { lock.unlock() }
        return drivingRole != nil
    }

    func acquire(_ role: ViewportRole) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard drivingRole == nil else { return false }
        drivingRole = role
        return true
    }

    func release(_ role: ViewportRole) {
        lock.lock()
        defer { lock.unlock() }
        if drivingRole == role {
            drivingRole = nil
        }
    }

    func isDriving(_ role: ViewportRole) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return drivingRole == role
    }
}
