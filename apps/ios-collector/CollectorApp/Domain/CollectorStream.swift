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

    var transportType: String {
        switch self {
        case .heartRate:
            return "hr"
        case .ppi:
            return "ppi"
        case .accelerometer:
            return "acc"
        case .eeg:
            return "eeg"
        }
    }

    var unit: String {
        switch self {
        case .heartRate:
            return "bpm"
        case .ppi:
            return "ms"
        case .accelerometer:
            return "g"
        case .eeg:
            return "uV"
        }
    }
}
