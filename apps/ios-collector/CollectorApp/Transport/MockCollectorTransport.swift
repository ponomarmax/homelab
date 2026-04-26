import Foundation

struct MockCollectorTransport: CollectorTransporting {
    typealias HTTPDataProvider = @Sendable (URLRequest) async throws -> (Data, URLResponse)

    private let chunkBuilder = HeartRateChunkBuilder()
    private let uploadEndpoint: URL?
    private let shouldSucceedInMockMode: Bool
    private let nowProvider: @Sendable () -> Date
    private let httpDataProvider: HTTPDataProvider
    private let uploadConfiguration: CollectorUploadConfiguration

    var uploadDestinationDescription: String {
        uploadEndpoint?.absoluteString ?? "mock://local-only (no server request)"
    }

    var isNetworkUploadConfigured: Bool {
        uploadEndpoint != nil
    }

    init(
        uploadEndpoint: URL? = nil,
        shouldSucceedInMockMode: Bool = true,
        uploadConfiguration: CollectorUploadConfiguration = .default,
        nowProvider: @escaping @Sendable () -> Date = { Date() },
        httpDataProvider: @escaping HTTPDataProvider = { request in
            try await URLSession.shared.data(for: request)
        }
    ) {
        self.uploadEndpoint = uploadEndpoint
        self.shouldSucceedInMockMode = shouldSucceedInMockMode
        self.uploadConfiguration = uploadConfiguration
        self.nowProvider = nowProvider
        self.httpDataProvider = httpDataProvider
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
            streamProfile: uploadConfiguration.streamProfile,
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
                message: "Mock upload accepted (no network request)"
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
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(uploadConfiguration.userIDHeaderValue, forHTTPHeaderField: "X-User-ID")

        let encoder = JSONEncoder()
        request.httpBody = try encoder.encode(requestBody)

        let (data, response) = try await httpDataProvider(request)
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
            let detailSummary = (errorResponse.details ?? [])
                .map { "\($0.field): \($0.issue)" }
                .joined(separator: "; ")
            let detailsSuffix = detailSummary.isEmpty ? "" : " Details: \(detailSummary)"
            throw CollectorUploadError.rejected(
                message: "[\(errorResponse.errorCode)] \(errorResponse.message)\(detailsSuffix)"
            )
        }

        throw CollectorUploadError.rejected(
            message: "Upload failed with status \(httpResponse.statusCode)"
        )
    }
}
