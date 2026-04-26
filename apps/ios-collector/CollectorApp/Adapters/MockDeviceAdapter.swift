import Foundation

final class MockDeviceAdapter: CollectorDeviceAdapter {
    private(set) var connectionState: ConnectionState = .disconnected

    let deviceIdentity: CollectorDevice
    let availableStreams: [CollectorStream]
    let sourceIdentifier: String = "mock"
    let deviceSelectionActionTitle: String = "Select Mock Device"

    private let providers: [HeartRateStreamProviding]

    init(
        deviceIdentity: CollectorDevice = CollectorDevice(
            id: "mock-polar-verity-sense",
            name: "Mock Polar Verity Sense",
            vendor: "Polar",
            model: "Verity Sense"
        ),
        availableStreams: [CollectorStream] = [.heartRate],
        hrProvider: HeartRateStreamProviding = MockHeartRateStreamProvider(),
        additionalProviders: [HeartRateStreamProviding] = []
    ) {
        self.deviceIdentity = deviceIdentity
        self.availableStreams = availableStreams
        self.providers = [hrProvider] + additionalProviders
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

    func markSelected() {
        connectionState = .deviceSelected
    }
}
