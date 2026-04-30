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
        case "polar.offline.hr":
            guard let hrPayload = makeOfflineHrPayload(samples: samples) else { return nil }
            payload = .offlineHr(hrPayload)
        case "polar.offline.ppi":
            guard let ppiPayload = makeOfflinePpiPayload(samples: samples) else { return nil }
            payload = .offlinePpi(ppiPayload)
        case "polar.ecg":
            guard let ecgPayload = makeEcgPayload(samples: samples) else { return nil }
            payload = .ecg(ecgPayload)
        case "polar.acc":
            guard let accPayload = makeAccPayload(samples: samples) else { return nil }
            payload = .acc(accPayload)
        case "polar.offline.acc":
            guard let accPayload = makeOfflineAccPayload(samples: samples) else { return nil }
            payload = .offlineAcc(accPayload)
        case "polar.offline.ppg":
            guard let ppgPayload = makeOfflinePpgPayload(samples: samples) else { return nil }
            payload = .offlinePpg(ppgPayload)
        case "polar.offline.mag":
            guard let magPayload = makeOfflineMagPayload(samples: samples) else { return nil }
            payload = .offlineMag(magPayload)
        case "polar.offline.gyr", "polar.offline.gyro":
            guard let gyrPayload = makeOfflineGyrPayload(samples: samples) else { return nil }
            payload = .offlineGyr(gyrPayload)
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
        return CanonicalPolarHrPayload(
            streamSettings: resolveStreamSettings(from: samples),
            samples: payloadSamples
        )
    }

    private func makeOfflineHrPayload(samples: [HeartRateSample]) -> CanonicalPolarOfflineHrPayload? {
        let payloadSamples = samples.compactMap { sample -> CanonicalPolarOfflineHrSample? in
            guard case .hr(let streamData) = sample.payload else { return nil }
            return CanonicalPolarOfflineHrSample(
                sampleIndex: sample.sampleSequenceNumber,
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
        return CanonicalPolarOfflineHrPayload(type: "HR", source: "polar_verity_sense_offline", samples: payloadSamples)
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
            streamSettings: resolveStreamSettings(from: samples),
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
            streamSettings: resolveStreamSettings(from: samples),
            units: CanonicalPolarAccPayload.Units(
                xMg: "mg",
                yMg: "mg",
                zMg: "mg",
                deviceTimeNS: "ns_since_2000_epoch"
            ),
            samples: payloadSamples
        )
    }

    private func makeOfflineAccPayload(samples: [HeartRateSample]) -> CanonicalPolarOfflineAccPayload? {
        let payloadSamples = samples.compactMap { sample -> CanonicalPolarOfflineAccSample? in
            guard case .acc(let accData) = sample.payload else { return nil }
            guard let deviceTimeNS = accData.deviceTimeNS else { return nil }
            return CanonicalPolarOfflineAccSample(timeStamp: deviceTimeNS, xMg: accData.xMg, yMg: accData.yMg, zMg: accData.zMg)
        }
        guard !payloadSamples.isEmpty else { return nil }
        return CanonicalPolarOfflineAccPayload(type: "ACC", source: "polar_verity_sense_offline", samples: payloadSamples)
    }

    private func makeOfflinePpiPayload(samples: [HeartRateSample]) -> CanonicalPolarOfflinePpiPayload? {
        let payloadSamples = samples.compactMap { sample -> CanonicalPolarOfflinePpiSample? in
            guard case .ppi(let ppiData) = sample.payload else { return nil }
            return CanonicalPolarOfflinePpiSample(
                timeStamp: ppiData.timeStamp,
                hr: ppiData.hr,
                ppiMs: ppiData.ppiMs,
                ppErrorEstimate: ppiData.errorEstimateMs,
                blockerBit: ppiData.blockerBit,
                skinContactStatus: ppiData.skinContactStatus,
                skinContactSupported: ppiData.skinContactSupported
            )
        }
        guard !payloadSamples.isEmpty else { return nil }
        return CanonicalPolarOfflinePpiPayload(type: "PPI", source: "polar_verity_sense_offline", samples: payloadSamples)
    }

    private func makeOfflinePpgPayload(samples: [HeartRateSample]) -> CanonicalPolarOfflinePpgPayload? {
        let payloadSamples = samples.compactMap { sample -> CanonicalPolarOfflinePpgSample? in
            guard case .ppg(let ppgData) = sample.payload else { return nil }
            return CanonicalPolarOfflinePpgSample(
                timeStamp: ppgData.deviceTimeNS,
                ppg0: ppgData.ppg0,
                ppg1: ppgData.ppg1,
                ppg2: ppgData.ppg2,
                ambient: ppgData.ambient,
                channelSamples: ppgData.channelSamples
            )
        }
        guard !payloadSamples.isEmpty else { return nil }
        return CanonicalPolarOfflinePpgPayload(type: "PPG", source: "polar_verity_sense_offline", samples: payloadSamples)
    }

    private func makeOfflineMagPayload(samples: [HeartRateSample]) -> CanonicalPolarOfflineMagPayload? {
        let payloadSamples = samples.compactMap { sample -> CanonicalPolarOfflineMagSample? in
            guard case .mag(let magData) = sample.payload else { return nil }
            return CanonicalPolarOfflineMagSample(timeStamp: magData.deviceTimeNS, xGauss: magData.xGauss, yGauss: magData.yGauss, zGauss: magData.zGauss)
        }
        guard !payloadSamples.isEmpty else { return nil }
        return CanonicalPolarOfflineMagPayload(type: "MAG", source: "polar_verity_sense_offline", samples: payloadSamples)
    }

    private func makeOfflineGyrPayload(samples: [HeartRateSample]) -> CanonicalPolarOfflineGyrPayload? {
        let payloadSamples = samples.compactMap { sample -> CanonicalPolarOfflineGyrSample? in
            guard case .gyr(let gyrData) = sample.payload else { return nil }
            return CanonicalPolarOfflineGyrSample(timeStamp: gyrData.deviceTimeNS, xDps: gyrData.xDps, yDps: gyrData.yDps, zDps: gyrData.zDps)
        }
        guard !payloadSamples.isEmpty else { return nil }
        return CanonicalPolarOfflineGyrPayload(type: "GYR", source: "polar_verity_sense_offline", samples: payloadSamples)
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

    private func resolveStreamSettings(from samples: [HeartRateSample]) -> [String: StreamSettingValue]? {
        samples.compactMap(\.streamSettings).first
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
    let streamSettings: [String: StreamSettingValue]?
    let samples: [CanonicalPolarHrSample]

    enum CodingKeys: String, CodingKey {
        case streamSettings = "stream_settings"
        case samples
    }
}

struct CanonicalPolarOfflineHrSample: Equatable, Codable, Sendable {
    let sampleIndex: Int
    let hr: Int
    let ppgQuality: Int
    let correctedHr: Int
    let rrsMs: [Int]
    let rrAvailable: Bool
    let contactStatus: Bool
    let contactStatusSupported: Bool

    enum CodingKeys: String, CodingKey {
        case sampleIndex = "sample_index"
        case hr
        case ppgQuality = "ppg_quality"
        case correctedHr = "corrected_hr"
        case rrsMs = "rrs_ms"
        case rrAvailable = "rr_available"
        case contactStatus = "contact_status"
        case contactStatusSupported = "contact_status_supported"
    }
}

struct CanonicalPolarOfflineHrPayload: Equatable, Codable, Sendable {
    let type: String
    let source: String
    let samples: [CanonicalPolarOfflineHrSample]
}

struct CanonicalPolarOfflinePpiSample: Equatable, Codable, Sendable {
    let timeStamp: UInt64
    let hr: Int
    let ppiMs: UInt16
    let ppErrorEstimate: UInt16
    let blockerBit: Int
    let skinContactStatus: Int
    let skinContactSupported: Int

    enum CodingKeys: String, CodingKey {
        case timeStamp = "timeStamp"
        case hr
        case ppiMs = "ppInMs"
        case ppErrorEstimate = "ppErrorEstimate"
        case blockerBit = "blockerBit"
        case skinContactStatus = "skinContactStatus"
        case skinContactSupported = "skinContactSupported"
    }
}

struct CanonicalPolarOfflinePpiPayload: Equatable, Codable, Sendable {
    let type: String
    let source: String
    let samples: [CanonicalPolarOfflinePpiSample]
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
    let streamSettings: [String: StreamSettingValue]?
    let units: Units
    let samples: [CanonicalPolarEcgSample]

    enum CodingKeys: String, CodingKey {
        case sampleRateHz = "sample_rate_hz"
        case streamSettings = "stream_settings"
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
    let streamSettings: [String: StreamSettingValue]?
    let units: Units
    let samples: [CanonicalPolarAccSample]

    enum CodingKeys: String, CodingKey {
        case sampleRateHz = "sample_rate_hz"
        case rangeMg = "range_mg"
        case streamSettings = "stream_settings"
        case units
        case samples
    }
}

struct CanonicalPolarOfflineAccSample: Equatable, Codable, Sendable {
    let timeStamp: UInt64
    let xMg: Int32
    let yMg: Int32
    let zMg: Int32

    enum CodingKeys: String, CodingKey {
        case timeStamp = "timeStamp"
        case xMg = "x"
        case yMg = "y"
        case zMg = "z"
    }
}

struct CanonicalPolarOfflineAccPayload: Equatable, Codable, Sendable {
    let type: String
    let source: String
    let samples: [CanonicalPolarOfflineAccSample]
}

struct CanonicalPolarOfflinePpgSample: Equatable, Codable, Sendable {
    let timeStamp: UInt64
    let ppg0: Int32?
    let ppg1: Int32?
    let ppg2: Int32?
    let ambient: Int32?
    let channelSamples: [Int32]

    enum CodingKeys: String, CodingKey {
        case timeStamp = "timeStamp"
        case ppg0 = "ppg0"
        case ppg1 = "ppg1"
        case ppg2 = "ppg2"
        case ambient = "ambient"
        case channelSamples = "channelSamples"
    }
}

struct CanonicalPolarOfflinePpgPayload: Equatable, Codable, Sendable {
    let type: String
    let source: String
    let samples: [CanonicalPolarOfflinePpgSample]
}

struct CanonicalPolarOfflineMagSample: Equatable, Codable, Sendable {
    let timeStamp: UInt64
    let xGauss: Float
    let yGauss: Float
    let zGauss: Float

    enum CodingKeys: String, CodingKey {
        case timeStamp = "timeStamp"
        case xGauss = "x"
        case yGauss = "y"
        case zGauss = "z"
    }
}

struct CanonicalPolarOfflineMagPayload: Equatable, Codable, Sendable {
    let type: String
    let source: String
    let samples: [CanonicalPolarOfflineMagSample]
}

struct CanonicalPolarOfflineGyrSample: Equatable, Codable, Sendable {
    let timeStamp: UInt64
    let xDps: Float
    let yDps: Float
    let zDps: Float

    enum CodingKeys: String, CodingKey {
        case timeStamp = "timeStamp"
        case xDps = "x"
        case yDps = "y"
        case zDps = "z"
    }
}

struct CanonicalPolarOfflineGyrPayload: Equatable, Codable, Sendable {
    let type: String
    let source: String
    let samples: [CanonicalPolarOfflineGyrSample]
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
    case offlineHr(CanonicalPolarOfflineHrPayload)
    case offlinePpi(CanonicalPolarOfflinePpiPayload)
    case ecg(CanonicalPolarEcgPayload)
    case acc(CanonicalPolarAccPayload)
    case offlineAcc(CanonicalPolarOfflineAccPayload)
    case offlinePpg(CanonicalPolarOfflinePpgPayload)
    case offlineMag(CanonicalPolarOfflineMagPayload)
    case offlineGyr(CanonicalPolarOfflineGyrPayload)
    case battery(CanonicalPolarDeviceBatteryPayload)

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .hr(let value):
            try container.encode(value)
        case .offlineHr(let value):
            try container.encode(value)
        case .offlinePpi(let value):
            try container.encode(value)
        case .ecg(let value):
            try container.encode(value)
        case .acc(let value):
            try container.encode(value)
        case .offlineAcc(let value):
            try container.encode(value)
        case .offlinePpg(let value):
            try container.encode(value)
        case .offlineMag(let value):
            try container.encode(value)
        case .offlineGyr(let value):
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
        if let value = try? container.decode(CanonicalPolarOfflineHrPayload.self) {
            self = .offlineHr(value)
            return
        }
        if let value = try? container.decode(CanonicalPolarOfflinePpiPayload.self) {
            self = .offlinePpi(value)
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
        if let value = try? container.decode(CanonicalPolarOfflineAccPayload.self) {
            self = .offlineAcc(value)
            return
        }
        if let value = try? container.decode(CanonicalPolarOfflinePpgPayload.self) {
            self = .offlinePpg(value)
            return
        }
        if let value = try? container.decode(CanonicalPolarOfflineMagPayload.self) {
            self = .offlineMag(value)
            return
        }
        if let value = try? container.decode(CanonicalPolarOfflineGyrPayload.self) {
            self = .offlineGyr(value)
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
