import Foundation

enum SourceTimestampKind: String, Codable, Sendable {
    case deviceReported
    case collectorObserved
    case reconstructed
    case unknown
}

struct HeartRateSample: Equatable, Sendable {
    let value: Int
    let collectorReceivedAtUTC: Date
    let rawDeviceTimestamp: Date?
    let sourceTimestampKind: SourceTimestampKind?
    let sampleSequenceNumber: Int?
}
