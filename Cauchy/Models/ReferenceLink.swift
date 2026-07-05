import Foundation

struct ReferenceLink: Identifiable, Codable, Equatable, Sendable {
    var id: UUID
    var sourcePinID: UUID
    var targetPinID: UUID?
    var targetPageIndex: Int?
    var targetBounds: NormalizedRect?

    init(
        id: UUID = UUID(),
        sourcePinID: UUID,
        targetPinID: UUID? = nil,
        targetPageIndex: Int? = nil,
        targetBounds: NormalizedRect? = nil
    ) {
        self.id = id
        self.sourcePinID = sourcePinID
        self.targetPinID = targetPinID
        self.targetPageIndex = targetPageIndex
        self.targetBounds = targetBounds
    }
}
