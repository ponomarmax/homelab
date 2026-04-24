import Foundation

enum CollectionMode: String, CaseIterable, Codable, Sendable {
    case live
    case offlineRecording
    case importedData

    var transportValue: String {
        switch self {
        case .live:
            return "online_live"
        case .offlineRecording:
            return "offline_recording"
        case .importedData:
            return "file_import"
        }
    }
}
