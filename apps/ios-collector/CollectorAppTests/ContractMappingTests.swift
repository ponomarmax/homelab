import XCTest
@testable import CollectorApp

final class ContractMappingTests: XCTestCase {
    func testHeartRateChunkBuilderPreservesSessionAndStreamMetadata() throws {
        let sessionID = UUID(uuidString: "5B6D87A5-95EF-4D4B-8893-E2F4B3946C72")!
        let session = CollectionSession(
            sessionID: sessionID,
            device: CollectorDevice(
                id: "mock-device",
                name: "Mock Device",
                vendor: "Polar",
                model: "H10"
            ),
            collectionMode: .live,
            startedAtUTC: Date(timeIntervalSince1970: 900),
            supportedStreams: [.heartRate]
        )
        let descriptor = StreamDescriptor(
            streamName: "HR",
            streamType: "hr",
            unit: "bpm",
            source: "mock",
            sampleKind: "scalar"
        )
        let sample = makeSample(hr: 73, receivedAt: Date(timeIntervalSince1970: 1_000), sequence: 0)

        let chunk = try XCTUnwrap(
            HeartRateChunkBuilder().buildChunk(
                session: session,
                streamDescriptor: descriptor,
                streamProfile: PolarStreamProfile.hrLive,
                chunkSequenceNumber: 7,
                samples: [sample],
                createdAtUTC: Date(timeIntervalSince1970: 1_001)
            )
        )

        XCTAssertEqual(chunk.sessionID, sessionID)
        XCTAssertEqual(chunk.streamName, "HR")
        XCTAssertEqual(chunk.streamType, "hr")
        XCTAssertEqual(chunk.streamID, "stream-hr-\(sessionID.uuidString.lowercased())")
        XCTAssertEqual(chunk.chunkSequenceNumber, 7)
        XCTAssertEqual(chunk.collectionMode, .live)
        XCTAssertEqual(chunk.samples.count, 1)
    }

    func testCanonicalHrMappingIncludesSessionStreamAndTransportMetadata() throws {
        let chunk = UploadChunk(
            sessionID: UUID(uuidString: "2E923C96-FB44-4C3A-B948-14A0E6DB4D11")!,
            streamName: "HR",
            streamType: "hr",
            streamID: "stream-hr-2e923c96-fb44-4c3a-b948-14a0e6db4d11",
            chunkID: UUID(uuidString: "6D8B2D67-3C4E-4A12-9307-D7BF4AF80A4A")!,
            chunkSequenceNumber: 1,
            createdAtUTC: Date(timeIntervalSince1970: 1_001),
            samples: [
                makeSample(
                    hr: 71,
                    receivedAt: Date(timeIntervalSince1970: 1_000),
                    sequence: 0,
                    streamData: PolarHrStreamData(
                        hr: 71,
                        ppgQuality: 1,
                        correctedHr: 70,
                        rrsMs: [810, 820],
                        rrAvailable: true,
                        contactStatus: true,
                        contactStatusSupported: true
                    )
                )
            ],
            collectionMode: .live,
            streamProfile: PolarStreamProfile.hrLive,
            sourceDeviceID: "h10-123"
        )

        let request = try XCTUnwrap(
            chunk.makeCanonicalRequest(uploadedAtUTC: Date(timeIntervalSince1970: 1_002))
        )

        XCTAssertEqual(request.chunkID, "6d8b2d67-3c4e-4a12-9307-d7bf4af80a4a")
        XCTAssertEqual(request.sessionID, "2e923c96-fb44-4c3a-b948-14a0e6db4d11")
        XCTAssertEqual(request.streamID, "stream-hr-2e923c96-fb44-4c3a-b948-14a0e6db4d11")
        XCTAssertEqual(request.streamType, "hr")
        XCTAssertEqual(request.sequence, 1)
        XCTAssertEqual(request.source.vendor, "polar")
        XCTAssertEqual(request.source.deviceModel, "Polar H10")
        XCTAssertEqual(request.source.deviceID, "h10-123")
        XCTAssertEqual(request.collection.mode, "online_live")
        XCTAssertEqual(request.transport.payloadSchema, "polar.hr")
        XCTAssertEqual(request.transport.payloadVersion, "1.0")
        XCTAssertEqual(request.time.firstSampleReceivedAtCollector, "1970-01-01T00:16:40.000Z")
        XCTAssertEqual(request.time.deviceTimeReference, "collector:collectorObserved")

        guard case .hr(let payload) = request.payload else {
            return XCTFail("Expected hr payload")
        }
        let sample = try XCTUnwrap(payload.samples.first)
        XCTAssertEqual(sample.receivedAtCollector, "1970-01-01T00:16:40.000Z")
        XCTAssertEqual(sample.hr, 71)
        XCTAssertEqual(sample.rrsMs, [810, 820])
        XCTAssertTrue(sample.rrAvailable)
    }

    func testCanonicalEcgMappingIncludesDeviceTimeAndCollectorReceiveTime() throws {
        let sample = HeartRateSample(
            stream: .ecg,
            collectorReceivedAtUTC: Date(timeIntervalSince1970: 2_000),
            sourceTimestampKind: .deviceReported,
            sampleSequenceNumber: 0,
            payload: .ecg(
                PolarEcgSampleData(
                    deviceTimeNS: 123_456_789,
                    ecgUv: 145,
                    sampleRateHz: 130
                )
            )
        )

        let chunk = UploadChunk(
            sessionID: UUID(),
            streamName: "ECG",
            streamType: "ecg",
            streamID: "stream-ecg-session",
            chunkID: UUID(),
            chunkSequenceNumber: 1,
            createdAtUTC: Date(),
            samples: [sample],
            collectionMode: .live,
            streamProfile: PolarStreamProfile.ecgLive,
            sourceDeviceID: nil
        )

        let request = try XCTUnwrap(chunk.makeCanonicalRequest())
        guard case .ecg(let payload) = request.payload else {
            return XCTFail("Expected ecg payload")
        }

        let mapped = try XCTUnwrap(payload.samples.first)
        XCTAssertEqual(mapped.deviceTimeNS, 123_456_789)
        XCTAssertEqual(mapped.ecgUv, 145)
        XCTAssertEqual(mapped.receivedAtCollector, "1970-01-01T00:33:20.000Z")
        XCTAssertEqual(payload.sampleRateHz, 130)
    }

    func testCanonicalAccMappingIncludesDeviceTimeAndCollectorReceiveTime() throws {
        let sample = HeartRateSample(
            stream: .accelerometer,
            collectorReceivedAtUTC: Date(timeIntervalSince1970: 3_000),
            sourceTimestampKind: .deviceReported,
            sampleSequenceNumber: 0,
            payload: .acc(
                PolarAccSampleData(
                    deviceTimeNS: 987_654_321,
                    xMg: 120,
                    yMg: -45,
                    zMg: 1024,
                    sampleRateHz: 200,
                    rangeMg: 8000
                )
            )
        )

        let chunk = UploadChunk(
            sessionID: UUID(),
            streamName: "ACC",
            streamType: "acc",
            streamID: "stream-acc-session",
            chunkID: UUID(),
            chunkSequenceNumber: 1,
            createdAtUTC: Date(),
            samples: [sample],
            collectionMode: .live,
            streamProfile: PolarStreamProfile.accLive,
            sourceDeviceID: nil
        )

        let request = try XCTUnwrap(chunk.makeCanonicalRequest())
        guard case .acc(let payload) = request.payload else {
            return XCTFail("Expected acc payload")
        }

        let mapped = try XCTUnwrap(payload.samples.first)
        XCTAssertEqual(mapped.deviceTimeNS, 987_654_321)
        XCTAssertEqual(mapped.xMg, 120)
        XCTAssertEqual(mapped.yMg, -45)
        XCTAssertEqual(mapped.zMg, 1024)
        XCTAssertEqual(mapped.receivedAtCollector, "1970-01-01T00:50:00.000Z")
        XCTAssertEqual(payload.sampleRateHz, 200)
        XCTAssertEqual(payload.rangeMg, 8000)
    }

    func testCanonicalBatteryMappingSupportsCallbackSnapshotAndUnavailable() throws {
        let callbackSample = PolarCollectorEventMapper.mapBattery(
            eventType: .callbackUpdate,
            sequenceNumber: 0,
            receivedAt: Date(timeIntervalSince1970: 4_000),
            levelPercent: 88,
            chargeState: "charging",
            powerSources: ["battery_present", "wired_connected"],
            sdkRaw: "battery_level_callback",
            unavailableReason: nil
        )

        let pollSample = PolarCollectorEventMapper.mapBattery(
            eventType: .pollSnapshot,
            sequenceNumber: 1,
            receivedAt: Date(timeIntervalSince1970: 4_100),
            levelPercent: 87,
            chargeState: "discharging_active",
            powerSources: ["battery_present"],
            sdkRaw: "trigger=periodic_poll",
            unavailableReason: nil
        )

        let unavailableSample = PolarCollectorEventMapper.mapBattery(
            eventType: .batteryUnavailable,
            sequenceNumber: 2,
            receivedAt: Date(timeIntervalSince1970: 4_200),
            levelPercent: nil,
            chargeState: nil,
            powerSources: nil,
            sdkRaw: "trigger=feature_ready",
            unavailableReason: "battery feature unavailable"
        )

        let callbackChunk = UploadChunk(
            sessionID: UUID(),
            streamName: "Battery",
            streamType: "unknown",
            streamID: "stream-battery-session",
            chunkID: UUID(),
            chunkSequenceNumber: 1,
            createdAtUTC: Date(),
            samples: [callbackSample],
            collectionMode: .live,
            streamProfile: PolarStreamProfile.batteryLive,
            sourceDeviceID: nil
        )

        let pollChunk = UploadChunk(
            sessionID: UUID(),
            streamName: "Battery",
            streamType: "unknown",
            streamID: "stream-battery-session",
            chunkID: UUID(),
            chunkSequenceNumber: 2,
            createdAtUTC: Date(),
            samples: [pollSample],
            collectionMode: .live,
            streamProfile: PolarStreamProfile.batteryLive,
            sourceDeviceID: nil
        )

        let unavailableChunk = UploadChunk(
            sessionID: UUID(),
            streamName: "Battery",
            streamType: "unknown",
            streamID: "stream-battery-session",
            chunkID: UUID(),
            chunkSequenceNumber: 3,
            createdAtUTC: Date(),
            samples: [unavailableSample],
            collectionMode: .live,
            streamProfile: PolarStreamProfile.batteryLive,
            sourceDeviceID: nil
        )

        let callbackRequest = try XCTUnwrap(callbackChunk.makeCanonicalRequest())
        let pollRequest = try XCTUnwrap(pollChunk.makeCanonicalRequest())
        let unavailableRequest = try XCTUnwrap(unavailableChunk.makeCanonicalRequest())

        guard case .battery(let callbackPayload) = callbackRequest.payload else {
            return XCTFail("Expected battery payload")
        }
        guard case .battery(let pollPayload) = pollRequest.payload else {
            return XCTFail("Expected battery payload")
        }
        guard case .battery(let unavailablePayload) = unavailableRequest.payload else {
            return XCTFail("Expected battery payload")
        }

        XCTAssertEqual(callbackPayload.eventType, .callbackUpdate)
        XCTAssertEqual(callbackPayload.battery?.levelPercent, 88)
        XCTAssertEqual(callbackPayload.battery?.chargeState, "charging")

        XCTAssertEqual(pollPayload.eventType, .pollSnapshot)
        XCTAssertEqual(pollPayload.battery?.levelPercent, 87)
        XCTAssertEqual(pollPayload.battery?.chargeState, "discharging_active")

        XCTAssertEqual(unavailablePayload.eventType, .batteryUnavailable)
        XCTAssertNil(unavailablePayload.battery?.levelPercent)
        XCTAssertEqual(unavailablePayload.unavailableReason, "battery feature unavailable")
    }

    func testPolarStreamProfilesMatchContractDefaults() {
        XCTAssertEqual(PolarStreamProfile.hrLive.streamType, "hr")
        XCTAssertEqual(PolarStreamProfile.hrLive.transport.payloadSchema, "polar.hr")

        XCTAssertEqual(PolarStreamProfile.ecgLive.streamType, "ecg")
        XCTAssertEqual(PolarStreamProfile.ecgLive.transport.payloadSchema, "polar.ecg")

        XCTAssertEqual(PolarStreamProfile.accLive.streamType, "acc")
        XCTAssertEqual(PolarStreamProfile.accLive.transport.payloadSchema, "polar.acc")

        XCTAssertEqual(PolarStreamProfile.batteryLive.streamType, "unknown")
        XCTAssertEqual(PolarStreamProfile.batteryLive.transport.payloadSchema, "polar.device_battery")
    }
}
