import Foundation

struct UploadChunk: Identifiable, Equatable, Codable, Sendable {
    let sessionID: UUID
    let streamName: String
    let chunkID: UUID
    let chunkSequenceNumber: Int
    let createdAtUTC: Date
    let samples: [HeartRateSample]
    let collectionMode: CollectionMode

    var id: UUID { chunkID }
}
