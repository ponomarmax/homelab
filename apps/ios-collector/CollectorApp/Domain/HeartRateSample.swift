import Foundation

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
    case battery(PolarBatteryData)
}

struct HeartRateSample: Equatable, Codable, Sendable {
    let stream: CollectorStream
    let collectorReceivedAtUTC: Date
    let deviceTimestampRaw: Date?
    let sourceTimestampKind: SourceTimestampKind?
    let sampleSequenceNumber: Int
    let payload: CollectorSamplePayload

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
        case .hr, .battery:
            return nil
        }
    }

    init(
        stream: CollectorStream,
        collectorReceivedAtUTC: Date,
        deviceTimestampRaw: Date? = nil,
        sourceTimestampKind: SourceTimestampKind?,
        sampleSequenceNumber: Int,
        payload: CollectorSamplePayload
    ) {
        self.stream = stream
        self.collectorReceivedAtUTC = collectorReceivedAtUTC
        self.deviceTimestampRaw = deviceTimestampRaw
        self.sourceTimestampKind = sourceTimestampKind
        self.sampleSequenceNumber = sampleSequenceNumber
        self.payload = payload
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
            payload: .hr(resolvedStreamData)
        )
    }
}
