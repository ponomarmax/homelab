import Foundation

enum CollectorStream: String, CaseIterable, Identifiable, Codable, Sendable {
    case heartRate
    case ecg
    case ppi
    case accelerometer
    case eeg
    case battery

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .heartRate:
            return "HR"
        case .ecg:
            return "ECG"
        case .ppi:
            return "PPI"
        case .accelerometer:
            return "ACC"
        case .eeg:
            return "EEG"
        case .battery:
            return "Battery"
        }
    }

    var transportType: String {
        switch self {
        case .heartRate:
            return "hr"
        case .ecg:
            return "ecg"
        case .ppi:
            return "ppi"
        case .accelerometer:
            return "acc"
        case .eeg:
            return "eeg"
        case .battery:
            // Keep current transport enum compatibility by using a fallback type.
            return "unknown"
        }
    }

    var unit: String {
        switch self {
        case .heartRate:
            return "bpm"
        case .ecg:
            return "uV"
        case .ppi:
            return "ms"
        case .accelerometer:
            return "mg"
        case .eeg:
            return "uV"
        case .battery:
            return "percent"
        }
    }
}
