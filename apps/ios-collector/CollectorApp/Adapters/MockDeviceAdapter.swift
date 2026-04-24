import Foundation

final class MockDeviceAdapter: CollectorDeviceAdapter {
    private(set) var connectionState: ConnectionState = .disconnected

    let deviceIdentity: CollectorDevice
    let availableStreams: [CollectorStream]

    private let hrProvider: HeartRateStreamProviding

    init(
        deviceIdentity: CollectorDevice = CollectorDevice(
            id: "mock-polar-verity-sense",
            name: "Mock Polar Verity Sense",
            vendor: "Polar",
            model: "Verity Sense"
        ),
        availableStreams: [CollectorStream] = [.heartRate],
        hrProvider: HeartRateStreamProviding = MockHeartRateStreamProvider()
    ) {
        self.deviceIdentity = deviceIdentity
        self.availableStreams = availableStreams
        self.hrProvider = hrProvider
    }

    func connect() async throws {
        connectionState = .connecting
        try await Task.sleep(nanoseconds: 150_000_000)
        connectionState = .connected
    }

    func disconnect() {
        connectionState = .disconnected
        hrProvider.stop()
    }

    func heartRateStreamProvider() -> HeartRateStreamProviding? {
        availableStreams.contains(.heartRate) ? hrProvider : nil
    }

    func markSelected() {
        connectionState = .deviceSelected
    }
}
