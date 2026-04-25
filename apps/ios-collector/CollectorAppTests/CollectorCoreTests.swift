import XCTest
@testable import CollectorApp

@MainActor
final class CollectorCoreTests: XCTestCase {
    final class ImmediateHeartRateProvider: HeartRateStreamProviding {
        let streamType: CollectorStream = .heartRate

        private let samples: [HeartRateSample]
        private var isStopped = false

        init(samples: [HeartRateSample]) {
            self.samples = samples
        }

        func start(onSample: @escaping @Sendable (HeartRateSample) -> Void) {
            isStopped = false
            for sample in samples where !isStopped {
                onSample(sample)
            }
        }

        func stop() {
            isStopped = true
        }
    }

    struct TestUploadError: LocalizedError {
        var errorDescription: String? { "upload rejected" }
    }

    final class TestTransport: CollectorTransporting {
        private let chunkBuilder = HeartRateChunkBuilder()
        private let shouldFailUpload: Bool

        init(shouldFailUpload: Bool = false) {
            self.shouldFailUpload = shouldFailUpload
        }

        func makeStreamDescriptor(
            for stream: CollectorStream,
            source: String
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
            if shouldFailUpload {
                throw TestUploadError()
            }

            guard let canonical = chunk.makeCanonicalRequest(
                uploadedAtUTC: Date(timeIntervalSince1970: 1_000)
            ) else {
                throw TestUploadError()
            }

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

    private func waitUntil(
        timeoutNanoseconds: UInt64 = 1_000_000_000,
        pollIntervalNanoseconds: UInt64 = 10_000_000,
        _ condition: @escaping @MainActor () -> Bool
    ) async -> Bool {
        let started = DispatchTime.now().uptimeNanoseconds
        while !condition() {
            let elapsed = DispatchTime.now().uptimeNanoseconds - started
            if elapsed >= timeoutNanoseconds {
                return false
            }
            try? await Task.sleep(nanoseconds: pollIntervalNanoseconds)
        }
        return true
    }

    func testMockHeartRateProviderEmitsSamples() async {
        let provider = MockHeartRateStreamProvider(
            values: [61, 62],
            intervalNanoseconds: 20_000_000
        )
        let expectation = expectation(description: "Provider emits samples")
        expectation.expectedFulfillmentCount = 2

        provider.start { sample in
            XCTAssertTrue([61, 62].contains(sample.hrBPM))
            expectation.fulfill()
        }

        await fulfillment(of: [expectation], timeout: 1.0)
        provider.stop()
    }

    func testSessionCreationUsesExpectedMetadata() async throws {
        let sample = HeartRateSample(
            hrBPM: 65,
            collectorReceivedAtUTC: Date(),
            deviceTimestampRaw: nil,
            sourceTimestampKind: .collectorObserved,
            sampleSequenceNumber: 0
        )
        let core = CollectorCore(
            adapter: MockDeviceAdapter(
                hrProvider: ImmediateHeartRateProvider(samples: [sample])
            ),
            transport: TestTransport()
        )

        core.selectDevice()
        await core.startCollection()

        let session = try XCTUnwrap(core.activeSession)
        XCTAssertEqual(session.deviceID, "mock-polar-verity-sense")
        XCTAssertEqual(session.deviceType, "Polar Verity Sense")
        XCTAssertEqual(session.collectionMode, .live)
        XCTAssertEqual(session.supportedStreams, [.heartRate])
        XCTAssertNil(session.stoppedAtUTC)
    }

    func testCollectorCoreStartsAndStopsSession() async {
        let core = CollectorCore(
            adapter: MockDeviceAdapter(
                hrProvider: MockHeartRateStreamProvider(intervalNanoseconds: 10_000_000)
            ),
            transport: TestTransport()
        )

        core.selectDevice()

        await core.startCollection()
        XCTAssertEqual(core.status, .collecting)
        XCTAssertNotNil(core.activeSession)
        XCTAssertEqual(core.defaultCollectionMode, .live)

        core.stopCollection()
        XCTAssertEqual(core.status, .stopped)
        XCTAssertNotNil(core.activeSession?.stoppedAtUTC)
    }

    func testSampleSequenceAndCountersIncrease() async throws {
        let samples = [
            HeartRateSample(
                hrBPM: 70,
                collectorReceivedAtUTC: Date(timeIntervalSince1970: 100),
                deviceTimestampRaw: nil,
                sourceTimestampKind: .collectorObserved,
                sampleSequenceNumber: 0
            ),
            HeartRateSample(
                hrBPM: 71,
                collectorReceivedAtUTC: Date(timeIntervalSince1970: 101),
                deviceTimestampRaw: nil,
                sourceTimestampKind: .collectorObserved,
                sampleSequenceNumber: 1
            ),
            HeartRateSample(
                hrBPM: 72,
                collectorReceivedAtUTC: Date(timeIntervalSince1970: 102),
                deviceTimestampRaw: nil,
                sourceTimestampKind: .collectorObserved,
                sampleSequenceNumber: 2
            )
        ]

        let core = CollectorCore(
            adapter: MockDeviceAdapter(
                hrProvider: ImmediateHeartRateProvider(samples: samples)
            ),
            transport: TestTransport()
        )

        core.selectDevice()
        await core.startCollection()

        let receivedAllSamples = await waitUntil {
            core.totalSamplesReceived >= 3 && core.latestHeartRateSample != nil
        }
        XCTAssertTrue(receivedAllSamples, "Timed out waiting for HR samples to be processed")

        let latestSample = try XCTUnwrap(core.latestHeartRateSample)
        XCTAssertEqual(core.totalSamplesReceived, 3)
        XCTAssertEqual(core.bufferedSamplesCount, 3)
        XCTAssertEqual(latestSample.sampleSequenceNumber, 2)
        XCTAssertEqual(latestSample.hrBPM, 72)
        XCTAssertEqual(core.streamDescriptor?.streamName, "HR")
    }

    func testUploadChunkContainsSessionAndBufferedSamples() async throws {
        let firstTimestamp = Date(timeIntervalSince1970: 200)
        let secondTimestamp = Date(timeIntervalSince1970: 201)
        let samples = [
            HeartRateSample(
                hrBPM: 80,
                collectorReceivedAtUTC: firstTimestamp,
                deviceTimestampRaw: firstTimestamp.addingTimeInterval(-0.5),
                sourceTimestampKind: .deviceReported,
                sampleSequenceNumber: 0
            ),
            HeartRateSample(
                hrBPM: 81,
                collectorReceivedAtUTC: secondTimestamp,
                deviceTimestampRaw: secondTimestamp.addingTimeInterval(-0.5),
                sourceTimestampKind: .deviceReported,
                sampleSequenceNumber: 1
            )
        ]

        let core = CollectorCore(
            adapter: MockDeviceAdapter(
                hrProvider: ImmediateHeartRateProvider(samples: samples)
            ),
            transport: TestTransport()
        )

        core.selectDevice()
        await core.startCollection()

        let bufferedSamplesReady = await waitUntil {
            core.bufferedSamplesCount >= 2
        }
        XCTAssertTrue(bufferedSamplesReady, "Timed out waiting for buffered HR samples")

        let session = try XCTUnwrap(core.activeSession)
        let chunk = try XCTUnwrap(core.prepareUploadChunk())

        XCTAssertEqual(chunk.sessionID, session.sessionID)
        XCTAssertEqual(chunk.streamName, "HR")
        XCTAssertEqual(chunk.streamType, "hr")
        XCTAssertEqual(chunk.samples.count, 2)
        XCTAssertEqual(chunk.samples[0].collectorReceivedAtUTC, firstTimestamp)
        XCTAssertEqual(chunk.samples[1].collectorReceivedAtUTC, secondTimestamp)
        XCTAssertEqual(chunk.samples[0].deviceTimestampRaw, firstTimestamp.addingTimeInterval(-0.5))
        XCTAssertEqual(chunk.collectionMode, .live)
        XCTAssertEqual(core.bufferedSamplesCount, 0)
        XCTAssertEqual(core.lastPreparedChunk?.samples.count, 2)
    }

    func testRealPolarFixtureMapsToCanonicalPayload() throws {
        let sample = HeartRateSample(
            hrBPM: 71,
            collectorReceivedAtUTC: Date(timeIntervalSince1970: 1_000),
            deviceTimestampRaw: nil,
            sourceTimestampKind: .collectorObserved,
            sampleSequenceNumber: 0,
            streamData: PolarHrStreamData(
                hr: 71,
                ppgQuality: 0,
                correctedHr: 0,
                rrsMs: [],
                rrAvailable: false,
                contactStatus: false,
                contactStatusSupported: false
            )
        )

        let chunk = UploadChunk(
            sessionID: UUID(uuidString: "2E923C96-FB44-4C3A-B948-14A0E6DB4D11")!,
            streamName: "HR",
            streamType: "hr",
            chunkID: UUID(uuidString: "6D8B2D67-3C4E-4A12-9307-D7BF4AF80A4A")!,
            chunkSequenceNumber: 1,
            createdAtUTC: Date(timeIntervalSince1970: 1_001),
            samples: [sample],
            collectionMode: .live
        )

        let payload = try XCTUnwrap(chunk.makeCanonicalRequest(uploadedAtUTC: Date(timeIntervalSince1970: 1_002)))
        let mapped = try XCTUnwrap(payload.payload.samples.first)

        XCTAssertEqual(mapped.hr, 71)
        XCTAssertEqual(mapped.ppgQuality, 0)
        XCTAssertEqual(mapped.correctedHr, 0)
        XCTAssertEqual(mapped.rrsMs, [])
        XCTAssertFalse(mapped.rrAvailable)
        XCTAssertFalse(mapped.contactStatus)
        XCTAssertFalse(mapped.contactStatusSupported)
        XCTAssertEqual(payload.transport.payloadSchema, "polar.hr")
        XCTAssertEqual(payload.transport.payloadVersion, "1.0")
    }

    func testHeartRateSampleCarriesTimestampMetadata() {
        let now = Date()
        let sample = HeartRateSample(
            hrBPM: 68,
            collectorReceivedAtUTC: now,
            deviceTimestampRaw: now.addingTimeInterval(-1),
            sourceTimestampKind: .deviceReported,
            sampleSequenceNumber: 42
        )

        XCTAssertEqual(sample.hrBPM, 68)
        XCTAssertEqual(sample.collectorReceivedAtUTC, now)
        XCTAssertEqual(sample.deviceTimestampRaw, now.addingTimeInterval(-1))
        XCTAssertEqual(sample.sourceTimestampKind, .deviceReported)
        XCTAssertEqual(sample.sampleSequenceNumber, 42)
    }

    func testSessionStopSetsStoppedAtUTC() async {
        let core = CollectorCore(
            adapter: MockDeviceAdapter(
                hrProvider: ImmediateHeartRateProvider(
                    samples: [
                        HeartRateSample(
                            hrBPM: 67,
                            collectorReceivedAtUTC: Date(),
                            deviceTimestampRaw: nil,
                            sourceTimestampKind: .collectorObserved,
                            sampleSequenceNumber: 0
                        )
                    ]
                )
            ),
            transport: TestTransport()
        )

        core.selectDevice()
        await core.startCollection()
        core.stopCollection()

        XCTAssertNotNil(core.activeSession?.stoppedAtUTC)
    }

    func testUploadSuccessUpdatesState() async {
        let core = CollectorCore(
            adapter: MockDeviceAdapter(
                hrProvider: ImmediateHeartRateProvider(
                    samples: [
                        HeartRateSample(
                            hrBPM: 71,
                            collectorReceivedAtUTC: Date(),
                            deviceTimestampRaw: nil,
                            sourceTimestampKind: .collectorObserved,
                            sampleSequenceNumber: 0
                        )
                    ]
                )
            ),
            transport: TestTransport(shouldFailUpload: false)
        )

        core.selectDevice()
        await core.startCollection()
        let bufferedSamplesReady = await waitUntil {
            core.bufferedSamplesCount >= 1
        }
        XCTAssertTrue(bufferedSamplesReady, "Timed out waiting for buffered HR samples before upload")
        _ = core.prepareUploadChunk()
        await core.uploadLastPreparedChunk()

        XCTAssertEqual(core.uploadStatus, .success)
        XCTAssertNil(core.lastErrorMessage)
    }

    func testUploadFailureUpdatesState() async {
        let core = CollectorCore(
            adapter: MockDeviceAdapter(
                hrProvider: ImmediateHeartRateProvider(
                    samples: [
                        HeartRateSample(
                            hrBPM: 71,
                            collectorReceivedAtUTC: Date(),
                            deviceTimestampRaw: nil,
                            sourceTimestampKind: .collectorObserved,
                            sampleSequenceNumber: 0
                        )
                    ]
                )
            ),
            transport: TestTransport(shouldFailUpload: true)
        )

        core.selectDevice()
        await core.startCollection()
        let bufferedSamplesReady = await waitUntil {
            core.bufferedSamplesCount >= 1
        }
        XCTAssertTrue(bufferedSamplesReady, "Timed out waiting for buffered HR samples before upload")
        _ = core.prepareUploadChunk()
        await core.uploadLastPreparedChunk()

        XCTAssertEqual(core.uploadStatus, .failure)
        XCTAssertNotNil(core.lastErrorMessage)
    }
}
