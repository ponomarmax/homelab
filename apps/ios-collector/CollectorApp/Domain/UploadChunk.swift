import Foundation

struct UploadChunk: Identifiable, Equatable, Codable, Sendable {
    let sessionID: UUID
    let streamName: String
    let streamType: String
    let chunkID: UUID
    let chunkSequenceNumber: Int
    let createdAtUTC: Date
    let samples: [HeartRateSample]
    let collectionMode: CollectionMode

    var id: UUID { chunkID }

    func makeCanonicalRequest(uploadedAtUTC: Date = Date()) -> CanonicalUploadChunkRequest? {
        guard !samples.isEmpty else { return nil }

        let payloadSamples = samples.map { sample in
            if let streamData = sample.streamData {
                return CanonicalPolarHrSample(
                    hr: streamData.hr,
                    ppgQuality: streamData.ppgQuality,
                    correctedHr: streamData.correctedHr,
                    rrsMs: streamData.rrsMs,
                    rrAvailable: streamData.rrAvailable,
                    contactStatus: streamData.contactStatus,
                    contactStatusSupported: streamData.contactStatusSupported
                )
            }

            // Keep mock provider support by emitting a minimal raw-compatible fallback.
            return CanonicalPolarHrSample(
                hr: sample.hrBPM,
                ppgQuality: 0,
                correctedHr: 0,
                rrsMs: [],
                rrAvailable: false,
                contactStatus: false,
                contactStatusSupported: false
            )
        }

        return CanonicalUploadChunkRequest(
            schemaVersion: "1.0",
            chunkID: chunkID.uuidString.lowercased(),
            sessionID: sessionID.uuidString.lowercased(),
            streamID: "stream-\(streamType)-\(sessionID.uuidString.lowercased())",
            sequence: chunkSequenceNumber,
            time: CanonicalUploadChunkRequest.TimeMetadata(
                receivedAtCollector: Self.iso8601(from: samples[0].collectorReceivedAtUTC),
                uploadedAtCollector: Self.iso8601(from: uploadedAtUTC)
            ),
            transport: CanonicalUploadChunkRequest.TransportMetadata(
                encoding: "json",
                compression: "none",
                payloadSchema: "polar.hr",
                payloadVersion: "1.0"
            ),
            payload: CanonicalPolarHrPayload(samples: payloadSamples)
        )
    }

    private static let iso8601Formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }()

    private static func iso8601(from date: Date) -> String {
        iso8601Formatter.string(from: date)
    }
}

struct CanonicalPolarHrSample: Equatable, Codable, Sendable {
    let hr: Int
    let ppgQuality: Int
    let correctedHr: Int
    let rrsMs: [Int]
    let rrAvailable: Bool
    let contactStatus: Bool
    let contactStatusSupported: Bool
}

struct CanonicalPolarHrPayload: Equatable, Codable, Sendable {
    let samples: [CanonicalPolarHrSample]
}

struct CanonicalUploadChunkRequest: Equatable, Codable, Sendable {
    let schemaVersion: String
    let chunkID: String
    let sessionID: String
    let streamID: String
    let sequence: Int
    let time: TimeMetadata
    let transport: TransportMetadata
    let payload: CanonicalPolarHrPayload

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case chunkID = "chunk_id"
        case sessionID = "session_id"
        case streamID = "stream_id"
        case sequence
        case time
        case transport
        case payload
    }

    struct TimeMetadata: Equatable, Codable, Sendable {
        let receivedAtCollector: String
        let uploadedAtCollector: String

        enum CodingKeys: String, CodingKey {
            case receivedAtCollector = "received_at_collector"
            case uploadedAtCollector = "uploaded_at_collector"
        }
    }

    struct TransportMetadata: Equatable, Codable, Sendable {
        let encoding: String
        let compression: String
        let payloadSchema: String
        let payloadVersion: String

        enum CodingKeys: String, CodingKey {
            case encoding
            case compression
            case payloadSchema = "payload_schema"
            case payloadVersion = "payload_version"
        }
    }
}

struct UploadAck: Equatable, Codable, Sendable {
    let accepted: Bool
    let status: String
    let chunkID: String
    let sessionID: String
    let streamID: String
    let receivedAtServer: String
    let storage: UploadStorage
    let message: String?

    enum CodingKeys: String, CodingKey {
        case accepted
        case status
        case chunkID = "chunk_id"
        case sessionID = "session_id"
        case streamID = "stream_id"
        case receivedAtServer = "received_at_server"
        case storage
        case message
    }

    struct UploadStorage: Equatable, Codable, Sendable {
        let rawPersisted: Bool
        let storagePath: String?

        enum CodingKeys: String, CodingKey {
            case rawPersisted = "raw_persisted"
            case storagePath = "storage_path"
        }
    }
}

struct UploadErrorResponse: Equatable, Codable, Sendable {
    let accepted: Bool
    let status: String
    let errorCode: String
    let message: String

    enum CodingKeys: String, CodingKey {
        case accepted
        case status
        case errorCode = "error_code"
        case message
    }
}

enum CollectorUploadError: LocalizedError, Sendable {
    case missingPayload
    case invalidResponse
    case rejected(message: String)

    var errorDescription: String? {
        switch self {
        case .missingPayload:
            return "Upload payload is empty"
        case .invalidResponse:
            return "Upload response is invalid"
        case .rejected(let message):
            return message
        }
    }
}
