import Foundation

struct MockCollectorTransport: CollectorTransporting {
    private let chunkBuilder = HeartRateChunkBuilder()

    func makeStreamDescriptor(
        for stream: CollectorStream,
        source: String = "mock"
    ) -> StreamDescriptor {
        StreamDescriptor(
            streamName: stream.displayName,
            streamType: stream.transportType,
            unit: stream.unit,
            source: source,
            sampleKind: "scalar"
        )
    }

    func prepareUploadChunk(
        session: CollectionSession,
        streamDescriptor: StreamDescriptor,
        chunkSequenceNumber: Int,
        samples: [HeartRateSample]
    ) -> UploadChunk? {
        chunkBuilder.buildChunk(
            session: session,
            streamDescriptor: streamDescriptor,
            chunkSequenceNumber: chunkSequenceNumber,
            samples: samples
        )
    }
}
