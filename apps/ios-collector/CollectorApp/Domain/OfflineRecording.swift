import Foundation

struct DeviceConnectability: Equatable, Sendable {
    let isConnectable: Bool
    let reason: String?

    static let connectable = DeviceConnectability(isConnectable: true, reason: nil)
}

enum OfflineLifecycleState: String, Equatable, Sendable {
    case notLoaded
    case refreshing
    case disconnected
    case featureUnavailable
    case idle
    case ready
    case recoveredRecording
    case starting
    case recording
    case stopping
    case listing
    case uploading
    case deleting
    case completed
    case unknown
    case failed
    case partialSuccess
}

enum OfflineOperation: String, Equatable, Sendable {
    case none = "Idle"
    case starting = "Starting offline recordings…"
    case stopping = "Stopping offline recordings…"
    case listing = "Listing offline recordings…"
    case uploading = "Uploading offline recordings…"
    case deleting = "Deleting offline recording…"
}

enum OfflineStreamRunState: String, Equatable, Sendable {
    case loadingSettings
    case ready
    case unavailable
    case unknown
    case starting
    case recording
    case stopping
    case fetching
    case uploading
    case uploaded
    case failed
}

enum OfflineSettingsLoadState: Equatable, Sendable {
    case notLoaded
    case loading
    case ready
    case failed(message: String)
}

struct OfflineStreamSettingsOptions: Equatable, Sendable {
    let sampleRates: [UInt32]
    let resolutions: [UInt32]
    let ranges: [UInt32]
    let channels: [UInt32]

    var isConfigurable: Bool {
        !sampleRates.isEmpty || !resolutions.isEmpty || !ranges.isEmpty || !channels.isEmpty
    }
}

struct OfflineStreamSettingsSelection: Equatable, Sendable {
    let sampleRate: UInt32?
    let resolution: UInt32?
    let range: UInt32?
    let channels: UInt32?

    func summary() -> String {
        let parts: [String] = [
            sampleRate.map { "sample_rate=\($0)" },
            resolution.map { "resolution=\($0)" },
            range.map { "range=\($0)" },
            channels.map { "channels=\($0)" }
        ].compactMap { $0 }
        return parts.isEmpty ? "default" : parts.joined(separator: ", ")
    }
}

struct OfflineStreamSettings: Equatable, Sendable {
    let stream: PolarOfflineStream
    let options: OfflineStreamSettingsOptions
    let selected: OfflineStreamSettingsSelection
}

struct OfflineSettingsFailure: Error, Equatable, Sendable {
    let message: String
}

struct OfflineRecordingStartRequest: Equatable, Sendable {
    let stream: PolarOfflineStream
    let selectedSettings: OfflineStreamSettingsSelection?
}

struct OfflineStreamCapability: Equatable, Sendable {
    let stream: PolarOfflineStream
    let isSupported: Bool
    let reason: String?
}

enum OfflineStreamStatus: String, Equatable, Sendable {
    case recording
    case ready
    case unavailable
    case failed
    case unknown
}

struct OfflineStreamRecoveredState: Equatable, Sendable {
    let isSelected: Bool
    let isSupported: Bool
    let isRecording: Bool
    let status: OfflineStreamStatus
    let lastError: String?
    let lastKnownRecordInfo: OfflineRecordingEntry?
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
    let timeContext: UploadChunkTimeContext?
}

struct OfflineUploadPreparationResult: Equatable, Sendable {
    let batches: [OfflineUploadBatch]
    let messagesByStream: [PolarOfflineStream: String]
}
