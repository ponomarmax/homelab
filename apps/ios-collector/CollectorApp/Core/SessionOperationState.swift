import Foundation

enum SessionOperationState: Equatable {
    case idle
    case connecting
    case recording
    case syncing
    case uploading
    case pipelineTriggering
    case completed
    case failed(message: String)

    var buttonTitle: String {
        switch self {
        case .recording:
            return "Stop & Sync Session"
        default:
            return "Start Night Session"
        }
    }
}
