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
            transport: MockCollectorTransport()
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
            transport: MockCollectorTransport()
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
            transport: MockCollectorTransport()
        )

        core.selectDevice()
        await core.startCollection()

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
            transport: MockCollectorTransport()
        )

        core.selectDevice()
        await core.startCollection()

        let session = try XCTUnwrap(core.activeSession)
        let chunk = try XCTUnwrap(core.prepareUploadChunk())

        XCTAssertEqual(chunk.sessionID, session.sessionID)
        XCTAssertEqual(chunk.streamName, "HR")
        XCTAssertEqual(chunk.samples.count, 2)
        XCTAssertEqual(chunk.samples[0].collectorReceivedAtUTC, firstTimestamp)
        XCTAssertEqual(chunk.samples[1].collectorReceivedAtUTC, secondTimestamp)
        XCTAssertEqual(chunk.samples[0].deviceTimestampRaw, firstTimestamp.addingTimeInterval(-0.5))
        XCTAssertEqual(chunk.collectionMode, .live)
        XCTAssertEqual(core.bufferedSamplesCount, 0)
        XCTAssertEqual(core.lastPreparedChunk?.samples.count, 2)
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
            transport: MockCollectorTransport()
        )

        core.selectDevice()
        await core.startCollection()
        core.stopCollection()

        XCTAssertNotNil(core.activeSession?.stoppedAtUTC)
    }
}
