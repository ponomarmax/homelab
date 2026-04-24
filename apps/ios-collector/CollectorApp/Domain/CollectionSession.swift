import Foundation

struct CollectionSession: Identifiable, Equatable, Codable, Sendable {
    let sessionID: UUID
    let deviceID: String
    let deviceType: String
    let collectionMode: CollectionMode
    let startedAtUTC: Date
    var stoppedAtUTC: Date?
    let supportedStreams: [CollectorStream]

    var id: UUID { sessionID }

    init(
        sessionID: UUID = UUID(),
        device: CollectorDevice,
        collectionMode: CollectionMode,
        startedAtUTC: Date = Date(),
        stoppedAtUTC: Date? = nil,
        supportedStreams: [CollectorStream]
    ) {
        self.sessionID = sessionID
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
}
