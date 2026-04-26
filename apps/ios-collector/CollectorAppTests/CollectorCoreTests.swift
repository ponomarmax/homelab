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
            streamProfile: StreamMetadataProfile,
            chunkSequenceNumber: Int,
            samples: [HeartRateSample]
        ) -> UploadChunk? {
            chunkBuilder.buildChunk(
                session: session,
                streamDescriptor: streamDescriptor,
                streamProfile: streamProfile,
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

        func streamProviders() -> [HeartRateStreamProviding] {
            [provider]
        }

        func heartRateStreamProvider() -> HeartRateStreamProviding? {
            provider
        }
    }

    final class CountingProvider: HeartRateStreamProviding {
        let streamType: CollectorStream
        private(set) var startCount: Int = 0
        private(set) var stopCount: Int = 0

        init(streamType: CollectorStream) {
            self.streamType = streamType
        }

        func start(onSample: @escaping @Sendable (HeartRateSample) -> Void) {
            startCount += 1
        }

        func stop() {
            stopCount += 1
        }
    }

    final class PostConnectStreamsAdapter: CollectorDeviceAdapter {
        let deviceIdentity: CollectorDevice = CollectorDevice(
            id: "post-connect-device",
            name: "Polar H10",
            vendor: "Polar",
            model: "H10"
        )
        let availableStreams: [CollectorStream] = [.heartRate, .ecg, .accelerometer]
        let sourceIdentifier: String = "polar"
        let deviceSelectionActionTitle: String = "Scan"
        private(set) var connectionState: ConnectionState = .disconnected

        private let preConnectProviders: [HeartRateStreamProviding]
        private let postConnectProviders: [HeartRateStreamProviding]

        init(
            preConnectProviders: [HeartRateStreamProviding],
            postConnectProviders: [HeartRateStreamProviding]
        ) {
            self.preConnectProviders = preConnectProviders
            self.postConnectProviders = postConnectProviders
        }

        func scanDevices() async throws -> [CollectorDevice] {
            [deviceIdentity]
        }

        func selectDevice(_ device: CollectorDevice) throws {
            connectionState = .deviceSelected
        }

        func connect() async throws {
            connectionState = .connected
        }

        func disconnect() {
            connectionState = .disconnected
            postConnectProviders.forEach { $0.stop() }
        }

        func streamProviders() -> [HeartRateStreamProviding] {
            connectionState == .connected ? postConnectProviders : preConnectProviders
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

    func testCoreResolvesStreamProvidersAfterConnect() async {
        let hrProvider = CountingProvider(streamType: .heartRate)
        let ecgProvider = CountingProvider(streamType: .ecg)
        let accProvider = CountingProvider(streamType: .accelerometer)

        let adapter = PostConnectStreamsAdapter(
            preConnectProviders: [hrProvider],
            postConnectProviders: [hrProvider, ecgProvider, accProvider]
        )
        let core = CollectorCore(adapter: adapter, transport: RecordingTransport())

        core.selectDevice()
        await core.startCollection()

        XCTAssertEqual(core.status, .collecting)
        XCTAssertEqual(hrProvider.startCount, 1)
        XCTAssertEqual(ecgProvider.startCount, 1)
        XCTAssertEqual(accProvider.startCount, 1)
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
        core.stopCollection()
    }

    func testAutoUploadTriggersAtTwentySamples() async {
        let transport = RecordingTransport()
        let samples = (0..<20).map { index in
            makeSample(
                hr: 60 + index,
                receivedAt: Date(timeIntervalSince1970: 1_000 + Double(index)),
                sequence: index
            )
        }
        let core = CollectorCore(
            adapter: MockDeviceAdapter(
                hrProvider: ImmediateHeartRateProvider(samples: samples)
            ),
            transport: transport
        )

        core.selectDevice()
        await core.startCollection()

        let uploaded = await waitUntil { transport.uploadedChunks.count == 1 }
        XCTAssertTrue(uploaded)
        XCTAssertEqual(transport.uploadedChunks.first?.samples.count, 20)
    }

    func testAutoUploadTriggersByFlushIntervalWhenBelowSampleThreshold() async {
        let transport = RecordingTransport()
        let samples = (0..<3).map { index in
            makeSample(
                hr: 70 + index,
                receivedAt: Date(timeIntervalSince1970: 2_000 + Double(index)),
                sequence: index
            )
        }
        let configuration = CollectorUploadConfiguration(
            autoFlushSampleCount: 20,
            autoFlushIntervalSeconds: 0.05,
            userIDHeaderValue: "2",
            streamProfiles: CollectorUploadConfiguration.default.streamProfiles
        )
        let core = CollectorCore(
            adapter: MockDeviceAdapter(
                hrProvider: ImmediateHeartRateProvider(samples: samples)
            ),
            transport: transport,
            uploadConfiguration: configuration,
            sleepProvider: { _ in
                try? await Task.sleep(nanoseconds: 5_000_000)
            }
        )

        core.selectDevice()
        await core.startCollection()

        let uploaded = await waitUntil(timeoutNanoseconds: 2_000_000_000) {
            transport.uploadedChunks.count == 1
        }
        XCTAssertTrue(uploaded)
        XCTAssertEqual(transport.uploadedChunks.first?.samples.count, 3)
    }

    func testStopCollectionFlushesRemainingSamples() async {
        let transport = RecordingTransport()
        let samples = (0..<5).map { index in
            makeSample(
                hr: 80 + index,
                receivedAt: Date(timeIntervalSince1970: 3_000 + Double(index)),
                sequence: index
            )
        }
        let configuration = CollectorUploadConfiguration(
            autoFlushSampleCount: 20,
            autoFlushIntervalSeconds: 30,
            userIDHeaderValue: "2",
            streamProfiles: CollectorUploadConfiguration.default.streamProfiles
        )
        let core = CollectorCore(
            adapter: MockDeviceAdapter(
                hrProvider: ImmediateHeartRateProvider(samples: samples)
            ),
            transport: transport,
            uploadConfiguration: configuration
        )

        core.selectDevice()
        await core.startCollection()
        let buffered = await waitUntil { core.bufferedSamplesCount == 5 }
        XCTAssertTrue(buffered)
        core.stopCollection()

        let uploaded = await waitUntil { transport.uploadedChunks.count == 1 }
        XCTAssertTrue(uploaded)
        XCTAssertEqual(transport.uploadedChunks.first?.samples.count, 5)
    }

    func testStopCollectionDoesNotUploadEmptyChunk() async {
        let transport = RecordingTransport()
        let configuration = CollectorUploadConfiguration(
            autoFlushSampleCount: 20,
            autoFlushIntervalSeconds: 30,
            userIDHeaderValue: "2",
            streamProfiles: CollectorUploadConfiguration.default.streamProfiles
        )
        let core = CollectorCore(
            adapter: MockDeviceAdapter(
                hrProvider: ImmediateHeartRateProvider(samples: [])
            ),
            transport: transport,
            uploadConfiguration: configuration
        )

        core.selectDevice()
        await core.startCollection()
        core.stopCollection()
        try? await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertEqual(transport.uploadedChunks.count, 0)
    }

    func testStreamIDStableSequenceIncrementsAndChunkIDIsUniqueWithinSession() async {
        let transport = RecordingTransport()
        let samples = (0..<40).map { index in
            makeSample(
                hr: 65 + index,
                receivedAt: Date(timeIntervalSince1970: 4_000 + Double(index)),
                sequence: index
            )
        }
        let core = CollectorCore(
            adapter: MockDeviceAdapter(
                hrProvider: ImmediateHeartRateProvider(samples: samples)
            ),
            transport: transport
        )

        core.selectDevice()
        await core.startCollection()

        let uploadedTwoChunks = await waitUntil(timeoutNanoseconds: 2_000_000_000) {
            transport.uploadedChunks.count == 2
        }
        XCTAssertTrue(uploadedTwoChunks)

        let chunks = transport.uploadedChunks
        let streamIDs = Set(chunks.map(\.streamID))
        let chunkIDs = Set(chunks.map(\.chunkID))
        let sequences = chunks.map(\.chunkSequenceNumber).sorted()

        XCTAssertEqual(streamIDs.count, 1)
        XCTAssertEqual(chunkIDs.count, chunks.count)
        XCTAssertEqual(sequences, [1, 2])
        core.stopCollection()
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
