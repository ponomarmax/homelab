import Foundation

enum CollectorStatus: String, Equatable, Sendable {
    case disconnected
    case deviceSelected
    case collecting
    case stopped

    var displayName: String {
        switch self {
        case .disconnected:
            return "Disconnected"
        case .deviceSelected:
            return "Device Selected"
        case .collecting:
            return "Collecting"
        case .stopped:
            return "Stopped"
        }
    }
}
