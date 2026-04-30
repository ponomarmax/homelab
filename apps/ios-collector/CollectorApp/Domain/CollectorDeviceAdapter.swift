import Foundation

protocol CollectorDeviceAdapter: DeviceStatusProvider {
    var deviceIdentity: CollectorDevice { get }
    var connectionState: ConnectionState { get }
    var availableStreams: [CollectorStream] { get }
    var sourceIdentifier: String { get }
    var deviceSelectionActionTitle: String { get }

    func scanDevices() async throws -> [CollectorDevice]
    func scanDevices(onDiscovered: @escaping @Sendable ([CollectorDevice]) -> Void) async throws -> [CollectorDevice]
    func selectDevice(_ device: CollectorDevice) throws
    func connect() async throws
    func disconnect()
    func streamProviders() -> [HeartRateStreamProviding]
    func heartRateStreamProvider() -> HeartRateStreamProviding?
}

extension CollectorDeviceAdapter {
    func scanDevices(onDiscovered: @escaping @Sendable ([CollectorDevice]) -> Void) async throws -> [CollectorDevice] {
        let devices = try await scanDevices()
        onDiscovered(devices)
        return devices
    }

    func heartRateStreamProvider() -> HeartRateStreamProviding? {
        streamProviders().first(where: { $0.streamType == .heartRate })
    }

    var deviceStatusCapabilities: [DeviceStatusCapability] { [] }

    func cachedDeviceStatusSnapshot(for deviceID: String) -> DeviceStatusSnapshot? {
        nil
    }
}
