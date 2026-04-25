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

struct HeartRateSample: Equatable, Codable, Sendable {
    let hrBPM: Int
    let collectorReceivedAtUTC: Date
    let deviceTimestampRaw: Date?
    let sourceTimestampKind: SourceTimestampKind?
    let sampleSequenceNumber: Int
    let streamData: PolarHrStreamData?

    init(
        hrBPM: Int,
        collectorReceivedAtUTC: Date,
        deviceTimestampRaw: Date?,
        sourceTimestampKind: SourceTimestampKind?,
        sampleSequenceNumber: Int,
        streamData: PolarHrStreamData? = nil
    ) {
        self.hrBPM = hrBPM
        self.collectorReceivedAtUTC = collectorReceivedAtUTC
        self.deviceTimestampRaw = deviceTimestampRaw
        self.sourceTimestampKind = sourceTimestampKind
        self.sampleSequenceNumber = sampleSequenceNumber
        self.streamData = streamData
    }
}
