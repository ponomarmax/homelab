import Foundation

protocol CollectorTransporting {
    func makeStreamDescriptor(
        for stream: CollectorStream,
        source: String
    ) -> StreamDescriptor

    func prepareUploadChunk(
        session: CollectionSession,
        streamDescriptor: StreamDescriptor,
        chunkSequenceNumber: Int,
        samples: [HeartRateSample]
    ) -> UploadChunk?

    func upload(chunk: UploadChunk) async throws -> UploadAck
}
