import XCTest
@testable import CollectorApp

final class TransportTests: XCTestCase {
    func testTransportReportsMockModeWhenEndpointIsMissing() {
        let transport = MockCollectorTransport()

        XCTAssertFalse(transport.isNetworkUploadConfigured)
        XCTAssertEqual(transport.uploadDestinationDescription, "mock://local-only (no server request)")
    }

    func testPrepareUploadChunkReturnsNilForEmptySamples() {
        let transport = MockCollectorTransport()
        let session = CollectionSession(
            sessionID: UUID(uuidString: "D4E6016A-C568-4E2A-8418-E7ED410E5A02")!,
            device: CollectorDevice(
                id: "mock-device",
                name: "Mock Device",
                vendor: "Polar",
                model: "Verity Sense"
            ),
            collectionMode: .live,
            startedAtUTC: Date(timeIntervalSince1970: 100),
            supportedStreams: [.heartRate]
        )
        let streamDescriptor = transport.makeStreamDescriptor(for: .heartRate, source: "mock")

        let chunk = transport.prepareUploadChunk(
            session: session,
            streamDescriptor: streamDescriptor,
            chunkSequenceNumber: 1,
            samples: []
        )

        XCTAssertNil(chunk)
    }

    func testUploadUsesConfiguredEndpointAndBuildsPostRequest() async throws {
        let capturedRequest = LockedValueBox<URLRequest?>(nil)
        let endpoint = URL(string: "http://localhost:8080/upload-chunk")!
        let uploadAck = UploadAck(
            accepted: true,
            status: "accepted",
            chunkID: "c1",
            sessionID: "s1",
            streamID: "stream-hr-s1",
            receivedAtServer: "2024-01-01T00:00:00.000Z",
            storage: UploadAck.UploadStorage(rawPersisted: true, storagePath: "raw/s1.jsonl"),
            message: nil
        )
        let ackData = try JSONEncoder().encode(uploadAck)
        let response = HTTPURLResponse(
            url: endpoint,
            statusCode: 202,
            httpVersion: nil,
            headerFields: nil
        )!

        let transport = MockCollectorTransport(
            uploadEndpoint: endpoint,
            nowProvider: { Date(timeIntervalSince1970: 1_002) },
            httpDataProvider: { request in
                capturedRequest.withValue { value in
                    value = request
                }
                return (ackData, response)
            }
        )

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

        let ack = try await transport.upload(chunk: chunk)
        let request = capturedRequest.withValue { $0 }

        XCTAssertEqual(ack.status, "accepted")
        XCTAssertEqual(request?.url, endpoint)
        XCTAssertEqual(request?.httpMethod, "POST")
        XCTAssertEqual(request?.value(forHTTPHeaderField: "Accept"), "application/json")
        XCTAssertEqual(request?.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertEqual(request?.value(forHTTPHeaderField: "X-User-ID"), "2")
        XCTAssertNotNil(request?.httpBody)

        let body = try XCTUnwrap(request?.httpBody)
        let decoded = try XCTUnwrap(
            JSONSerialization.jsonObject(with: body) as? [String: Any]
        )
        let time = try XCTUnwrap(decoded["time"] as? [String: Any])
        let source = try XCTUnwrap(decoded["source"] as? [String: Any])
        let collection = try XCTUnwrap(decoded["collection"] as? [String: Any])

        XCTAssertEqual(decoded["stream_type"] as? String, "hr")
        XCTAssertEqual(source["vendor"] as? String, "polar")
        XCTAssertEqual(source["device_model"] as? String, "verity_sense")
        XCTAssertEqual(collection["mode"] as? String, "online_live")
        XCTAssertNil(time["received_at_server"])
    }

    func testUploadHandlesRejectedErrorResponse() async throws {
        let endpoint = URL(string: "http://localhost:8080/upload-chunk")!
        let errorResponse = UploadErrorResponse(
            accepted: false,
            status: "rejected",
            errorCode: "unsupported_schema",
            message: "Upload chunk validation failed",
            details: [
                UploadErrorResponse.UploadErrorDetail(
                    field: "transport",
                    issue: "only polar.hr@1.0 is supported in CP3"
                )
            ]
        )
        let responseData = try JSONEncoder().encode(errorResponse)
        let response = HTTPURLResponse(
            url: endpoint,
            statusCode: 422,
            httpVersion: nil,
            headerFields: nil
        )!

        let transport = MockCollectorTransport(
            uploadEndpoint: endpoint,
            httpDataProvider: { _ in (responseData, response) }
        )

        let chunk = UploadChunk(
            sessionID: UUID(),
            streamName: "HR",
            streamType: "hr",
            streamID: "stream-hr-session",
            chunkID: UUID(),
            chunkSequenceNumber: 1,
            createdAtUTC: Date(),
            samples: [makeSample(hr: 71, receivedAt: Date(), sequence: 0)],
            collectionMode: .live,
            streamProfile: PolarHrStreamProfile.live,
            sourceDeviceID: nil
        )

        do {
            _ = try await transport.upload(chunk: chunk)
            XCTFail("Expected upload to fail")
        } catch let error as CollectorUploadError {
            switch error {
            case .rejected(let message):
                XCTAssertTrue(message.contains("[unsupported_schema]"))
                XCTAssertTrue(message.contains("Upload chunk validation failed"))
                XCTAssertTrue(message.contains("transport"))
            default:
                XCTFail("Expected rejected error")
            }
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    func testMockModeCanReturnRejectedWithoutEndpoint() async {
        let transport = MockCollectorTransport(shouldSucceedInMockMode: false)
        let chunk = UploadChunk(
            sessionID: UUID(),
            streamName: "HR",
            streamType: "hr",
            streamID: "stream-hr-session",
            chunkID: UUID(),
            chunkSequenceNumber: 1,
            createdAtUTC: Date(),
            samples: [makeSample(hr: 64, receivedAt: Date(), sequence: 0)],
            collectionMode: .live,
            streamProfile: PolarHrStreamProfile.live,
            sourceDeviceID: nil
        )

        do {
            _ = try await transport.upload(chunk: chunk)
            XCTFail("Expected mock upload to fail")
        } catch let error as CollectorUploadError {
            switch error {
            case .rejected(let message):
                XCTAssertEqual(message, "Mock upload failed")
            default:
                XCTFail("Expected rejected error")
            }
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }
}
