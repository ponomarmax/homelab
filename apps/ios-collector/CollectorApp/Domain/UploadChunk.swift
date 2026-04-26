import Foundation

struct UploadChunk: Identifiable, Equatable, Codable, Sendable {
    let sessionID: UUID
    let streamName: String
    let streamType: String
    let streamID: String
    let chunkID: UUID
    let chunkSequenceNumber: Int
    let createdAtUTC: Date
    let samples: [HeartRateSample]
    let collectionMode: CollectionMode
    let streamProfile: StreamMetadataProfile
    let sourceDeviceID: String?

    var id: UUID { chunkID }

    func makeCanonicalRequest(uploadedAtUTC: Date = Date()) -> CanonicalUploadChunkRequest? {
        guard !samples.isEmpty else { return nil }
        let firstSampleAt = samples[0].collectorReceivedAtUTC

        let payload: CanonicalPayload
        switch streamProfile.transport.payloadSchema {
        case "polar.hr":
            guard let hrPayload = makeHrPayload(samples: samples) else { return nil }
            payload = .hr(hrPayload)
        case "polar.ecg":
            guard let ecgPayload = makeEcgPayload(samples: samples) else { return nil }
            payload = .ecg(ecgPayload)
        case "polar.acc":
            guard let accPayload = makeAccPayload(samples: samples) else { return nil }
            payload = .acc(accPayload)
        case "polar.device_battery":
            guard let batteryPayload = makeBatteryPayload(samples: samples) else { return nil }
            payload = .battery(batteryPayload)
        default:
            return nil
        }

        return CanonicalUploadChunkRequest(
            schemaVersion: streamProfile.schemaVersion,
            chunkID: chunkID.uuidString.lowercased(),
            sessionID: sessionID.uuidString.lowercased(),
            streamID: streamID,
            streamType: streamProfile.streamType,
            sequence: chunkSequenceNumber,
            source: CanonicalUploadChunkRequest.SourceMetadata(
                vendor: streamProfile.source.vendor,
                deviceModel: streamProfile.source.deviceModel,
                deviceID: sourceDeviceID ?? streamProfile.source.deviceID
            ),
            collection: CanonicalUploadChunkRequest.CollectionMetadata(
                mode: streamProfile.collection.mode
            ),
            time: CanonicalUploadChunkRequest.TimeMetadata(
                deviceTimeReference: streamProfile.deviceTimeReference,
                firstSampleReceivedAtCollector: Self.iso8601(from: firstSampleAt),
                uploadedAtCollector: Self.iso8601(from: uploadedAtUTC)
            ),
            transport: CanonicalUploadChunkRequest.TransportMetadata(
                encoding: streamProfile.transport.encoding,
                compression: streamProfile.transport.compression,
                payloadSchema: streamProfile.transport.payloadSchema,
                payloadVersion: streamProfile.transport.payloadVersion
            ),
            payload: payload
        )
    }

    private func makeHrPayload(samples: [HeartRateSample]) -> CanonicalPolarHrPayload? {
        let payloadSamples = samples.compactMap { sample -> CanonicalPolarHrSample? in
            guard case .hr(let streamData) = sample.payload else { return nil }

            return CanonicalPolarHrSample(
                receivedAtCollector: Self.iso8601(from: sample.collectorReceivedAtUTC),
                hr: streamData.hr,
                ppgQuality: streamData.ppgQuality,
                correctedHr: streamData.correctedHr,
                rrsMs: streamData.rrsMs,
                rrAvailable: streamData.rrAvailable,
                contactStatus: streamData.contactStatus,
                contactStatusSupported: streamData.contactStatusSupported
            )
        }

        guard !payloadSamples.isEmpty else { return nil }
        return CanonicalPolarHrPayload(samples: payloadSamples)
    }

    private func makeEcgPayload(samples: [HeartRateSample]) -> CanonicalPolarEcgPayload? {
        let payloadSamples = samples.compactMap { sample -> CanonicalPolarEcgSample? in
            guard case .ecg(let ecgData) = sample.payload else { return nil }
            return CanonicalPolarEcgSample(
                deviceTimeNS: ecgData.deviceTimeNS,
                receivedAtCollector: Self.iso8601(from: sample.collectorReceivedAtUTC),
                ecgUv: ecgData.ecgUv
            )
        }

        guard !payloadSamples.isEmpty else { return nil }

        let sampleRateHz = samples.compactMap { sample -> UInt32? in
            guard case .ecg(let ecgData) = sample.payload else { return nil }
            return ecgData.sampleRateHz
        }.first

        return CanonicalPolarEcgPayload(
            sampleRateHz: sampleRateHz,
            units: CanonicalPolarEcgPayload.Units(
                ecgUv: "uV",
                deviceTimeNS: "ns_since_2000_epoch"
            ),
            samples: payloadSamples
        )
    }

    private func makeAccPayload(samples: [HeartRateSample]) -> CanonicalPolarAccPayload? {
        let payloadSamples = samples.compactMap { sample -> CanonicalPolarAccSample? in
            guard case .acc(let accData) = sample.payload else { return nil }
            return CanonicalPolarAccSample(
                deviceTimeNS: accData.deviceTimeNS,
                receivedAtCollector: Self.iso8601(from: sample.collectorReceivedAtUTC),
                xMg: accData.xMg,
                yMg: accData.yMg,
                zMg: accData.zMg
            )
        }

        guard !payloadSamples.isEmpty else { return nil }

        let sampleRateHz = samples.compactMap { sample -> UInt32? in
            guard case .acc(let accData) = sample.payload else { return nil }
            return accData.sampleRateHz
        }.first

        let rangeMg = samples.compactMap { sample -> UInt32? in
            guard case .acc(let accData) = sample.payload else { return nil }
            return accData.rangeMg
        }.first

        return CanonicalPolarAccPayload(
            sampleRateHz: sampleRateHz,
            rangeMg: rangeMg,
            units: CanonicalPolarAccPayload.Units(
                xMg: "mg",
                yMg: "mg",
                zMg: "mg",
                deviceTimeNS: "ns_since_2000_epoch"
            ),
            samples: payloadSamples
        )
    }

    private func makeBatteryPayload(samples: [HeartRateSample]) -> CanonicalPolarDeviceBatteryPayload? {
        guard let sample = samples.last else { return nil }
        guard case .battery(let batteryData) = sample.payload else { return nil }

        let batteryPayload: CanonicalPolarDeviceBatteryPayload.Battery?
        if batteryData.levelPercent != nil || batteryData.chargeState != nil || batteryData.powerSources != nil {
            batteryPayload = CanonicalPolarDeviceBatteryPayload.Battery(
                levelPercent: batteryData.levelPercent,
                chargeState: batteryData.chargeState,
                powerSources: batteryData.powerSources
            )
        } else {
            batteryPayload = nil
        }

        return CanonicalPolarDeviceBatteryPayload(
            eventType: batteryData.eventType,
            battery: batteryPayload,
            sdkRaw: batteryData.sdkRaw,
            unavailableReason: batteryData.unavailableReason,
            receivedAtCollector: Self.iso8601(from: sample.collectorReceivedAtUTC),
            units: CanonicalPolarDeviceBatteryPayload.Units(levelPercent: "percent")
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
    let receivedAtCollector: String
    let hr: Int
    let ppgQuality: Int
    let correctedHr: Int
    let rrsMs: [Int]
    let rrAvailable: Bool
    let contactStatus: Bool
    let contactStatusSupported: Bool

    enum CodingKeys: String, CodingKey {
        case receivedAtCollector = "received_at_collector"
        case hr
        case ppgQuality
        case correctedHr
        case rrsMs
        case rrAvailable
        case contactStatus
        case contactStatusSupported
    }
}

struct CanonicalPolarHrPayload: Equatable, Codable, Sendable {
    let samples: [CanonicalPolarHrSample]
}

struct CanonicalPolarEcgSample: Equatable, Codable, Sendable {
    let deviceTimeNS: UInt64?
    let receivedAtCollector: String
    let ecgUv: Int32

    enum CodingKeys: String, CodingKey {
        case deviceTimeNS = "device_time_ns"
        case receivedAtCollector = "received_at_collector"
        case ecgUv = "ecg_uv"
    }
}

struct CanonicalPolarEcgPayload: Equatable, Codable, Sendable {
    struct Units: Equatable, Codable, Sendable {
        let ecgUv: String
        let deviceTimeNS: String

        enum CodingKeys: String, CodingKey {
            case ecgUv = "ecg_uv"
            case deviceTimeNS = "device_time_ns"
        }
    }

    let sampleRateHz: UInt32?
    let units: Units
    let samples: [CanonicalPolarEcgSample]

    enum CodingKeys: String, CodingKey {
        case sampleRateHz = "sample_rate_hz"
        case units
        case samples
    }
}

struct CanonicalPolarAccSample: Equatable, Codable, Sendable {
    let deviceTimeNS: UInt64?
    let receivedAtCollector: String
    let xMg: Int32
    let yMg: Int32
    let zMg: Int32

    enum CodingKeys: String, CodingKey {
        case deviceTimeNS = "device_time_ns"
        case receivedAtCollector = "received_at_collector"
        case xMg = "x_mg"
        case yMg = "y_mg"
        case zMg = "z_mg"
    }
}

struct CanonicalPolarAccPayload: Equatable, Codable, Sendable {
    struct Units: Equatable, Codable, Sendable {
        let xMg: String
        let yMg: String
        let zMg: String
        let deviceTimeNS: String

        enum CodingKeys: String, CodingKey {
            case xMg = "x_mg"
            case yMg = "y_mg"
            case zMg = "z_mg"
            case deviceTimeNS = "device_time_ns"
        }
    }

    let sampleRateHz: UInt32?
    let rangeMg: UInt32?
    let units: Units
    let samples: [CanonicalPolarAccSample]

    enum CodingKeys: String, CodingKey {
        case sampleRateHz = "sample_rate_hz"
        case rangeMg = "range_mg"
        case units
        case samples
    }
}

struct CanonicalPolarDeviceBatteryPayload: Equatable, Codable, Sendable {
    struct Units: Equatable, Codable, Sendable {
        let levelPercent: String

        enum CodingKeys: String, CodingKey {
            case levelPercent = "level_percent"
        }
    }

    struct Battery: Equatable, Codable, Sendable {
        let levelPercent: Int?
        let chargeState: String?
        let powerSources: [String]?

        enum CodingKeys: String, CodingKey {
            case levelPercent = "level_percent"
            case chargeState = "charge_state"
            case powerSources = "power_sources"
        }
    }

    let eventType: PolarBatteryEventType
    let battery: Battery?
    let sdkRaw: String?
    let unavailableReason: String?
    let receivedAtCollector: String
    let units: Units

    enum CodingKeys: String, CodingKey {
        case eventType = "event_type"
        case battery
        case sdkRaw = "sdk_raw"
        case unavailableReason = "unavailable_reason"
        case receivedAtCollector = "received_at_collector"
        case units
    }
}

enum CanonicalPayload: Equatable, Codable, Sendable {
    case hr(CanonicalPolarHrPayload)
    case ecg(CanonicalPolarEcgPayload)
    case acc(CanonicalPolarAccPayload)
    case battery(CanonicalPolarDeviceBatteryPayload)

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .hr(let value):
            try container.encode(value)
        case .ecg(let value):
            try container.encode(value)
        case .acc(let value):
            try container.encode(value)
        case .battery(let value):
            try container.encode(value)
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(CanonicalPolarHrPayload.self) {
            self = .hr(value)
            return
        }
        if let value = try? container.decode(CanonicalPolarEcgPayload.self) {
            self = .ecg(value)
            return
        }
        if let value = try? container.decode(CanonicalPolarAccPayload.self) {
            self = .acc(value)
            return
        }
        if let value = try? container.decode(CanonicalPolarDeviceBatteryPayload.self) {
            self = .battery(value)
            return
        }
        throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported payload")
    }
}

struct CanonicalUploadChunkRequest: Equatable, Codable, Sendable {
    let schemaVersion: String
    let chunkID: String
    let sessionID: String
    let streamID: String
    let streamType: String
    let sequence: Int
    let source: SourceMetadata
    let collection: CollectionMetadata
    let time: TimeMetadata
    let transport: TransportMetadata
    let payload: CanonicalPayload

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case chunkID = "chunk_id"
        case sessionID = "session_id"
        case streamID = "stream_id"
        case streamType = "stream_type"
        case sequence
        case source
        case collection
        case time
        case transport
        case payload
    }

    struct SourceMetadata: Equatable, Codable, Sendable {
        let vendor: String
        let deviceModel: String
        let deviceID: String?

        enum CodingKeys: String, CodingKey {
            case vendor
            case deviceModel = "device_model"
            case deviceID = "device_id"
        }
    }

    struct CollectionMetadata: Equatable, Codable, Sendable {
        let mode: String
    }

    struct TimeMetadata: Equatable, Codable, Sendable {
        let deviceTimeReference: String
        let firstSampleReceivedAtCollector: String
        let uploadedAtCollector: String

        enum CodingKeys: String, CodingKey {
            case deviceTimeReference = "device_time_reference"
            case firstSampleReceivedAtCollector = "first_sample_received_at_collector"
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
    let details: [UploadErrorDetail]?

    enum CodingKeys: String, CodingKey {
        case accepted
        case status
        case errorCode = "error_code"
        case message
        case details
    }

    struct UploadErrorDetail: Equatable, Codable, Sendable {
        let field: String
        let issue: String
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
