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
                model: "Verity Sense"
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
                streamProfile: PolarHrStreamProfile.live,
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

    func testCanonicalMappingIncludesSessionStreamAndTransportMetadata() throws {
        let chunk = UploadChunk(
            sessionID: UUID(uuidString: "2E923C96-FB44-4C3A-B948-14A0E6DB4D11")!,
            streamName: "HR",
            streamType: "hr",
            streamID: "stream-hr-2e923c96-fb44-4c3a-b948-14a0e6db4d11",
            chunkID: UUID(uuidString: "6D8B2D67-3C4E-4A12-9307-D7BF4AF80A4A")!,
            chunkSequenceNumber: 1,
            createdAtUTC: Date(timeIntervalSince1970: 1_001),
            samples: [makeSample(hr: 71, receivedAt: Date(timeIntervalSince1970: 1_000), sequence: 0)],
            collectionMode: .live,
            streamProfile: PolarHrStreamProfile.live,
            sourceDeviceID: nil
        )

        let payload = try XCTUnwrap(
            chunk.makeCanonicalRequest(uploadedAtUTC: Date(timeIntervalSince1970: 1_002))
        )

        XCTAssertEqual(payload.chunkID, "6d8b2d67-3c4e-4a12-9307-d7bf4af80a4a")
        XCTAssertEqual(payload.sessionID, "2e923c96-fb44-4c3a-b948-14a0e6db4d11")
        XCTAssertEqual(payload.streamID, "stream-hr-2e923c96-fb44-4c3a-b948-14a0e6db4d11")
        XCTAssertEqual(payload.streamType, "hr")
        XCTAssertEqual(payload.sequence, 1)
        XCTAssertEqual(payload.source.vendor, "polar")
        XCTAssertEqual(payload.source.deviceModel, "verity_sense")
        XCTAssertEqual(payload.collection.mode, "online_live")
        XCTAssertEqual(payload.transport.payloadSchema, "polar.hr")
        XCTAssertEqual(payload.transport.payloadVersion, "1.0")
        XCTAssertEqual(payload.time.firstSampleReceivedAtCollector, "1970-01-01T00:16:40.000Z")
        XCTAssertEqual(payload.time.deviceTimeReference, "collector:collectorObserved")
    }

    func testCanonicalMappingUsesFirstSampleTimestampForChunkTime() throws {
        let first = makeSample(hr: 70, receivedAt: Date(timeIntervalSince1970: 1_000), sequence: 0)
        let second = makeSample(hr: 72, receivedAt: Date(timeIntervalSince1970: 1_005), sequence: 1)
        let chunk = UploadChunk(
            sessionID: UUID(),
            streamName: "HR",
            streamType: "hr",
            streamID: "stream-hr-session",
            chunkID: UUID(),
            chunkSequenceNumber: 1,
            createdAtUTC: Date(),
            samples: [first, second],
            collectionMode: .live,
            streamProfile: PolarHrStreamProfile.live,
            sourceDeviceID: nil
        )

        let payload = try XCTUnwrap(chunk.makeCanonicalRequest(uploadedAtUTC: Date(timeIntervalSince1970: 1_010)))
        XCTAssertEqual(payload.time.firstSampleReceivedAtCollector, "1970-01-01T00:16:40.000Z")
    }

    func testCanonicalMappingUsesFallbackPayloadForMockSamples() throws {
        let chunk = UploadChunk(
            sessionID: UUID(),
            streamName: "HR",
            streamType: "hr",
            streamID: "stream-hr-session",
            chunkID: UUID(),
            chunkSequenceNumber: 1,
            createdAtUTC: Date(),
            samples: [makeSample(hr: 68, receivedAt: Date(), sequence: 0)],
            collectionMode: .live,
            streamProfile: PolarHrStreamProfile.live,
            sourceDeviceID: nil
        )

        let payload = try XCTUnwrap(chunk.makeCanonicalRequest())
        let mapped = try XCTUnwrap(payload.payload.samples.first)

        XCTAssertEqual(mapped.hr, 68)
        XCTAssertFalse(mapped.receivedAtCollector.isEmpty)
        XCTAssertEqual(mapped.ppgQuality, 0)
        XCTAssertEqual(mapped.correctedHr, 0)
        XCTAssertEqual(mapped.rrsMs, [])
        XCTAssertFalse(mapped.rrAvailable)
    }

    func testCanonicalMappingPreservesPolarStreamDataWhenPresent() throws {
        let polarData = PolarHrStreamData(
            hr: 71,
            ppgQuality: 1,
            correctedHr: 70,
            rrsMs: [820, 810],
            rrAvailable: true,
            contactStatus: true,
            contactStatusSupported: true
        )
        let sample = makeSample(
            hr: 71,
            receivedAt: Date(timeIntervalSince1970: 1_000),
            sequence: 0,
            streamData: polarData
        )
        let chunk = UploadChunk(
            sessionID: UUID(),
            streamName: "HR",
            streamType: "hr",
            streamID: "stream-hr-session",
            chunkID: UUID(),
            chunkSequenceNumber: 1,
            createdAtUTC: Date(),
            samples: [sample],
            collectionMode: .live,
            streamProfile: PolarHrStreamProfile.live,
            sourceDeviceID: nil
        )

        let payload = try XCTUnwrap(chunk.makeCanonicalRequest(uploadedAtUTC: Date(timeIntervalSince1970: 1_002)))
        let mapped = try XCTUnwrap(payload.payload.samples.first)

        XCTAssertEqual(mapped.hr, 71)
        XCTAssertEqual(mapped.receivedAtCollector, "1970-01-01T00:16:40.000Z")
        XCTAssertEqual(mapped.ppgQuality, 1)
        XCTAssertEqual(mapped.correctedHr, 70)
        XCTAssertEqual(mapped.rrsMs, [820, 810])
        XCTAssertTrue(mapped.rrAvailable)
        XCTAssertTrue(mapped.contactStatus)
        XCTAssertTrue(mapped.contactStatusSupported)
    }

    func testPolarHrStreamProfileMatchesContractDefaults() {
        let profile = PolarHrStreamProfile.live

        XCTAssertEqual(profile.streamType, "hr")
        XCTAssertEqual(profile.source.vendor, "polar")
        XCTAssertEqual(profile.source.deviceModel, "verity_sense")
        XCTAssertEqual(profile.collection.mode, "online_live")
        XCTAssertEqual(profile.transport.payloadSchema, "polar.hr")
    }
}
