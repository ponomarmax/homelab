import Foundation

protocol CollectorDeviceAdapter: AnyObject {
    var deviceIdentity: CollectorDevice { get }
    var connectionState: ConnectionState { get }
    var availableStreams: [CollectorStream] { get }

    func connect() async throws
    func disconnect()
    func heartRateStreamProvider() -> HeartRateStreamProviding?
}
