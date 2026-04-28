import Foundation

struct CollectorDevice: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let vendor: String
    let model: String
}

enum BatteryChargeState: String, Equatable, Codable, Sendable {
    case charging = "charging"
    case dischargingActive = "discharging_active"
    case dischargingInactive = "discharging_inactive"
    case unknown = "unknown"

    init?(rawOrNil rawValue: String?) {
        guard let rawValue else {
            return nil
        }
        self = BatteryChargeState(rawValue: rawValue) ?? .unknown
    }
}

enum BatteryStatusSource: String, Equatable, Codable, Sendable {
    case callback
    case poll
    case cached
    case unavailable
}

struct BatteryStatus: Equatable, Sendable {
    let levelPercent: Int?
    let chargeState: BatteryChargeState?
    let lastUpdatedAt: Date
    let source: BatteryStatusSource?
    let unavailableReason: String?
}

struct DeviceStatus: Equatable, Sendable {
    let battery: BatteryStatus?

    static let empty = DeviceStatus(battery: nil)
}

struct DeviceStatusSnapshot: Equatable, Sendable {
    let deviceID: String
    let status: DeviceStatus
    let updatedAt: Date
}

struct DeviceStatusCapability: Equatable, Sendable {
    enum Kind: String, Equatable, Sendable {
        case battery
    }

    let kind: Kind
    let isSupported: Bool
    let supportsCallbacks: Bool
    let supportsPolling: Bool
    let requiresConnection: Bool
}

protocol DeviceStatusProvider: AnyObject {
    var deviceStatusCapabilities: [DeviceStatusCapability] { get }
    func cachedDeviceStatusSnapshot(for deviceID: String) -> DeviceStatusSnapshot?
}
