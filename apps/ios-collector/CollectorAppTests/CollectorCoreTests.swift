import XCTest
@testable import CollectorApp

@MainActor
final class CollectorCoreTests: XCTestCase {
    func testMockHeartRateProviderEmitsSamples() async {
        let provider = MockHeartRateStreamProvider(
            values: [61, 62],
            intervalNanoseconds: 20_000_000
        )
        let expectation = expectation(description: "Provider emits samples")
        expectation.expectedFulfillmentCount = 2

        provider.start { sample in
            XCTAssertTrue([61, 62].contains(sample.value))
            expectation.fulfill()
        }

        await fulfillment(of: [expectation], timeout: 1.0)
        provider.stop()
    }

    func testCollectorCoreStartsAndStopsSession() async {
        let core = CollectorCore(
            adapter: MockDeviceAdapter(
                hrProvider: MockHeartRateStreamProvider(intervalNanoseconds: 10_000_000)
            ),
            transport: MockCollectorTransport()
        )

        core.selectDevice()
        XCTAssertEqual(core.status, .deviceSelected)

        await core.startCollection()
        XCTAssertEqual(core.status, .collecting)
        XCTAssertNotNil(core.activeSession)
        XCTAssertEqual(core.defaultCollectionMode, .live)

        core.stopCollection()
        XCTAssertEqual(core.status, .stopped)
        XCTAssertNil(core.activeSession)
    }

    func testLatestHeartRateAndSampleCountUpdate() async {
        let core = CollectorCore(
            adapter: MockDeviceAdapter(
                hrProvider: MockHeartRateStreamProvider(
                    values: [70, 71, 72],
                    intervalNanoseconds: 15_000_000
                )
            ),
            transport: MockCollectorTransport()
        )

        core.selectDevice()
        await core.startCollection()

        try? await Task.sleep(nanoseconds: 80_000_000)

        XCTAssertNotNil(core.latestHeartRateSample)
        XCTAssertGreaterThanOrEqual(core.totalSamplesReceived, 2)
        XCTAssertNotNil(core.preparedSessionBoundary)
        XCTAssertNotNil(core.lastPreparedChunkBoundary)

        core.stopCollection()
    }

    func testHeartRateSampleCarriesTimestampMetadata() {
        let now = Date()
        let sample = HeartRateSample(
            value: 68,
            collectorReceivedAtUTC: now,
            rawDeviceTimestamp: now.addingTimeInterval(-1),
            sourceTimestampKind: .deviceReported,
            sampleSequenceNumber: 42
        )

        XCTAssertEqual(sample.value, 68)
        XCTAssertEqual(sample.collectorReceivedAtUTC, now)
        XCTAssertEqual(sample.rawDeviceTimestamp, now.addingTimeInterval(-1))
        XCTAssertEqual(sample.sourceTimestampKind, .deviceReported)
        XCTAssertEqual(sample.sampleSequenceNumber, 42)
    }
}
