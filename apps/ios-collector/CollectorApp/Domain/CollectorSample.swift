import Foundation

enum StreamSettingValue: Equatable, Hashable, Codable, Sendable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: StreamSettingValue])
    case array([StreamSettingValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if container.decodeNil() {
            self = .null
            return
        }
        if let value = try? container.decode(Bool.self) {
            self = .bool(value)
            return
        }
        if let value = try? container.decode(Double.self) {
            self = .number(value)
            return
        }
        if let value = try? container.decode(String.self) {
            self = .string(value)
            return
        }
        if let value = try? container.decode([String: StreamSettingValue].self) {
            self = .object(value)
            return
        }
        if let value = try? container.decode([StreamSettingValue].self) {
            self = .array(value)
            return
        }

        throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported stream setting value")
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value):
            try container.encode(value)
        case .number(let value):
            try container.encode(value)
        case .bool(let value):
            try container.encode(value)
        case .object(let value):
            try container.encode(value)
        case .array(let value):
            try container.encode(value)
        case .null:
            try container.encodeNil()
        }
    }
}

enum SourceTimestampKind: String, Codable, Sendable {
    case deviceReported
    case collectorObserved
    case reconstructed
    case unknown
}

struct PolarHrStreamData: Equatable, Codable, Sendable {
    let hr: Int
    let ppgQuality: Int
    let correctedHr: Int
    let rrsMs: [Int]
    let rrAvailable: Bool
    let contactStatus: Bool
    let contactStatusSupported: Bool
}

struct PolarEcgSampleData: Equatable, Codable, Sendable {
    let deviceTimeNS: UInt64?
    let ecgUv: Int32
    let sampleRateHz: UInt32?

    enum CodingKeys: String, CodingKey {
        case deviceTimeNS = "device_time_ns"
        case ecgUv = "ecg_uv"
        case sampleRateHz = "sample_rate_hz"
    }
}

struct PolarAccSampleData: Equatable, Codable, Sendable {
    let deviceTimeNS: UInt64?
    let xMg: Int32
    let yMg: Int32
    let zMg: Int32
    let sampleRateHz: UInt32?
    let rangeMg: UInt32?

    enum CodingKeys: String, CodingKey {
        case deviceTimeNS = "device_time_ns"
        case xMg = "x_mg"
        case yMg = "y_mg"
        case zMg = "z_mg"
        case sampleRateHz = "sample_rate_hz"
        case rangeMg = "range_mg"
    }
}

struct PolarPpiSampleData: Equatable, Codable, Sendable {
    let timeStamp: UInt64
    let hr: Int
    let ppiMs: UInt16
    let errorEstimateMs: UInt16
    let blockerBit: Int
    let skinContactStatus: Int
    let skinContactSupported: Int

    enum CodingKeys: String, CodingKey {
        case timeStamp = "time_stamp"
        case hr
        case ppiMs = "ppi_ms"
        case errorEstimateMs = "error_estimate_ms"
        case blockerBit = "blocker_bit"
        case skinContactStatus = "skin_contact_status"
        case skinContactSupported = "skin_contact_supported"
    }
}

struct PolarPpgSampleData: Equatable, Codable, Sendable {
    let deviceTimeNS: UInt64
    let ppg0: Int32?
    let ppg1: Int32?
    let ppg2: Int32?
    let ambient: Int32?
    let channelSamples: [Int32]

    enum CodingKeys: String, CodingKey {
        case deviceTimeNS = "device_time_ns"
        case ppg0 = "ppg0"
        case ppg1 = "ppg1"
        case ppg2 = "ppg2"
        case ambient = "ambient"
        case channelSamples = "channel_samples"
    }
}

struct PolarMagSampleData: Equatable, Codable, Sendable {
    let deviceTimeNS: UInt64
    let xGauss: Float
    let yGauss: Float
    let zGauss: Float

    enum CodingKeys: String, CodingKey {
        case deviceTimeNS = "device_time_ns"
        case xGauss = "x_gauss"
        case yGauss = "y_gauss"
        case zGauss = "z_gauss"
    }
}

struct PolarGyroSampleData: Equatable, Codable, Sendable {
    let deviceTimeNS: UInt64
    let xDps: Float
    let yDps: Float
    let zDps: Float

    enum CodingKeys: String, CodingKey {
        case deviceTimeNS = "device_time_ns"
        case xDps = "x_dps"
        case yDps = "y_dps"
        case zDps = "z_dps"
    }
}

enum PolarBatteryEventType: String, Codable, Sendable {
    case callbackUpdate = "callback_update"
    case pollSnapshot = "poll_snapshot"
    case batteryUnavailable = "battery_unavailable"
}

struct PolarBatteryData: Equatable, Codable, Sendable {
    let eventType: PolarBatteryEventType
    let levelPercent: Int?
    let chargeState: String?
    let powerSources: [String]?
    let sdkRaw: String?
    let unavailableReason: String?

    enum CodingKeys: String, CodingKey {
        case eventType = "event_type"
        case levelPercent = "level_percent"
        case chargeState = "charge_state"
        case powerSources = "power_sources"
        case sdkRaw = "sdk_raw"
        case unavailableReason = "unavailable_reason"
    }
}

enum CollectorSamplePayload: Equatable, Codable, Sendable {
    case hr(PolarHrStreamData)
    case ecg(PolarEcgSampleData)
    case acc(PolarAccSampleData)
    case ppi(PolarPpiSampleData)
    case ppg(PolarPpgSampleData)
    case mag(PolarMagSampleData)
    case gyro(PolarGyroSampleData)
    case battery(PolarBatteryData)
}

struct CollectorSample: Equatable, Codable, Sendable {
    let stream: CollectorStream
    let collectorReceivedAtUTC: Date
    let deviceTimestampRaw: Date?
    let sourceTimestampKind: SourceTimestampKind?
    let sampleSequenceNumber: Int
    let payload: CollectorSamplePayload
    let streamSettings: [String: StreamSettingValue]?

    var hrBPM: Int {
        guard case .hr(let hrData) = payload else { return 0 }
        return hrData.hr
    }

    var streamData: PolarHrStreamData? {
        guard case .hr(let hrData) = payload else { return nil }
        return hrData
    }

    var ecgData: PolarEcgSampleData? {
        guard case .ecg(let ecgData) = payload else { return nil }
        return ecgData
    }

    var accData: PolarAccSampleData? {
        guard case .acc(let accData) = payload else { return nil }
        return accData
    }

    var batteryData: PolarBatteryData? {
        guard case .battery(let batteryData) = payload else { return nil }
        return batteryData
    }

    var deviceTimeNS: UInt64? {
        switch payload {
        case .ecg(let ecgData):
            return ecgData.deviceTimeNS
        case .acc(let accData):
            return accData.deviceTimeNS
        case .ppg(let ppgData):
            return ppgData.deviceTimeNS
        case .mag(let magData):
            return magData.deviceTimeNS
        case .gyro(let gyrData):
            return gyrData.deviceTimeNS
        case .hr, .ppi, .battery:
            return nil
        }
    }

    init(
        stream: CollectorStream,
        collectorReceivedAtUTC: Date,
        deviceTimestampRaw: Date? = nil,
        sourceTimestampKind: SourceTimestampKind?,
        sampleSequenceNumber: Int,
        payload: CollectorSamplePayload,
        streamSettings: [String: StreamSettingValue]? = nil
    ) {
        self.stream = stream
        self.collectorReceivedAtUTC = collectorReceivedAtUTC
        self.deviceTimestampRaw = deviceTimestampRaw
        self.sourceTimestampKind = sourceTimestampKind
        self.sampleSequenceNumber = sampleSequenceNumber
        self.payload = payload
        self.streamSettings = streamSettings
    }

    init(
        hrBPM: Int,
        collectorReceivedAtUTC: Date,
        deviceTimestampRaw: Date?,
        sourceTimestampKind: SourceTimestampKind?,
        sampleSequenceNumber: Int,
        streamData: PolarHrStreamData? = nil
    ) {
        let resolvedStreamData = streamData ?? PolarHrStreamData(
            hr: hrBPM,
            ppgQuality: 0,
            correctedHr: 0,
            rrsMs: [],
            rrAvailable: false,
            contactStatus: false,
            contactStatusSupported: false
        )
        self.init(
            stream: .heartRate,
            collectorReceivedAtUTC: collectorReceivedAtUTC,
            deviceTimestampRaw: deviceTimestampRaw,
            sourceTimestampKind: sourceTimestampKind,
            sampleSequenceNumber: sampleSequenceNumber,
            payload: .hr(resolvedStreamData),
            streamSettings: nil
        )
    }
}

typealias HeartRateSample = CollectorSample
