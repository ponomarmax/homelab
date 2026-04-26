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

    func testPolarMapperBuildsHeartRateSampleWithRrData() {
        let mapped = PolarCollectorEventMapper.mapHr(
            entry: (
                hr: 74,
                ppgQuality: 2,
                correctedHr: 73,
                rrsMs: [800, 810],
                rrAvailable: true,
                contactStatus: true,
                contactStatusSupported: true
            ),
            sequenceNumber: 3,
            receivedAt: Date(timeIntervalSince1970: 10)
        )

        XCTAssertEqual(mapped.stream, .heartRate)
        XCTAssertEqual(mapped.hrBPM, 74)
        XCTAssertEqual(mapped.streamData?.rrsMs, [800, 810])
        XCTAssertEqual(mapped.sampleSequenceNumber, 3)
        XCTAssertEqual(mapped.collectorReceivedAtUTC, Date(timeIntervalSince1970: 10))
    }

    func testPolarMapperBuildsEcgSampleWithDeviceTimeNs() {
        let mapped = PolarCollectorEventMapper.mapEcg(
            sample: (timeStamp: 555_000, voltage: 165),
            sequenceNumber: 1,
            receivedAt: Date(timeIntervalSince1970: 11),
            settings: PolarStreamSettingsMetadata(sampleRateHz: 130, rangeMg: nil)
        )

        XCTAssertEqual(mapped.stream, .ecg)
        XCTAssertEqual(mapped.ecgData?.deviceTimeNS, 555_000)
        XCTAssertEqual(mapped.ecgData?.ecgUv, 165)
        XCTAssertEqual(mapped.ecgData?.sampleRateHz, 130)
        XCTAssertEqual(mapped.collectorReceivedAtUTC, Date(timeIntervalSince1970: 11))
    }

    func testPolarMapperBuildsAccSampleWithDeviceTimeNs() {
        let mapped = PolarCollectorEventMapper.mapAcc(
            sample: (timeStamp: 777_000, x: 100, y: -40, z: 1020),
            sequenceNumber: 2,
            receivedAt: Date(timeIntervalSince1970: 12),
            settings: PolarStreamSettingsMetadata(sampleRateHz: 200, rangeMg: 8000)
        )

        XCTAssertEqual(mapped.stream, .accelerometer)
        XCTAssertEqual(mapped.accData?.deviceTimeNS, 777_000)
        XCTAssertEqual(mapped.accData?.xMg, 100)
        XCTAssertEqual(mapped.accData?.yMg, -40)
        XCTAssertEqual(mapped.accData?.zMg, 1020)
        XCTAssertEqual(mapped.accData?.sampleRateHz, 200)
        XCTAssertEqual(mapped.accData?.rangeMg, 8000)
        XCTAssertEqual(mapped.collectorReceivedAtUTC, Date(timeIntervalSince1970: 12))
    }

    func testPolarMapperBuildsBatterySamplesForCallbackPollAndUnavailable() {
        let callback = PolarCollectorEventMapper.mapBattery(
            eventType: .callbackUpdate,
            sequenceNumber: 0,
            receivedAt: Date(timeIntervalSince1970: 13),
            levelPercent: 91,
            chargeState: "charging",
            powerSources: ["battery_present"],
            sdkRaw: "battery_level_callback",
            unavailableReason: nil
        )
        let poll = PolarCollectorEventMapper.mapBattery(
            eventType: .pollSnapshot,
            sequenceNumber: 1,
            receivedAt: Date(timeIntervalSince1970: 14),
            levelPercent: 90,
            chargeState: "discharging_active",
            powerSources: ["battery_present"],
            sdkRaw: "trigger=periodic_poll",
            unavailableReason: nil
        )
        let unavailable = PolarCollectorEventMapper.mapBattery(
            eventType: .batteryUnavailable,
            sequenceNumber: 2,
            receivedAt: Date(timeIntervalSince1970: 15),
            levelPercent: nil,
            chargeState: nil,
            powerSources: nil,
            sdkRaw: "trigger=feature_ready",
            unavailableReason: "battery feature unavailable"
        )

        XCTAssertEqual(callback.batteryData?.eventType, .callbackUpdate)
        XCTAssertEqual(callback.batteryData?.levelPercent, 91)
        XCTAssertEqual(poll.batteryData?.eventType, .pollSnapshot)
        XCTAssertEqual(poll.batteryData?.levelPercent, 90)
        XCTAssertEqual(unavailable.batteryData?.eventType, .batteryUnavailable)
        XCTAssertEqual(unavailable.batteryData?.unavailableReason, "battery feature unavailable")
    }
}
