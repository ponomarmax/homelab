import XCTest
@testable import CollectorApp

@MainActor
final class DeviceAdapterTests: XCTestCase {
    func testMockAdapterScanReturnsConfiguredDevice() async throws {
        let device = CollectorDevice(
            id: "mock-1",
            name: "Mock Polar Verity Sense",
            vendor: "Polar",
            model: "Verity Sense"
        )
        let adapter = MockDeviceAdapter(deviceIdentity: device)

        let scanned = try await adapter.scanDevices()

        XCTAssertEqual(scanned, [device])
    }

    func testMockAdapterConnectAndDisconnectStateTransitions() async throws {
        let adapter = MockDeviceAdapter(hrProvider: MockHeartRateStreamProvider(intervalNanoseconds: 10_000_000))
        try adapter.selectDevice(adapter.deviceIdentity)
        XCTAssertEqual(adapter.connectionState, .deviceSelected)

        try await adapter.connect()
        XCTAssertEqual(adapter.connectionState, .connected)

        adapter.disconnect()
        XCTAssertEqual(adapter.connectionState, .disconnected)
    }

    func testMockAdapterHidesHeartRateProviderWhenStreamUnavailable() {
        let adapter = MockDeviceAdapter(availableStreams: [])
        XCTAssertNil(adapter.heartRateStreamProvider())
    }

    func testMockHeartRateProviderEmitsDeterministicValues() async {
        let provider = MockHeartRateStreamProvider(
            values: [61, 62],
            intervalNanoseconds: 20_000_000
        )
        let expectation = expectation(description: "Provider emits samples")
        expectation.expectedFulfillmentCount = 2
        let emittedValues = LockedValueBox<[Int]>([])

        provider.start { sample in
            emittedValues.withValue { values in
                values.append(sample.hrBPM)
            }
            expectation.fulfill()
        }

        await fulfillment(of: [expectation], timeout: 1.0)
        provider.stop()
        let values = emittedValues.withValue { $0 }
        XCTAssertEqual(values, [61, 62])
    }
}
