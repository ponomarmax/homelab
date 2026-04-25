import XCTest
@testable import CollectorApp

@MainActor
final class CollectorCoreTests: XCTestCase {
    final class RecordingTransport: CollectorTransporting {
        private let chunkBuilder = HeartRateChunkBuilder()
        private let shouldFailUpload: Bool
        let uploadDestinationDescription: String
        let isNetworkUploadConfigured: Bool

        private(set) var descriptorSourceInputs: [String] = []
        private(set) var uploadedChunks: [UploadChunk] = []

        init(
            shouldFailUpload: Bool = false,
            uploadDestinationDescription: String = "http://localhost:8080/ingest/wearable/chunk",
            isNetworkUploadConfigured: Bool = true
        ) {
            self.shouldFailUpload = shouldFailUpload
            self.uploadDestinationDescription = uploadDestinationDescription
            self.isNetworkUploadConfigured = isNetworkUploadConfigured
        }

        func makeStreamDescriptor(for stream: CollectorStream, source: String) -> StreamDescriptor {
            descriptorSourceInputs.append(source)
            return StreamDescriptor(
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
            uploadedChunks.append(chunk)
            if shouldFailUpload {
                throw TestUploadError.rejected
            }

            let uploadedAt = Date(timeIntervalSince1970: 1_000)
            let canonical = try XCTUnwrap(chunk.makeCanonicalRequest(uploadedAtUTC: uploadedAt))

            return UploadAck(
                accepted: true,
                status: "accepted",
                chunkID: canonical.chunkID,
                sessionID: canonical.sessionID,
                streamID: canonical.streamID,
                receivedAtServer: canonical.time.uploadedAtCollector,
                storage: UploadAck.UploadStorage(
                    rawPersisted: true,
                    storagePath: "mock/\(canonical.sessionID).jsonl"
                ),
                message: "ok"
            )
        }
    }

    final class SourceTaggedAdapter: CollectorDeviceAdapter {
        let deviceIdentity: CollectorDevice
        let availableStreams: [CollectorStream] = [.heartRate]
        let sourceIdentifier: String
        let deviceSelectionActionTitle: String
        private(set) var connectionState: ConnectionState = .disconnected

        private let provider: HeartRateStreamProviding

        init(
            sourceIdentifier: String,
            deviceSelectionActionTitle: String = "Select",
            provider: HeartRateStreamProviding
        ) {
            self.sourceIdentifier = sourceIdentifier
            self.deviceSelectionActionTitle = deviceSelectionActionTitle
            self.provider = provider
            self.deviceIdentity = CollectorDevice(
                id: "custom-device",
                name: "Custom Device",
                vendor: "CustomVendor",
                model: "ModelX"
            )
        }

        func scanDevices() async throws -> [CollectorDevice] { [deviceIdentity] }

        func selectDevice(_ device: CollectorDevice) throws {
            connectionState = .deviceSelected
        }

        func connect() async throws {
            connectionState = .connected
        }

        func disconnect() {
            provider.stop()
            connectionState = .disconnected
        }

        func heartRateStreamProvider() -> HeartRateStreamProviding? {
            provider
        }
    }

    func testCoreStartsAndStopsSession() async {
        let core = CollectorCore(
            adapter: MockDeviceAdapter(
                hrProvider: MockHeartRateStreamProvider(intervalNanoseconds: 10_000_000)
            ),
            transport: RecordingTransport()
        )

        core.selectDevice()
        await core.startCollection()
        XCTAssertEqual(core.status, .collecting)
        XCTAssertNotNil(core.activeSession)

        core.stopCollection()
        XCTAssertEqual(core.status, .stopped)
        XCTAssertNotNil(core.activeSession?.stoppedAtUTC)
    }

    func testCoreUsesAdapterSourceIdentifierForStreamDescriptor() async throws {
        let sample = makeSample(
            hr: 70,
            receivedAt: Date(timeIntervalSince1970: 100),
            sequence: 0
        )
        let transport = RecordingTransport()
        let adapter = SourceTaggedAdapter(
            sourceIdentifier: "custom-sensor-source",
            provider: ImmediateHeartRateProvider(samples: [sample])
        )
        let core = CollectorCore(adapter: adapter, transport: transport)

        core.selectDevice()
        await core.startCollection()

        XCTAssertEqual(core.deviceActionTitle, "Select")
        XCTAssertEqual(transport.descriptorSourceInputs, ["custom-sensor-source"])
        XCTAssertEqual(core.streamDescriptor?.source, "custom-sensor-source")
    }

    func testCoreBuffersSamplesAndPreparesChunk() async throws {
        let firstTimestamp = Date(timeIntervalSince1970: 200)
        let secondTimestamp = Date(timeIntervalSince1970: 201)
        let samples = [
            makeSample(
                hr: 80,
                receivedAt: firstTimestamp,
                sequence: 0,
                deviceTimestamp: firstTimestamp.addingTimeInterval(-0.5),
                sourceTimestampKind: .deviceReported
            ),
            makeSample(
                hr: 81,
                receivedAt: secondTimestamp,
                sequence: 1,
                deviceTimestamp: secondTimestamp.addingTimeInterval(-0.5),
                sourceTimestampKind: .deviceReported
            )
        ]

        let core = CollectorCore(
            adapter: MockDeviceAdapter(
                hrProvider: ImmediateHeartRateProvider(samples: samples)
            ),
            transport: RecordingTransport()
        )

        core.selectDevice()
        await core.startCollection()

        let bufferedSamplesReady = await waitUntil { core.bufferedSamplesCount >= 2 }
        XCTAssertTrue(bufferedSamplesReady)

        let chunk = try XCTUnwrap(core.prepareUploadChunk())
        let session = try XCTUnwrap(core.activeSession)

        XCTAssertEqual(core.totalSamplesReceived, 2)
        XCTAssertEqual(chunk.sessionID, session.sessionID)
        XCTAssertEqual(chunk.streamType, "hr")
        XCTAssertEqual(chunk.samples.count, 2)
        XCTAssertEqual(chunk.samples[0].collectorReceivedAtUTC, firstTimestamp)
        XCTAssertEqual(chunk.samples[1].collectorReceivedAtUTC, secondTimestamp)
        XCTAssertEqual(core.bufferedSamplesCount, 0)
        XCTAssertEqual(core.lastPreparedChunk?.samples.count, 2)
    }

    func testCoreForwardsPreparedChunkToTransportOnUpload() async {
        let transport = RecordingTransport()
        let core = CollectorCore(
            adapter: MockDeviceAdapter(
                hrProvider: ImmediateHeartRateProvider(
                    samples: [makeSample(hr: 71, receivedAt: Date(), sequence: 0)]
                )
            ),
            transport: transport
        )

        core.selectDevice()
        await core.startCollection()
        let bufferedSamplesReady = await waitUntil { core.bufferedSamplesCount >= 1 }
        XCTAssertTrue(bufferedSamplesReady)

        _ = core.prepareUploadChunk()
        await core.uploadLastPreparedChunk()

        XCTAssertEqual(core.uploadStatus, .success)
        XCTAssertEqual(transport.uploadedChunks.count, 1)
        XCTAssertEqual(core.pendingUploadChunksCount, 0)
    }

    func testCoreUploadFailureUpdatesState() async {
        let core = CollectorCore(
            adapter: MockDeviceAdapter(
                hrProvider: ImmediateHeartRateProvider(
                    samples: [makeSample(hr: 71, receivedAt: Date(), sequence: 0)]
                )
            ),
            transport: RecordingTransport(shouldFailUpload: true)
        )

        core.selectDevice()
        await core.startCollection()
        let bufferedSamplesReady = await waitUntil { core.bufferedSamplesCount >= 1 }
        XCTAssertTrue(bufferedSamplesReady)

        _ = core.prepareUploadChunk()
        await core.uploadLastPreparedChunk()

        XCTAssertEqual(core.uploadStatus, .failure)
        XCTAssertNotNil(core.lastErrorMessage)
        XCTAssertEqual(core.pendingUploadChunksCount, 1)
        XCTAssertTrue(core.shouldSuggestLogExport)
    }

    func testPendingQueueAccumulatesChunksWhenServerIsUnavailable() async {
        let transport = RecordingTransport(shouldFailUpload: true)
        let core = CollectorCore(
            adapter: MockDeviceAdapter(
                hrProvider: MockHeartRateStreamProvider(
                    values: [70, 71, 72, 73],
                    intervalNanoseconds: 10_000_000
                )
            ),
            transport: transport
        )

        core.selectDevice()
        await core.startCollection()
        let firstBufferReady = await waitUntil { core.bufferedSamplesCount >= 1 }
        XCTAssertTrue(firstBufferReady)
        _ = core.prepareUploadChunk()
        XCTAssertEqual(core.pendingUploadChunksCount, 1)

        let secondBufferReady = await waitUntil { core.bufferedSamplesCount >= 1 }
        XCTAssertTrue(secondBufferReady)
        _ = core.prepareUploadChunk()
        XCTAssertEqual(core.pendingUploadChunksCount, 2)

        await core.uploadLastPreparedChunk()
        XCTAssertEqual(core.uploadStatus, .failure)
        XCTAssertEqual(core.pendingUploadChunksCount, 2)
    }

    func testPrepareLogExportCreatesShareableFile() {
        let core = CollectorCore(
            adapter: MockDeviceAdapter(),
            transport: RecordingTransport()
        )

        core.prepareLogExportFile()

        XCTAssertNotNil(core.logExportFileURL)
    }
}
