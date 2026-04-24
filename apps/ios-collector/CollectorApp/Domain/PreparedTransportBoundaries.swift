import Foundation

struct PreparedSessionBoundary: Equatable, Sendable {
    let sessionID: UUID
    let collectionModeTransportValue: String
    let startedAt: Date
    let streamTypes: [CollectorStream]
}

struct PreparedChunkBoundary: Equatable, Sendable {
    let sessionID: UUID
    let stream: CollectorStream
    let sequenceNumber: Int
    let sampleCount: Int
    let preparedAt: Date
}
