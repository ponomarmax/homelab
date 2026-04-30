import Foundation

enum CollectorStream: String, CaseIterable, Identifiable, Codable, Sendable {
    case heartRate
    case ecg
    case ppi
    case accelerometer
    case ppg
    case magnetometer
    case gyroscope
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
        case .ppg:
            return "PPG"
        case .magnetometer:
            return "MAG"
        case .gyroscope:
            return "GYR"
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
        case .ppg:
            return "ppg"
        case .magnetometer:
            return "mag"
        case .gyroscope:
            return "gyro"
        case .eeg:
            return "eeg"
        case .battery:
            return "battery"
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
        case .ppg:
            return "raw"
        case .magnetometer:
            return "gauss"
        case .gyroscope:
            return "deg/sec"
        case .eeg:
            return "uV"
        case .battery:
            return "percent"
        }
    }
}
