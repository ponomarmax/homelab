import Foundation

struct CollectionSession: Identifiable, Equatable, Sendable {
    struct Metadata: Equatable, Sendable {
        let mode: CollectionMode
        let startedAt: Date
        let collectorID: String
    }

    let id: UUID
    let device: CollectorDevice
    let metadata: Metadata

    init(
        id: UUID = UUID(),
        device: CollectorDevice,
        metadata: Metadata
    ) {
        self.id = id
        self.device = device
        self.metadata = metadata
    }
}
