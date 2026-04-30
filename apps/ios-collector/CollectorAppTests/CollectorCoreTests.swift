import XCTest
@testable import CollectorApp

@MainActor
final class CollectorCoreTests: XCTestCase {
    final class RecordingTransport: CollectorTransporting {
        private let chunkBuilder = HeartRateChunkBuilder()
        private var remainingFailures: Int
        let uploadDestinationDescription: String
        let isNetworkUploadConfigured: Bool

        private(set) var descriptorSourceInputs: [String] = []
        private(set) var uploadedChunks: [UploadChunk] = []

        init(
            shouldFailUpload: Bool = false,
            failUploadAttempts: Int = 0,
            uploadDestinationDescription: String = "http://localhost:8080/ingest/wearable/chunk",
            isNetworkUploadConfigured: Bool = true
        ) {
            self.remainingFailures = shouldFailUpload ? Int.max : failUploadAttempts
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
            if remainingFailures > 0 {
                remainingFailures -= 1
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

    final class ImmediateBatteryProvider: HeartRateStreamProviding {
        let streamType: CollectorStream = .battery
        private let samples: [HeartRateSample]

        init(samples: [HeartRateSample]) {
            self.samples = samples
        }

        func start(onSample: @escaping @Sendable (HeartRateSample) -> Void) {
            for sample in samples {
                onSample(sample)
            }
        }

        func stop() {}
    }

    final class ProgressiveScanAdapter: CollectorDeviceAdapter {
        let deviceIdentity: CollectorDevice
        let availableStreams: [CollectorStream] = [.heartRate]
        let sourceIdentifier: String = "polar"
        let deviceSelectionActionTitle: String = "Scan"
        private(set) var connectionState: ConnectionState = .disconnected
        private let scanDevicesSequence: [[CollectorDevice]]

        init(scanDevicesSequence: [[CollectorDevice]]) {
            self.scanDevicesSequence = scanDevicesSequence
            self.deviceIdentity = scanDevicesSequence.last?.last ?? CollectorDevice(
                id: "progressive-default",
                name: "Polar Verity Sense",
                vendor: "Polar",
                model: "Verity Sense"
            )
        }

        func scanDevices() async throws -> [CollectorDevice] { scanDevicesSequence.last ?? [] }

        func scanDevices(onDiscovered: @escaping @Sendable ([CollectorDevice]) -> Void) async throws -> [CollectorDevice] {
            for step in scanDevicesSequence {
                onDiscovered(step)
            }
            return scanDevicesSequence.last ?? []
        }

        func selectDevice(_ device: CollectorDevice) throws { connectionState = .deviceSelected }
        func connect() async throws { connectionState = .connected }
        func disconnect() { connectionState = .disconnected }
        func streamProviders() -> [HeartRateStreamProviding] { [] }
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

    func testDeviceTimeSyncSuccessMapping() async {
        let adapter = MockDeviceAdapter()
        adapter.nextSyncDeviceTimeResult = DeviceTimeActionResult(
            state: .success,
            message: "Device time synced",
            debugDetails: "Stream timestamp verification not performed",
            readbackDeviceTime: Date(timeIntervalSince1970: 200),
            readbackTimeZoneID: "Europe/Kyiv",
            verificationDeltaSeconds: 0.4,
            operationalEvents: []
        )
        let core = CollectorCore(adapter: adapter, transport: RecordingTransport())

        core.selectDevice()
        await core.syncDeviceTimeToPhoneNow()

        XCTAssertEqual(core.deviceTimeSyncState, .success)
        XCTAssertEqual(core.deviceTimeStatusMessage, "Device time synced")
        XCTAssertEqual(core.lastDeviceTimeDeltaSeconds, 0.4, accuracy: 0.001)
    }

    func testDeviceTimeSyncUnavailableMapping() async {
        let adapter = MockDeviceAdapter()
        adapter.nextSyncDeviceTimeResult = DeviceTimeActionResult(
            state: .unavailable,
            message: "Read-back unavailable",
            debugDetails: "feature not ready",
            readbackDeviceTime: nil,
            readbackTimeZoneID: nil,
            verificationDeltaSeconds: nil,
            operationalEvents: []
        )
        let core = CollectorCore(adapter: adapter, transport: RecordingTransport())

        core.selectDevice()
        await core.syncDeviceTimeToPhoneNow()

        XCTAssertEqual(core.deviceTimeSyncState, .unavailable)
        XCTAssertEqual(core.deviceTimeStatusMessage, "Read-back unavailable")
        XCTAssertEqual(core.lastDeviceTimeReadResult, "Read-back unavailable")
    }

    func testPreOfflineSyncHookReturnsStructuredResult() async {
        let adapter = MockDeviceAdapter()
        adapter.nextSyncDeviceTimeResult = DeviceTimeActionResult(
            state: .failed,
            message: "Time sync failed",
            debugDetails: "setLocalTime failed",
            readbackDeviceTime: nil,
            readbackTimeZoneID: nil,
            verificationDeltaSeconds: nil,
            operationalEvents: []
        )
        let core = CollectorCore(adapter: adapter, transport: RecordingTransport())

        let result = await core.runPreOfflineSyncTimeCheck()

        XCTAssertEqual(result.state, .failed)
        XCTAssertEqual(result.message, "Time sync failed")
        XCTAssertEqual(core.deviceTimeSyncState, .failed)
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

    func testFailedChunkIsRetriedAndEventuallyUploadedWithoutLoss() async {
        let transport = RecordingTransport(failUploadAttempts: 1)
        let retryConfiguration = CollectorUploadConfiguration.RetryConfiguration(
            initialDelaySeconds: 0.01,
            maxDelaySeconds: 0.01,
            backoffMultiplier: 1
        )
        let configuration = CollectorUploadConfiguration(
            uploadFlushIntervalSeconds: 60,
            defaultSampleCountThreshold: 1,
            retry: retryConfiguration,
            streamConfigurations: [:],
            userIDHeaderValue: "2",
            streamProfiles: CollectorUploadConfiguration.default.streamProfiles
        )
        let core = CollectorCore(
            adapter: MockDeviceAdapter(
                hrProvider: ImmediateHeartRateProvider(
                    samples: [makeSample(hr: 72, receivedAt: Date(timeIntervalSince1970: 999), sequence: 0)]
                )
            ),
            transport: transport,
            uploadConfiguration: configuration,
            sleepProvider: { _ in
                try? await Task.sleep(nanoseconds: 5_000_000)
            }
        )

        core.selectDevice()
        await core.startCollection()

        let retrySucceeded = await waitUntil(timeoutNanoseconds: 2_000_000_000) {
            core.pendingUploadChunksCount == 0 && core.uploadStatus == .success
        }
        XCTAssertTrue(retrySucceeded)
        XCTAssertGreaterThanOrEqual(transport.uploadedChunks.count, 2)
        XCTAssertEqual(transport.uploadedChunks.first?.chunkID, transport.uploadedChunks.last?.chunkID)
    }

    func testAutoUploadCanUseConfiguredSampleThreshold() async {
        let transport = RecordingTransport()
        let samples = (0..<20).map { index in
            makeSample(
                hr: 60 + index,
                receivedAt: Date(timeIntervalSince1970: 1_000 + Double(index)),
                sequence: index
            )
        }
        let configuration = CollectorUploadConfiguration(
            autoFlushSampleCount: 20,
            autoFlushIntervalSeconds: 60,
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

        let uploaded = await waitUntil { transport.uploadedChunks.count == 1 }
        XCTAssertTrue(uploaded)
        XCTAssertEqual(transport.uploadedChunks.first?.samples.count, 20)
    }

    func testDefaultConfigurationDoesNotFlushImmediatelyBySampleCount() async {
        let transport = RecordingTransport()
        let samples = (0..<20).map { index in
            makeSample(
                hr: 60 + index,
                receivedAt: Date(timeIntervalSince1970: 1_500 + Double(index)),
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

        try? await Task.sleep(nanoseconds: 120_000_000)
        XCTAssertEqual(transport.uploadedChunks.count, 0)
        XCTAssertEqual(core.bufferedSamplesCount, 20)
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
        let configuration = CollectorUploadConfiguration(
            autoFlushSampleCount: 20,
            autoFlushIntervalSeconds: 60,
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

    func testInitialBatteryStateShowsAvailableAfterConnectionWhenCapabilityNeedsConnect() {
        let adapter = MockDeviceAdapter(availableStreams: [.heartRate, .battery])
        let core = CollectorCore(adapter: adapter, transport: RecordingTransport())

        core.selectDevice()

        XCTAssertEqual(core.selectedDeviceBatteryDisplayText(), "available after connection")
    }

    func testDiscoveredDevicesUseCachedBatteryStatusWhenAvailable() async {
        let device = CollectorDevice(
            id: "mock-status-device",
            name: "Mock Polar H10",
            vendor: "Polar",
            model: "H10"
        )
        let snapshot = DeviceStatusSnapshot(
            deviceID: device.id,
            status: DeviceStatus(
                battery: BatteryStatus(
                    levelPercent: 77,
                    chargeState: .charging,
                    lastUpdatedAt: Date(timeIntervalSince1970: 100),
                    source: .cached,
                    unavailableReason: nil
                )
            ),
            updatedAt: Date(timeIntervalSince1970: 100)
        )
        let adapter = MockDeviceAdapter(
            deviceIdentity: device,
            availableStreams: [.heartRate, .battery],
            initialDeviceStatusSnapshot: snapshot
        )
        let core = CollectorCore(adapter: adapter, transport: RecordingTransport())

        await core.scanAndSelectDevice()

        XCTAssertEqual(core.batteryDisplayText(for: device.id), "77%")
        XCTAssertEqual(core.discoveredDeviceStatusByID[device.id]?.status.battery?.source, .cached)
    }

    func testDiscoveredDevicesShowUnavailableBatteryCleanly() async {
        let device = CollectorDevice(
            id: "mock-unavailable-device",
            name: "Mock Polar Verity Sense",
            vendor: "Polar",
            model: "Verity Sense"
        )
        let snapshot = DeviceStatusSnapshot(
            deviceID: device.id,
            status: DeviceStatus(
                battery: BatteryStatus(
                    levelPercent: nil,
                    chargeState: nil,
                    lastUpdatedAt: Date(timeIntervalSince1970: 101),
                    source: .unavailable,
                    unavailableReason: "not ready"
                )
            ),
            updatedAt: Date(timeIntervalSince1970: 101)
        )
        let adapter = MockDeviceAdapter(
            deviceIdentity: device,
            availableStreams: [.heartRate, .battery],
            initialDeviceStatusSnapshot: snapshot
        )
        let core = CollectorCore(adapter: adapter, transport: RecordingTransport())

        await core.scanAndSelectDevice()

        XCTAssertEqual(core.batteryDisplayText(for: device.id), "unavailable")
    }

    func testActiveCollectionMapsCallbackAndPollBatteryIntoGenericStatus() async {
        let callback = makeBatterySample(
            eventType: .callbackUpdate,
            receivedAt: Date(timeIntervalSince1970: 200),
            sequence: 0,
            levelPercent: 88,
            chargeState: "charging"
        )
        let poll = makeBatterySample(
            eventType: .pollSnapshot,
            receivedAt: Date(timeIntervalSince1970: 201),
            sequence: 1,
            levelPercent: 87,
            chargeState: "discharging_active"
        )
        let adapter = MockDeviceAdapter(
            availableStreams: [.heartRate, .battery],
            hrProvider: ImmediateHeartRateProvider(samples: []),
            additionalProviders: [ImmediateBatteryProvider(samples: [callback, poll])]
        )
        let core = CollectorCore(adapter: adapter, transport: RecordingTransport())

        core.selectDevice()
        await core.startCollection()

        let updated = await waitUntil {
            core.latestDeviceStatusSnapshot?.status.battery?.levelPercent == 87
        }
        XCTAssertTrue(updated)
        XCTAssertEqual(core.latestDeviceStatusSnapshot?.status.battery?.source, .poll)
        XCTAssertEqual(core.selectedDeviceBatteryDisplayText(), "87%")
    }

    func testUnsupportedBatteryCapabilityReturnsFallbackWithoutCrash() {
        let adapter = MockDeviceAdapter(availableStreams: [.heartRate])
        let core = CollectorCore(adapter: adapter, transport: RecordingTransport())

        XCTAssertEqual(core.batteryDisplayText(for: "unknown-device"), "unsupported")
    }

    func testCoreExposesGenericDeviceStatusSnapshotType() async {
        let callback = makeBatterySample(
            eventType: .callbackUpdate,
            receivedAt: Date(timeIntervalSince1970: 220),
            sequence: 0,
            levelPercent: 64,
            chargeState: "charging"
        )
        let adapter = MockDeviceAdapter(
            availableStreams: [.heartRate, .battery],
            hrProvider: ImmediateHeartRateProvider(samples: []),
            additionalProviders: [ImmediateBatteryProvider(samples: [callback])]
        )
        let core = CollectorCore(adapter: adapter, transport: RecordingTransport())

        core.selectDevice()
        await core.startCollection()

        let snapshot = core.latestDeviceStatusSnapshot
        XCTAssertNotNil(snapshot)
        XCTAssertEqual(snapshot?.status.battery?.levelPercent, 64)
        XCTAssertEqual(snapshot?.status.battery?.chargeState, .charging)
    }

    func testConnectSelectedDeviceDoesNotAutoStartOnlineStreaming() async {
        let hrProvider = CountingProvider(streamType: .heartRate)
        let adapter = MockDeviceAdapter(
            availableStreams: [.heartRate],
            hrProvider: hrProvider
        )
        let core = CollectorCore(adapter: adapter, transport: RecordingTransport())

        core.selectDevice()
        await core.connectSelectedDevice()

        XCTAssertEqual(core.status, .connected)
        XCTAssertEqual(hrProvider.startCount, 0)
        XCTAssertNil(core.activeSession)
    }

    func testScanProgressivelyUpdatesDiscoveredDevices() async {
        let first = CollectorDevice(id: "d1", name: "Polar A", vendor: "Polar", model: "Verity Sense")
        let second = CollectorDevice(id: "d2", name: "Polar B", vendor: "Polar", model: "Verity Sense")
        let adapter = ProgressiveScanAdapter(scanDevicesSequence: [[first], [first, second]])
        let core = CollectorCore(adapter: adapter, transport: RecordingTransport())

        await core.scanAndSelectDevice()

        XCTAssertEqual(core.discoveredDevices, [first, second])
        XCTAssertEqual(core.lastErrorMessage, "Select a device from the list below")
    }

    func testConnectabilityReflectsAdapterStateForDiscoveredDevice() {
        let device = CollectorDevice(id: "d1", name: "Polar A", vendor: "Polar", model: "Verity Sense")
        let adapter = MockDeviceAdapter(deviceIdentity: device)
        adapter.connectabilityByDeviceID[device.id] = DeviceConnectability(isConnectable: false, reason: "Busy")
        let core = CollectorCore(adapter: adapter, transport: RecordingTransport())

        let result = core.connectability(for: device)
        XCTAssertFalse(result.isConnectable)
        XCTAssertEqual(result.reason, "Busy")
    }

    func testStartSelectedOfflineRecordingsCallsAdapterWithSelectedOnly() async {
        let adapter = MockDeviceAdapter()
        adapter.offlineCapabilityByStream = Dictionary(
            uniqueKeysWithValues: PolarOfflineStream.allCases.map { stream in
                (stream, OfflineStreamCapability(stream: stream, isSupported: true, reason: nil))
            }
        )
        let core = CollectorCore(adapter: adapter, transport: RecordingTransport())
        core.selectDevice()
        await core.connectSelectedDevice()
        core.toggleOfflineStream(.ppi)
        core.toggleOfflineStream(.ppg)
        core.toggleOfflineStream(.mag)
        core.toggleOfflineStream(.gyr)

        await core.startOfflineSelected()

        XCTAssertEqual(adapter.lastStartedOfflineStreams.sorted { $0.rawValue < $1.rawValue }, [.acc, .hr])
    }

    func testStartAllOfflineUsesAllSupportedVeritySenseStreams() async {
        let adapter = MockDeviceAdapter()
        adapter.offlineCapabilityByStream = Dictionary(
            uniqueKeysWithValues: PolarOfflineStream.allCases.map { stream in
                (stream, OfflineStreamCapability(stream: stream, isSupported: true, reason: nil))
            }
        )
        let core = CollectorCore(adapter: adapter, transport: RecordingTransport())
        core.selectDevice()
        await core.connectSelectedDevice()

        await core.startOfflineAllSupported()

        XCTAssertEqual(adapter.lastStartedOfflineStreams.sorted { $0.rawValue < $1.rawValue }, [.acc, .gyr, .hr, .mag, .ppg, .ppi])
    }

    func testStopSelectedAndAllOfflineMappings() async {
        let adapter = MockDeviceAdapter()
        adapter.offlineCapabilityByStream = Dictionary(
            uniqueKeysWithValues: PolarOfflineStream.allCases.map { stream in
                (stream, OfflineStreamCapability(stream: stream, isSupported: true, reason: nil))
            }
        )
        let core = CollectorCore(adapter: adapter, transport: RecordingTransport())
        core.selectDevice()
        await core.connectSelectedDevice()
        core.toggleOfflineStream(.ppi)
        core.toggleOfflineStream(.ppg)
        core.toggleOfflineStream(.mag)
        core.toggleOfflineStream(.gyr)

        await core.stopOfflineSelected()
        XCTAssertEqual(adapter.lastStoppedOfflineStreams.sorted { $0.rawValue < $1.rawValue }, [.acc, .hr])

        await core.stopOfflineAllSupported()
        XCTAssertEqual(adapter.lastStoppedOfflineStreams.sorted { $0.rawValue < $1.rawValue }, [.acc, .gyr, .hr, .mag, .ppg, .ppi])
    }

    func testListOfflineRecordingsStateMapping() async {
        let adapter = MockDeviceAdapter()
        adapter.offlineCapabilityByStream = Dictionary(
            uniqueKeysWithValues: PolarOfflineStream.allCases.map { stream in
                (stream, OfflineStreamCapability(stream: stream, isSupported: true, reason: nil))
            }
        )
        adapter.nextOfflineRecordings = [
            OfflineRecordingEntry(
                id: "entry-1",
                path: "/U/0/HR/1.rec",
                stream: .hr,
                sizeBytes: 123,
                startedAt: Date(timeIntervalSince1970: 100),
                status: "available"
            )
        ]
        let core = CollectorCore(adapter: adapter, transport: RecordingTransport())
        core.selectDevice()
        await core.connectSelectedDevice()

        await core.listOfflineRecordings()

        XCTAssertEqual(core.offlineRecordings.count, 1)
        XCTAssertEqual(core.offlineRecordings.first?.stream, .hr)
        XCTAssertEqual(core.offlineLifecycleState, .completed)
    }

    func testOfflinePartialFailureIsRepresentedInState() async {
        let adapter = MockDeviceAdapter()
        adapter.offlineCapabilityByStream = Dictionary(
            uniqueKeysWithValues: PolarOfflineStream.allCases.map { stream in
                (stream, OfflineStreamCapability(stream: stream, isSupported: true, reason: nil))
            }
        )
        adapter.nextStartOfflineResults[.hr] = OfflineStreamOperationResult(stream: .hr, success: true, message: "Started")
        adapter.nextStartOfflineResults[.acc] = OfflineStreamOperationResult(stream: .acc, success: false, message: "Busy")
        let core = CollectorCore(adapter: adapter, transport: RecordingTransport())
        core.selectDevice()
        await core.connectSelectedDevice()
        core.toggleOfflineStream(.ppi)
        core.toggleOfflineStream(.ppg)
        core.toggleOfflineStream(.mag)
        core.toggleOfflineStream(.gyr)

        await core.startOfflineSelected()

        XCTAssertEqual(core.offlineLifecycleState, .partialSuccess)
        XCTAssertEqual(core.offlineStreamRunMessages[.acc], "Busy")
    }

    func testStopAllOfflineTriggersFetchChunkUploadFlow() async {
        let adapter = MockDeviceAdapter()
        adapter.offlineCapabilityByStream = Dictionary(
            uniqueKeysWithValues: PolarOfflineStream.allCases.map { ($0, OfflineStreamCapability(stream: $0, isSupported: true, reason: nil)) }
        )
        adapter.nextOfflinePreparationResult = OfflineUploadPreparationResult(
            batches: [
                OfflineUploadBatch(
                    stream: .heartRate,
                    sourcePath: "/U/0/HR/1.rec",
                    samples: [makeSample(hr: 61, receivedAt: Date(timeIntervalSince1970: 100), sequence: 1)]
                ),
                OfflineUploadBatch(
                    stream: .ppi,
                    sourcePath: "/U/0/PPI/1.rec",
                    samples: [
                        HeartRateSample(
                            stream: .ppi,
                            collectorReceivedAtUTC: Date(timeIntervalSince1970: 101),
                            sourceTimestampKind: .collectorObserved,
                            sampleSequenceNumber: 1,
                            payload: .ppi(
                                PolarPpiSampleData(
                                    timeStamp: 0,
                                    hr: 62,
                                    ppiMs: 900,
                                    errorEstimateMs: 5,
                                    blockerBit: 0,
                                    skinContactStatus: 1,
                                    skinContactSupported: 1
                                )
                            )
                        )
                    ]
                )
            ],
            messagesByStream: [.hr: "fetched", .ppi: "fetched"]
        )
        let transport = RecordingTransport()
        let core = CollectorCore(adapter: adapter, transport: transport)
        core.selectDevice()
        await core.connectSelectedDevice()

        await core.stopOfflineAllSupported()

        XCTAssertFalse(transport.uploadedChunks.isEmpty)
        XCTAssertEqual(core.uploadStatus, .success)
        XCTAssertEqual(core.offlineStreamRunMessages[.hr], "fetched")
    }

    func testOfflineUploadFailureForOneChunkDoesNotCrashFlow() async {
        let adapter = MockDeviceAdapter()
        adapter.offlineCapabilityByStream = Dictionary(
            uniqueKeysWithValues: PolarOfflineStream.allCases.map { ($0, OfflineStreamCapability(stream: $0, isSupported: true, reason: nil)) }
        )
        adapter.nextOfflinePreparationResult = OfflineUploadPreparationResult(
            batches: [
                OfflineUploadBatch(stream: .heartRate, sourcePath: "/U/0/HR/1.rec", samples: [makeSample(hr: 60, receivedAt: Date(timeIntervalSince1970: 100), sequence: 1)]),
                OfflineUploadBatch(stream: .accelerometer, sourcePath: "/U/0/ACC/1.rec", samples: [
                    HeartRateSample(
                        stream: .accelerometer,
                        collectorReceivedAtUTC: Date(timeIntervalSince1970: 100),
                        sourceTimestampKind: .collectorObserved,
                        sampleSequenceNumber: 1,
                        payload: .acc(
                            PolarAccSampleData(deviceTimeNS: 10, xMg: 1, yMg: 2, zMg: 3, sampleRateHz: nil, rangeMg: nil)
                        )
                    )
                ])
            ],
            messagesByStream: [.hr: "fetched", .acc: "fetched"]
        )
        let transport = RecordingTransport(failUploadAttempts: 1)
        let core = CollectorCore(adapter: adapter, transport: transport)
        core.selectDevice()
        await core.connectSelectedDevice()

        await core.uploadOfflineRecordings()

        XCTAssertEqual(core.uploadStatus, .failure)
        XCTAssertGreaterThanOrEqual(transport.uploadedChunks.count, 1)
    }

    func testDeleteOfflineRecordingCallsAdapterForSelectedOnly() async {
        let adapter = MockDeviceAdapter()
        let entry = OfflineRecordingEntry(
            id: "entry-1",
            path: "/U/0/HR/1.rec",
            stream: .hr,
            sizeBytes: 12,
            startedAt: Date(timeIntervalSince1970: 100),
            status: "available"
        )
        adapter.nextOfflineRecordings = [entry]
        let core = CollectorCore(adapter: adapter, transport: RecordingTransport())
        core.selectDevice()
        await core.connectSelectedDevice()
        await core.listOfflineRecordings()

        await core.deleteOfflineRecording(entry)

        XCTAssertEqual(adapter.removedOfflineRecordingPaths, ["/U/0/HR/1.rec"])
        XCTAssertTrue(core.offlineRecordings.isEmpty)
        XCTAssertEqual(core.offlineLifecycleState, .completed)
    }

    func testDeleteOfflineRecordingFailureShowsPerRecordError() async {
        enum DeleteError: Error, LocalizedError {
            case failed
            var errorDescription: String? { "remove failed" }
        }
        let adapter = MockDeviceAdapter()
        let entry = OfflineRecordingEntry(
            id: "entry-1",
            path: "/U/0/HR/1.rec",
            stream: .hr,
            sizeBytes: nil,
            startedAt: nil,
            status: "available"
        )
        adapter.offlineDeleteErrorsByPath["/U/0/HR/1.rec"] = DeleteError.failed
        let core = CollectorCore(adapter: adapter, transport: RecordingTransport())
        core.selectDevice()
        await core.connectSelectedDevice()

        await core.deleteOfflineRecording(entry)

        XCTAssertEqual(core.offlineRecordErrorsByID["entry-1"], "Delete failed: remove failed")
        XCTAssertEqual(core.offlineLifecycleState, .failed)
    }

    func testOfflineOperationLockPreventsDuplicateStartTaps() async {
        let adapter = MockDeviceAdapter()
        adapter.offlineCapabilityByStream = Dictionary(
            uniqueKeysWithValues: PolarOfflineStream.allCases.map { stream in
                (stream, OfflineStreamCapability(stream: stream, isSupported: true, reason: nil))
            }
        )
        let core = CollectorCore(adapter: adapter, transport: RecordingTransport())
        core.selectDevice()
        await core.connectSelectedDevice()

        async let first: Void = core.startOfflineAllSupported()
        async let second: Void = core.startOfflineAllSupported()
        _ = await (first, second)

        XCTAssertEqual(adapter.lastStartedOfflineStreams.sorted { $0.rawValue < $1.rawValue }, [.acc, .gyr, .hr, .mag, .ppg, .ppi])
        XCTAssertFalse(core.offlineIsOperationRunning)
    }

    func testStartOfflineMapsPerStreamStatesAndErrors() async {
        let adapter = MockDeviceAdapter()
        adapter.offlineCapabilityByStream = Dictionary(
            uniqueKeysWithValues: PolarOfflineStream.allCases.map { stream in
                (stream, OfflineStreamCapability(stream: stream, isSupported: true, reason: nil))
            }
        )
        adapter.nextStartOfflineResults[.hr] = OfflineStreamOperationResult(stream: .hr, success: false, message: "Failed to start: GATT attribute error 1")
        adapter.nextStartOfflineResults[.acc] = OfflineStreamOperationResult(stream: .acc, success: true, message: "Started")
        let core = CollectorCore(adapter: adapter, transport: RecordingTransport())
        core.selectDevice()
        await core.connectSelectedDevice()
        core.toggleOfflineStream(.ppi)
        core.toggleOfflineStream(.ppg)
        core.toggleOfflineStream(.mag)
        core.toggleOfflineStream(.gyr)

        await core.startOfflineSelected()

        XCTAssertEqual(core.offlineStreamRunStates[.acc], .recording)
        XCTAssertEqual(core.offlineStreamRunStates[.hr], .failed)
        XCTAssertEqual(core.offlineLastErrorMessage, "Failed to start: GATT attribute error 1")
    }
}
