import Foundation

enum SourceTimestampKind: String, Codable, Sendable {
    case deviceReported
    case collectorObserved
    case reconstructed
    case unknown
}

struct HeartRateSample: Equatable, Codable, Sendable {
    let hrBPM: Int
    let collectorReceivedAtUTC: Date
    let deviceTimestampRaw: Date?
    let sourceTimestampKind: SourceTimestampKind?
    let sampleSequenceNumber: Int
}
