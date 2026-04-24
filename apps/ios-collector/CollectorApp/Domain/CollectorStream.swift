import Foundation

enum CollectorStream: String, CaseIterable, Identifiable, Codable, Sendable {
    case heartRate
    case ppi
    case accelerometer
    case eeg

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .heartRate:
            return "HR"
        case .ppi:
            return "PPI"
        case .accelerometer:
            return "ACC"
        case .eeg:
            return "EEG"
        }
    }
}
