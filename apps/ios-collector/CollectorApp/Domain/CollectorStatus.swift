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

enum UploadStatus: Equatable, Sendable {
    case idle
    case success
    case failure

    var displayName: String {
        switch self {
        case .idle:
            return "Idle"
        case .success:
            return "Upload Success"
        case .failure:
            return "Upload Failure"
        }
    }
}
