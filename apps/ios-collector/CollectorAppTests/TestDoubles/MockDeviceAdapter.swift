import Foundation
@testable import CollectorApp

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

    var connectabilityByDeviceID: [String: DeviceConnectability] = [:]
    var offlineCapabilityByStream: [PolarOfflineStream: OfflineStreamCapability] = Dictionary(
        uniqueKeysWithValues: PolarOfflineStream.allCases.map {
            ($0, OfflineStreamCapability(stream: $0, isSupported: false, reason: "Offline recording is unavailable"))
        }
    )
    var offlineStatusByStream: [PolarOfflineStream: OfflineStreamStatus] = [:]
    var nextStartOfflineResults: [PolarOfflineStream: OfflineStreamOperationResult] = [:]
    var nextStopOfflineResults: [PolarOfflineStream: OfflineStreamOperationResult] = [:]
    var offlineSettingsByStream: [PolarOfflineStream: Result<OfflineStreamSettings, OfflineSettingsFailure>] = [:]
    var nextOfflineRecordings: [OfflineRecordingEntry] = []
    var nextOfflinePreparationResult: OfflineUploadPreparationResult = OfflineUploadPreparationResult(batches: [], messagesByStream: [:])
    var offlineListShouldThrowError: Error?
    var offlineDeleteErrorsByPath: [String: Error] = [:]
    private(set) var lastStartedOfflineStreams: [PolarOfflineStream] = []
    private(set) var lastStartedOfflineRequests: [OfflineRecordingStartRequest] = []
    private(set) var lastStoppedOfflineStreams: [PolarOfflineStream] = []
    private(set) var removedOfflineRecordingPaths: [String] = []

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


    func connectability(for device: CollectorDevice) -> DeviceConnectability {
        connectabilityByDeviceID[device.id] ?? .connectable
    }

    func offlineCapabilities() async -> [OfflineStreamCapability] {
        PolarOfflineStream.allCases.map {
            offlineCapabilityByStream[$0] ?? OfflineStreamCapability(stream: $0, isSupported: false, reason: "Offline recording is unavailable")
        }
    }

    func offlineRecordingStatus() async -> [PolarOfflineStream: OfflineStreamStatus] {
        var statuses: [PolarOfflineStream: OfflineStreamStatus] = [:]
        for stream in PolarOfflineStream.allCases {
            statuses[stream] = offlineStatusByStream[stream] ?? .unknown
        }
        return statuses
    }

    func startOfflineRecordings(streams: [PolarOfflineStream]) async -> [OfflineStreamOperationResult] {
        lastStartedOfflineStreams = streams
        return streams.map { nextStartOfflineResults[$0] ?? OfflineStreamOperationResult(stream: $0, success: true, message: "started") }
    }

    func offlineRecordingSettings(for stream: PolarOfflineStream) async -> Result<OfflineStreamSettings, OfflineSettingsFailure> {
        if let configured = offlineSettingsByStream[stream] {
            return configured
        }
        return .success(
            OfflineStreamSettings(
                stream: stream,
                options: OfflineStreamSettingsOptions(sampleRates: [], resolutions: [], ranges: [], channels: []),
                selected: OfflineStreamSettingsSelection(sampleRate: nil, resolution: nil, range: nil, channels: nil)
            )
        )
    }

    func updateOfflineRecordingSettingsSelection(_ selection: OfflineStreamSettingsSelection, for stream: PolarOfflineStream) {
        guard case .success(let settings) = offlineSettingsByStream[stream] else { return }
        offlineSettingsByStream[stream] = .success(
            OfflineStreamSettings(stream: stream, options: settings.options, selected: selection)
        )
    }

    func startOfflineRecordings(requests: [OfflineRecordingStartRequest]) async -> [OfflineStreamOperationResult] {
        lastStartedOfflineRequests = requests
        return await startOfflineRecordings(streams: requests.map(\.stream))
    }

    func stopOfflineRecordings(streams: [PolarOfflineStream]) async -> [OfflineStreamOperationResult] {
        lastStoppedOfflineStreams = streams
        return streams.map { nextStopOfflineResults[$0] ?? OfflineStreamOperationResult(stream: $0, success: true, message: "stopped") }
    }

    func listOfflineRecordings() async throws -> [OfflineRecordingEntry] {
        if let offlineListShouldThrowError {
            throw offlineListShouldThrowError
        }
        return nextOfflineRecordings
    }

    func removeOfflineRecording(path: String) async throws {
        removedOfflineRecordingPaths.append(path)
        if let error = offlineDeleteErrorsByPath[path] {
            throw error
        }
    }

    func prepareOfflineUploadBatches() async -> OfflineUploadPreparationResult {
        nextOfflinePreparationResult
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
