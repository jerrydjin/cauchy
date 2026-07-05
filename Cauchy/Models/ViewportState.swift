import CoreGraphics
import Foundation

enum ViewportSyncMode: String, Codable, Sendable {
    case independent
    case followTarget
    case followSource
}

struct ViewportState: Codable, Equatable, Sendable {
    var pageIndex: Int
    var scaleFactor: CGFloat
    var visibleRectNormalized: NormalizedRect?
    var linkedReferenceLinkID: UUID?
    var syncMode: ViewportSyncMode

    static let `default` = ViewportState(
        pageIndex: 0,
        scaleFactor: 1.0,
        visibleRectNormalized: nil,
        linkedReferenceLinkID: nil,
        syncMode: .independent
    )
}
