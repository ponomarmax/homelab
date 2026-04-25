import Foundation

struct HeartRateChunkBuilder {
    func buildChunk(
        session: CollectionSession,
        streamDescriptor: StreamDescriptor,
        chunkSequenceNumber: Int,
        samples: [HeartRateSample],
        createdAtUTC: Date = Date()
    ) -> UploadChunk? {
        guard !samples.isEmpty else { return nil }

        return UploadChunk(
            sessionID: session.sessionID,
            streamName: streamDescriptor.streamName,
            streamType: streamDescriptor.streamType,
            chunkID: UUID(),
            chunkSequenceNumber: chunkSequenceNumber,
            createdAtUTC: createdAtUTC,
            samples: samples,
            collectionMode: session.collectionMode
        )
    }
}
