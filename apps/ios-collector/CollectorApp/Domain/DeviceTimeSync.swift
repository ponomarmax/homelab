import Foundation

enum DeviceTimeSyncState: String, Equatable, Sendable {
    case idle
    case running
    case success
    case failed
    case unavailable

    var displayName: String {
        switch self {
        case .idle:
            return "Not synced"
        case .running:
            return "Syncing device time..."
        case .success:
            return "Device time synced"
        case .failed:
            return "Time sync failed"
        case .unavailable:
            return "Read-back unavailable"
        }
    }
}

enum DeviceTimeOperationalEventType: String, Equatable, Sendable {
    case deviceTimeRead = "device_time_read"
    case deviceTimeSet = "device_time_set"
    case deviceTimeVerification = "device_time_verification"
}

enum DeviceTimeOperationResult: String, Equatable, Sendable {
    case success
    case failed
    case unavailable
}

struct DeviceTimeOperationalEvent: Equatable, Sendable {
    let eventType: DeviceTimeOperationalEventType
    let vendor: String
    let model: String
    let deviceID: String?
    let collectionModeContext: String
    let requestedLocalTime: Date?
    let requestedTimeZoneID: String?
    let deviceReadbackLocalTime: Date?
    let deviceReadbackTimeZoneID: String?
    let deltaSeconds: TimeInterval?
    let result: DeviceTimeOperationResult
    let collectorTimestamp: Date
    let detail: String?
}

struct DeviceTimeActionAvailability: Equatable, Sendable {
    let canReadDeviceTime: Bool
    let canSyncDeviceTime: Bool
    let reason: String?

    static let unavailable = DeviceTimeActionAvailability(
        canReadDeviceTime: false,
        canSyncDeviceTime: false,
        reason: "Device time actions unavailable"
    )
}

struct DeviceTimeActionResult: Equatable, Sendable {
    let state: DeviceTimeSyncState
    let message: String
    let debugDetails: String?
    let readbackDeviceTime: Date?
    let readbackTimeZoneID: String?
    let verificationDeltaSeconds: TimeInterval?
    let operationalEvents: [DeviceTimeOperationalEvent]
}

