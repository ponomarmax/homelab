import Foundation

struct DeviceConnectability: Equatable, Sendable {
    let isConnectable: Bool
    let reason: String?

    static let connectable = DeviceConnectability(isConnectable: true, reason: nil)
}

enum OfflineLifecycleState: String, Equatable, Sendable {
    case disconnected
    case featureUnavailable
    case ready
    case starting
    case recording
    case stopping
    case listing
    case failed
    case partialSuccess
}

struct OfflineStreamCapability: Equatable, Sendable {
    let stream: PolarOfflineStream
    let isSupported: Bool
    let reason: String?
}

struct OfflineRecordingEntry: Identifiable, Equatable, Sendable {
    let id: String
    let path: String
    let stream: PolarOfflineStream?
    let sizeBytes: UInt?
    let startedAt: Date?
    let status: String?
}

struct OfflineStreamOperationResult: Equatable, Sendable {
    let stream: PolarOfflineStream
    let success: Bool
    let message: String
}

struct OfflineUploadBatch: Equatable, Sendable {
    let stream: CollectorStream
    let sourcePath: String
    let samples: [HeartRateSample]
}

struct OfflineUploadPreparationResult: Equatable, Sendable {
    let batches: [OfflineUploadBatch]
    let messagesByStream: [PolarOfflineStream: String]
}
