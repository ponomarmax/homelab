import Foundation

final class MockDeviceAdapter: CollectorDeviceAdapter {
    private(set) var connectionState: ConnectionState = .disconnected

    let deviceIdentity: CollectorDevice
    let availableStreams: [CollectorStream]
    let sourceIdentifier: String = "mock"
    let deviceSelectionActionTitle: String = "Select Mock Device"

    private let providers: [HeartRateStreamProviding]
    private var cachedStatusByDeviceID: [String: DeviceStatusSnapshot]
    var deviceTimeAvailability: DeviceTimeActionAvailability
    var nextReadDeviceTimeResult: DeviceTimeActionResult
    var nextSyncDeviceTimeResult: DeviceTimeActionResult

    init(
        deviceIdentity: CollectorDevice = CollectorDevice(
            id: "mock-polar-verity-sense",
            name: "Mock Polar Verity Sense",
            vendor: "Polar",
            model: "Verity Sense"
        ),
        availableStreams: [CollectorStream] = [.heartRate],
        hrProvider: HeartRateStreamProviding = MockHeartRateStreamProvider(),
        additionalProviders: [HeartRateStreamProviding] = [],
        initialDeviceStatusSnapshot: DeviceStatusSnapshot? = nil
    ) {
        self.deviceIdentity = deviceIdentity
        self.availableStreams = availableStreams
        self.providers = [hrProvider] + additionalProviders
        if let initialDeviceStatusSnapshot {
            self.cachedStatusByDeviceID = [initialDeviceStatusSnapshot.deviceID: initialDeviceStatusSnapshot]
        } else {
            self.cachedStatusByDeviceID = [:]
        }
        self.deviceTimeAvailability = DeviceTimeActionAvailability(
            canReadDeviceTime: true,
            canSyncDeviceTime: true,
            reason: nil
        )
        self.nextReadDeviceTimeResult = DeviceTimeActionResult(
            state: .success,
            message: "Device time synced",
            debugDetails: nil,
            readbackDeviceTime: Date(timeIntervalSince1970: 100),
            readbackTimeZoneID: TimeZone.current.identifier,
            verificationDeltaSeconds: nil,
            operationalEvents: []
        )
        self.nextSyncDeviceTimeResult = DeviceTimeActionResult(
            state: .success,
            message: "Device time synced",
            debugDetails: "Stream timestamp verification not performed",
            readbackDeviceTime: Date(timeIntervalSince1970: 100),
            readbackTimeZoneID: TimeZone.current.identifier,
            verificationDeltaSeconds: 0.8,
            operationalEvents: []
        )
    }

    func scanDevices() async throws -> [CollectorDevice] {
        [deviceIdentity]
    }

    func selectDevice(_ device: CollectorDevice) throws {
        guard device.id == deviceIdentity.id else { return }
        connectionState = .deviceSelected
    }

    func connect() async throws {
        connectionState = .connecting
        try await Task.sleep(nanoseconds: 150_000_000)
        connectionState = .connected
    }

    func disconnect() {
        connectionState = .disconnected
        providers.forEach { $0.stop() }
    }

    func streamProviders() -> [HeartRateStreamProviding] {
        providers.filter { availableStreams.contains($0.streamType) }
    }

    func heartRateStreamProvider() -> HeartRateStreamProviding? {
        streamProviders().first(where: { $0.streamType == .heartRate })
    }

    var deviceStatusCapabilities: [DeviceStatusCapability] {
        [
            DeviceStatusCapability(
                kind: .battery,
                isSupported: availableStreams.contains(.battery),
                supportsCallbacks: false,
                supportsPolling: false,
                requiresConnection: true
            )
        ]
    }

    func cachedDeviceStatusSnapshot(for deviceID: String) -> DeviceStatusSnapshot? {
        cachedStatusByDeviceID[deviceID]
    }

    func readDeviceTime(mode: CollectionMode) async -> DeviceTimeActionResult {
        nextReadDeviceTimeResult
    }

    func syncDeviceTimeToPhone(mode: CollectionMode) async -> DeviceTimeActionResult {
        nextSyncDeviceTimeResult
    }

    func prepareDeviceTimeForOfflineSync() async -> DeviceTimeActionResult {
        nextSyncDeviceTimeResult
    }

    func markSelected() {
        connectionState = .deviceSelected
    }
}
