import Foundation

protocol CollectorTransporting {
    var uploadDestinationDescription: String { get }
    var isNetworkUploadConfigured: Bool { get }

    func makeStreamDescriptor(
        for stream: CollectorStream,
        source: String
    ) -> StreamDescriptor

    func prepareUploadChunk(
        session: CollectionSession,
        streamDescriptor: StreamDescriptor,
        streamProfile: StreamMetadataProfile,
        chunkSequenceNumber: Int,
        samples: [HeartRateSample],
        timeContext: UploadChunkTimeContext?
    ) -> UploadChunk?

    func upload(chunk: UploadChunk) async throws -> UploadAck
}
