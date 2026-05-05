import Foundation

enum PolarDeviceFamily: String, Equatable, Sendable {
    case veritySense = "verity_sense"
    case h10 = "h10"
    case unknownPolar = "Unknown Polar"
}

enum PolarOfflineStream: String, CaseIterable, Identifiable, Hashable, Sendable {
    case hr = "HR"
    case ppi = "PPI"
    case acc = "ACC"
    case ppg = "PPG"
    case mag = "MAG"
    case gyro = "GYRO"

    var id: String { rawValue }
}

struct PolarDeviceProfile: Equatable, Sendable {
    let family: PolarDeviceFamily
    let availableOnlineStreams: [CollectorStream]
    let availableOfflineStreams: [PolarOfflineStream]
    let supportsManualTimeSync: Bool

    static func from(
        device: CollectorDevice?,
        availableOnlineStreams: [CollectorStream],
        supportsManualTimeSync: Bool
    ) -> PolarDeviceProfile {
        let family = classifyFamily(device: device)
        let offlineStreams: [PolarOfflineStream]
        switch family {
        case .veritySense:
            offlineStreams = PolarVeritySenseOfflineCatalog.candidateStreams
        case .h10, .unknownPolar:
            offlineStreams = []
        }

        return PolarDeviceProfile(
            family: family,
            availableOnlineStreams: availableOnlineStreams,
            availableOfflineStreams: offlineStreams,
            supportsManualTimeSync: supportsManualTimeSync
        )
    }

    private static func classifyFamily(device: CollectorDevice?) -> PolarDeviceFamily {
        let haystack = "\(device?.name ?? "") \(device?.model ?? "")".lowercased()
        if haystack.contains("verity sense") {
            return .veritySense
        }
        if haystack.contains("h10") {
            return .h10
        }
        return .unknownPolar
    }
}
