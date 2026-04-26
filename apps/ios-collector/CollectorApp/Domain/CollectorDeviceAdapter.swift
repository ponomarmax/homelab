import Foundation

protocol CollectorDeviceAdapter: AnyObject {
    var deviceIdentity: CollectorDevice { get }
    var connectionState: ConnectionState { get }
    var availableStreams: [CollectorStream] { get }
    var sourceIdentifier: String { get }
    var deviceSelectionActionTitle: String { get }

    func scanDevices() async throws -> [CollectorDevice]
    func selectDevice(_ device: CollectorDevice) throws
    func connect() async throws
    func disconnect()
    func streamProviders() -> [HeartRateStreamProviding]
    func heartRateStreamProvider() -> HeartRateStreamProviding?
}

extension CollectorDeviceAdapter {
    func heartRateStreamProvider() -> HeartRateStreamProviding? {
        streamProviders().first(where: { $0.streamType == .heartRate })
    }
}
