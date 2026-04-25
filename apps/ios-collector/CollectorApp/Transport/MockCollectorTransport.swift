import Foundation

struct MockCollectorTransport: CollectorTransporting {
    private let chunkBuilder = HeartRateChunkBuilder()
    private let uploadEndpoint: URL?
    private let shouldSucceedInMockMode: Bool
    private let nowProvider: @Sendable () -> Date

    init(
        uploadEndpoint: URL? = nil,
        shouldSucceedInMockMode: Bool = true,
        nowProvider: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.uploadEndpoint = uploadEndpoint
        self.shouldSucceedInMockMode = shouldSucceedInMockMode
        self.nowProvider = nowProvider
    }

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

    func upload(chunk: UploadChunk) async throws -> UploadAck {
        guard let requestBody = chunk.makeCanonicalRequest(uploadedAtUTC: nowProvider()) else {
            throw CollectorUploadError.missingPayload
        }

        if let uploadEndpoint {
            return try await uploadToServer(
                requestBody: requestBody,
                chunk: chunk,
                endpoint: uploadEndpoint
            )
        }

        if shouldSucceedInMockMode {
            return UploadAck(
                accepted: true,
                status: "accepted",
                chunkID: requestBody.chunkID,
                sessionID: requestBody.sessionID,
                streamID: requestBody.streamID,
                receivedAtServer: requestBody.time.uploadedAtCollector,
                storage: UploadAck.UploadStorage(
                    rawPersisted: true,
                    storagePath: "mock/raw/\(requestBody.sessionID)/\(requestBody.streamID).jsonl"
                ),
                message: "Mock upload accepted"
            )
        }

        throw CollectorUploadError.rejected(message: "Mock upload failed")
    }

    private func uploadToServer(
        requestBody: CanonicalUploadChunkRequest,
        chunk: UploadChunk,
        endpoint: URL
    ) async throws -> UploadAck {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let encoder = JSONEncoder()
        request.httpBody = try encoder.encode(requestBody)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw CollectorUploadError.invalidResponse
        }

        let decoder = JSONDecoder()
        if (200...299).contains(httpResponse.statusCode) {
            if let ack = try? decoder.decode(UploadAck.self, from: data) {
                return ack
            }
            throw CollectorUploadError.invalidResponse
        }

        if let errorResponse = try? decoder.decode(UploadErrorResponse.self, from: data) {
            throw CollectorUploadError.rejected(message: errorResponse.message)
        }

        throw CollectorUploadError.rejected(
            message: "Upload failed with status \(httpResponse.statusCode)"
        )
    }
}
