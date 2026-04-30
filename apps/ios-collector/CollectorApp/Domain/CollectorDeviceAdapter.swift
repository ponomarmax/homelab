import Foundation

protocol CollectorDeviceAdapter: DeviceStatusProvider {
    var deviceIdentity: CollectorDevice { get }
    var connectionState: ConnectionState { get }
    var availableStreams: [CollectorStream] { get }
    var sourceIdentifier: String { get }
    var deviceSelectionActionTitle: String { get }
    var deviceTimeAvailability: DeviceTimeActionAvailability { get }

    func scanDevices() async throws -> [CollectorDevice]
    func scanDevices(onDiscovered: @escaping @Sendable ([CollectorDevice]) -> Void) async throws -> [CollectorDevice]
    func selectDevice(_ device: CollectorDevice) throws
    func connect() async throws
    func disconnect()
    func connectability(for device: CollectorDevice) -> DeviceConnectability
    func streamProviders() -> [HeartRateStreamProviding]

    func offlineCapabilities() async -> [OfflineStreamCapability]
    func startOfflineRecordings(streams: [PolarOfflineStream]) async -> [OfflineStreamOperationResult]
    func stopOfflineRecordings(streams: [PolarOfflineStream]) async -> [OfflineStreamOperationResult]
    func listOfflineRecordings() async throws -> [OfflineRecordingEntry]
    func prepareOfflineUploadBatches() async -> OfflineUploadPreparationResult
    func heartRateStreamProvider() -> HeartRateStreamProviding?
    func readDeviceTime(mode: CollectionMode) async -> DeviceTimeActionResult
    func syncDeviceTimeToPhone(mode: CollectionMode) async -> DeviceTimeActionResult
    func prepareDeviceTimeForOfflineSync() async -> DeviceTimeActionResult
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

    func connectability(for device: CollectorDevice) -> DeviceConnectability {
        .connectable
    }

    func offlineCapabilities() async -> [OfflineStreamCapability] {
        PolarOfflineStream.allCases.map {
            OfflineStreamCapability(stream: $0, isSupported: false, reason: "Offline recording is unavailable")
        }
    }

    func startOfflineRecordings(streams: [PolarOfflineStream]) async -> [OfflineStreamOperationResult] {
        streams.map { OfflineStreamOperationResult(stream: $0, success: false, message: "Offline recording is unavailable") }
    }

    func stopOfflineRecordings(streams: [PolarOfflineStream]) async -> [OfflineStreamOperationResult] {
        streams.map { OfflineStreamOperationResult(stream: $0, success: false, message: "Offline recording is unavailable") }
    }

    func listOfflineRecordings() async throws -> [OfflineRecordingEntry] {
        []
    }

    func prepareOfflineUploadBatches() async -> OfflineUploadPreparationResult {
        OfflineUploadPreparationResult(batches: [], messagesByStream: [:])
    }

    var deviceStatusCapabilities: [DeviceStatusCapability] { [] }
    var deviceTimeAvailability: DeviceTimeActionAvailability { .unavailable }

    func readDeviceTime(mode: CollectionMode) async -> DeviceTimeActionResult {
        DeviceTimeActionResult(
            state: .unavailable,
            message: "Read-back unavailable",
            debugDetails: "Device adapter does not support get device time",
            readbackDeviceTime: nil,
            readbackTimeZoneID: nil,
            verificationDeltaSeconds: nil,
            operationalEvents: []
        )
    }

    func syncDeviceTimeToPhone(mode: CollectionMode) async -> DeviceTimeActionResult {
        DeviceTimeActionResult(
            state: .unavailable,
            message: "Read-back unavailable",
            debugDetails: "Device adapter does not support time sync",
            readbackDeviceTime: nil,
            readbackTimeZoneID: nil,
            verificationDeltaSeconds: nil,
            operationalEvents: []
        )
    }

    func prepareDeviceTimeForOfflineSync() async -> DeviceTimeActionResult {
        await syncDeviceTimeToPhone(mode: .offlineRecording)
    }

    func cachedDeviceStatusSnapshot(for deviceID: String) -> DeviceStatusSnapshot? {
        nil
    }
}
