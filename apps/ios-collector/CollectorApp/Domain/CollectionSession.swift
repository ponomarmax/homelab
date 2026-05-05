import Foundation

struct CollectionSession: Identifiable, Equatable, Codable, Sendable {
    let sessionID: UUID
    let clientSessionID: String
    let deviceID: String
    let deviceType: String
    let collectionMode: CollectionMode
    let startedAtUTC: Date
    var stoppedAtUTC: Date?
    let supportedStreams: [CollectorStream]

    var id: UUID { sessionID }

    init(
        sessionID: UUID = UUID(),
        clientSessionID: String? = nil,
        device: CollectorDevice,
        collectionMode: CollectionMode,
        startedAtUTC: Date = Date(),
        stoppedAtUTC: Date? = nil,
        supportedStreams: [CollectorStream]
    ) {
        self.sessionID = sessionID
        self.clientSessionID = clientSessionID ?? Self.makeClientSessionID(startedAtUTC: startedAtUTC, sessionID: sessionID)
        self.deviceID = device.id
        self.deviceType = "\(device.vendor) \(device.model)"
        self.collectionMode = collectionMode
        self.startedAtUTC = startedAtUTC
        self.stoppedAtUTC = stoppedAtUTC
        self.supportedStreams = supportedStreams
    }

    mutating func markStopped(at date: Date) {
        stoppedAtUTC = date
    }

    static func makeClientSessionID(startedAtUTC: Date, sessionID: UUID) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let prefix = formatter.string(from: startedAtUTC)
        let short = sessionID.uuidString.replacingOccurrences(of: "-", with: "").prefix(8).lowercased()
        return "S-\(prefix)Z-\(short)"
    }
}
