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
        chunkSequenceNumber: Int,
        samples: [HeartRateSample]
    ) -> UploadChunk?

    func upload(chunk: UploadChunk) async throws -> UploadAck
}
