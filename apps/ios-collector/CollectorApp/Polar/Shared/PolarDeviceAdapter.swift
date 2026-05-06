import Foundation
import CoreBluetooth

#if targetEnvironment(simulator) && arch(x86_64)
enum PolarAdapterError: LocalizedError {
    case unsupportedEnvironment

    var errorDescription: String? {
        switch self {
        case .unsupportedEnvironment:
            return "Polar BLE SDK is unavailable in this build environment"
        }
    }
}

final class PolarDeviceAdapter: CollectorDeviceAdapter {
    private(set) var connectionState: ConnectionState = .disconnected
    let sourceIdentifier: String = "polar"
    let deviceSelectionActionTitle: String = "Scan Polar Devices"

    let deviceIdentity: CollectorDevice = CollectorDevice(
        id: "polar-unavailable",
        name: "Polar Device",
        vendor: "Polar",
        model: "Unavailable"
    )

    let availableStreams: [CollectorStream] = [.heartRate, .ecg, .accelerometer, .battery]
    let deviceStatusCapabilities: [DeviceStatusCapability] = [
        DeviceStatusCapability(
            kind: .battery,
            isSupported: false,
            supportsCallbacks: false,
            supportsPolling: false,
            requiresConnection: true
        )
    ]
    var deviceTimeAvailability: DeviceTimeActionAvailability {
        .unavailable
    }
    func scanDevices() async throws -> [CollectorDevice] {
        throw PolarAdapterError.unsupportedEnvironment
    }

    func scanDevices(onDiscovered: @escaping @Sendable ([CollectorDevice]) -> Void) async throws -> [CollectorDevice] {
        let devices = try await scanDevices()
        onDiscovered(devices)
        return devices
    }

    func selectDevice(_ device: CollectorDevice) throws {
        throw PolarAdapterError.unsupportedEnvironment
    }

    func connect() async throws {
        throw PolarAdapterError.unsupportedEnvironment
    }

    func disconnect() {
        connectionState = .disconnected
    }

    func connectability(for device: CollectorDevice) -> DeviceConnectability {
        DeviceConnectability(
            isConnectable: false,
            reason: "Polar BLE SDK is unavailable in this build environment"
        )
    }

    func streamProviders() -> [HeartRateStreamProviding] {
        []
    }

    func offlineCapabilities() async -> [OfflineStreamCapability] {
        PolarOfflineStream.allCases.map {
            OfflineStreamCapability(
                stream: $0,
                isSupported: false,
                reason: "Offline recording unavailable in this build environment"
            )
        }
    }

    func offlineRecordingStatus() async -> [PolarOfflineStream: OfflineStreamStatus] {
        Dictionary(
            uniqueKeysWithValues: PolarOfflineStream.allCases.map { ($0, .unavailable) }
        )
    }

    func startOfflineRecordings(streams: [PolarOfflineStream]) async -> [OfflineStreamOperationResult] {
        streams.map {
            OfflineStreamOperationResult(
                stream: $0,
                success: false,
                message: "Offline recording unavailable in this build environment"
            )
        }
    }

    func offlineRecordingSettings(for stream: PolarOfflineStream) async -> Result<OfflineStreamSettings, OfflineSettingsFailure> {
        .failure(OfflineSettingsFailure(message: "Offline recording unavailable in this build environment"))
    }

    func updateOfflineRecordingSettingsSelection(_ selection: OfflineStreamSettingsSelection, for stream: PolarOfflineStream) {}

    func startOfflineRecordings(requests: [OfflineRecordingStartRequest]) async -> [OfflineStreamOperationResult] {
        await startOfflineRecordings(streams: requests.map(\.stream))
    }

    func stopOfflineRecordings(streams: [PolarOfflineStream]) async -> [OfflineStreamOperationResult] {
        streams.map {
            OfflineStreamOperationResult(
                stream: $0,
                success: false,
                message: "Offline recording unavailable in this build environment"
            )
        }
    }

    func listOfflineRecordings() async throws -> [OfflineRecordingEntry] {
        []
    }

    func removeOfflineRecording(path: String) async throws {
        throw PolarAdapterError.unsupportedEnvironment
    }

    func prepareOfflineUploadBatches(allowedPaths: Set<String>? = nil) async -> OfflineUploadPreparationResult {
        OfflineUploadPreparationResult(batches: [], messagesByStream: [:])
    }

    func heartRateStreamProvider() -> HeartRateStreamProviding? {
        nil
    }

    func cachedDeviceStatusSnapshot(for deviceID: String) -> DeviceStatusSnapshot? {
        nil
    }

    func readDeviceTime(mode: CollectionMode) async -> DeviceTimeActionResult {
        DeviceTimeActionResult(
            state: .unavailable,
            message: "Read-back unavailable",
            debugDetails: "Polar SDK unavailable in simulator build",
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
            debugDetails: "Polar SDK unavailable in simulator build",
            readbackDeviceTime: nil,
            readbackTimeZoneID: nil,
            verificationDeltaSeconds: nil,
            operationalEvents: []
        )
    }

    func prepareDeviceTimeForOfflineSync() async -> DeviceTimeActionResult {
        await syncDeviceTimeToPhone(mode: .offlineRecording)
    }
}
#else
#if canImport(PolarBleSdk) && canImport(RxSwift)
@preconcurrency import PolarBleSdk
@preconcurrency import RxSwift

enum PolarAdapterError: LocalizedError {
    case noDeviceSelected
    case deviceNotDiscovered
    case bluetoothPoweredOff
    case connectionInterrupted

    var errorDescription: String? {
        switch self {
        case .noDeviceSelected:
            return "No Polar device selected"
        case .deviceNotDiscovered:
            return "Selected device is not in the latest scan results"
        case .bluetoothPoweredOff:
            return "Bluetooth is off"
        case .connectionInterrupted:
            return "Polar connection interrupted"
        }
    }
}

final class PolarDeviceAdapter: NSObject, CollectorDeviceAdapter {
    private(set) var connectionState: ConnectionState = .disconnected
    let sourceIdentifier: String = "polar"
    let deviceSelectionActionTitle: String = "Scan Polar Devices"

    var deviceIdentity: CollectorDevice {
        selectedDevice ?? CollectorDevice(
            id: "polar-unknown",
            name: "Polar Device",
            vendor: "Polar",
            model: "Unknown"
        )
    }

    var availableStreams: [CollectorStream] {
        var streams: [CollectorStream] = [.heartRate]
        if shouldEnableEcgStream {
            streams.append(.ecg)
        }
        if shouldEnableAccStream {
            streams.append(.accelerometer)
        }
        streams.append(.battery)
        return streams
    }

    private var api: PolarBleApi
    private let scanTimeoutSeconds: Int
    private let scanNamePrefix: String?

    private var selectedDevice: CollectorDevice?
    private var selectedPolarIdentifier: String?
    private var discoveredDeviceMap: [String: PolarDeviceInfo] = [:]

    private var discoveredOnlineDataTypes: Set<PolarDeviceDataType> = []
    private var offlineSelectedSettingsByStream: [PolarOfflineStream: OfflineStreamSettingsSelection] = [:]
    private var hrProvider: PolarHrStreamProvider
    private var ecgProvider: PolarEcgStreamProvider
    private var accProvider: PolarAccStreamProvider
    private var batteryProvider: PolarBatteryStreamProvider

    private var scanDisposable: Disposable?
    private var connectContinuation: CheckedContinuation<Void, Error>?
    private var timeSetupDisposable: Disposable?
    private var timeReadbackDisposable: Disposable?
    private var streamCapabilitiesDisposable: Disposable?
    private var hrCapabilitiesFallbackDisposable: Disposable?

    private var batteryPollingTask: Task<Void, Never>?
    private var streamCapabilitiesRetryWorkItem: DispatchWorkItem?

    private var isBluetoothOn = true
    private var isSelectedDeviceConnected = false
    private var isSelectedDeviceHrFeatureReady = false
    private var isSelectedDeviceOnlineStreamingFeatureReady = false
    private var isSelectedDeviceOnlineStreamingUnavailable = false
    private var didReceiveFeaturesReadinessSnapshot = false
    private var connectStartedAt: Date?
    private var didRunPostConnectSetup = false
    private var capabilityProbeInFlight = false
    private var capabilityProbeCompleted = false
    private var capabilityProbeAttempt = 0

    private var latestBatteryLevelPercent: Int?
    private var latestChargeState: String?
    private var latestPowerSources: [String]?
    private var cachedStatusByDeviceID: [String: DeviceStatusSnapshot] = [:]
    private var lastKnownTimeFeatureUnavailable = false

    var deviceStatusCapabilities: [DeviceStatusCapability] {
        [
            DeviceStatusCapability(
                kind: .battery,
                isSupported: true,
                supportsCallbacks: true,
                supportsPolling: true,
                requiresConnection: true
            )
        ]
    }

    var deviceTimeAvailability: DeviceTimeActionAvailability {
        guard selectedPolarIdentifier != nil else {
            return DeviceTimeActionAvailability(
                canReadDeviceTime: false,
                canSyncDeviceTime: false,
                reason: "Select and connect a device first"
            )
        }
        guard connectionState == .connected else {
            return DeviceTimeActionAvailability(
                canReadDeviceTime: false,
                canSyncDeviceTime: false,
                reason: "Device disconnected"
            )
        }
        guard !lastKnownTimeFeatureUnavailable else {
            return DeviceTimeActionAvailability(
                canReadDeviceTime: false,
                canSyncDeviceTime: false,
                reason: "Time setup feature unavailable on selected device"
            )
        }
        guard let selectedPolarIdentifier,
              api.isFeatureReady(selectedPolarIdentifier, feature: .feature_polar_device_time_setup) else {
            return DeviceTimeActionAvailability(
                canReadDeviceTime: false,
                canSyncDeviceTime: false,
                reason: "Time setup feature not ready"
            )
        }
        return DeviceTimeActionAvailability(canReadDeviceTime: true, canSyncDeviceTime: true, reason: nil)
    }

    private var isLikelyH10: Bool {
        let name = selectedDevice?.name.lowercased() ?? ""
        let model = selectedDevice?.model.lowercased() ?? ""
        return name.contains("h10") || model.contains("h10")
    }

    private var shouldEnableEcgStream: Bool {
        discoveredOnlineDataTypes.contains(.ecg)
            || (isLikelyH10
                && isSelectedDeviceOnlineStreamingFeatureReady
                && PolarH10OnlineDefaults.streams.contains(.ecg))
    }

    private var shouldEnableAccStream: Bool {
        discoveredOnlineDataTypes.contains(.acc)
            || ((isLikelyH10 && PolarH10OnlineDefaults.streams.contains(.accelerometer))
                || (!isLikelyH10 && PolarVeritySenseOnlineDefaults.streams.contains(.accelerometer)))
                && isSelectedDeviceOnlineStreamingFeatureReady
    }

    init(
        scanTimeoutSeconds: Int = 8,
        scanNamePrefix: String? = "Polar"
    ) {
        let api = PolarBleApiDefaultImpl.polarImplementation(
            DispatchQueue.main,
            features: [
                .feature_hr,
                .feature_polar_online_streaming,
                .feature_polar_offline_recording,
                .feature_battery_info,
                .feature_device_info,
                .feature_polar_device_time_setup
            ]
        )

        self.api = api
        self.scanTimeoutSeconds = scanTimeoutSeconds
        self.scanNamePrefix = scanNamePrefix

        self.hrProvider = PolarHrStreamProvider(api: api)
        self.ecgProvider = PolarEcgStreamProvider(api: api)
        self.accProvider = PolarAccStreamProvider(api: api)
        self.batteryProvider = PolarBatteryStreamProvider()

        super.init()

        self.hrProvider = PolarHrStreamProvider(
            api: self.api,
            deviceIDProvider: { [weak self] in self?.selectedPolarIdentifier },
            logger: { [weak self] message in self?.log(message) }
        )
        self.ecgProvider = PolarEcgStreamProvider(
            api: self.api,
            deviceIDProvider: { [weak self] in self?.selectedPolarIdentifier },
            logger: { [weak self] message in self?.log(message) }
        )
        self.accProvider = PolarAccStreamProvider(
            api: self.api,
            deviceIDProvider: { [weak self] in self?.selectedPolarIdentifier },
            logger: { [weak self] message in self?.log(message) }
        )
        self.batteryProvider = PolarBatteryStreamProvider(
            logger: { [weak self] message in self?.log(message) }
        )

        self.api.observer = self
        self.api.powerStateObserver = self
        self.api.deviceFeaturesObserver = self
        self.api.deviceInfoObserver = self
    }

    func scanDevices() async throws -> [CollectorDevice] {
        try await scanDevices { _ in }
    }

    func scanDevices(onDiscovered: @escaping @Sendable ([CollectorDevice]) -> Void) async throws -> [CollectorDevice] {
        try await withCheckedThrowingContinuation { continuation in
            var isResumed = false

            let resume: (Result<[CollectorDevice], Error>) -> Void = { result in
                guard !isResumed else { return }
                isResumed = true
                continuation.resume(with: result)
            }

            discoveredDeviceMap.removeAll()
            scanDisposable?.dispose()

            let scanStream: Observable<PolarDeviceInfo>
            if let scanNamePrefix {
                scanStream = api.searchForDevice(withRequiredDeviceNamePrefix: scanNamePrefix)
            } else {
                scanStream = api.searchForDevice()
            }

            log("Scan started")
            scanDisposable = scanStream
                .observe(on: MainScheduler.asyncInstance)
                .subscribe(
                    onNext: { [weak self] info in
                        guard let self else { return }
                        self.discoveredDeviceMap[info.deviceId] = info
                        self.log("Device discovered: \(info.deviceId) (\(info.name))")
                        let devices = self.discoveredDeviceMap.values
                            .sorted { $0.rssi > $1.rssi }
                            .map { discovered in
                                CollectorDevice(
                                    id: discovered.deviceId,
                                    name: discovered.name,
                                    vendor: "Polar",
                                    model: self.resolveModel(from: discovered.name)
                                )
                            }
                        onDiscovered(devices)
                    },
                    onError: { [weak self] error in
                        self?.scanDisposable = nil
                        self?.log("Scan failed: \(error.localizedDescription)")
                        resume(.failure(error))
                    }
                )

            DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(scanTimeoutSeconds)) { [weak self] in
                guard let self else { return }

                self.scanDisposable?.dispose()
                self.scanDisposable = nil

                let devices = self.discoveredDeviceMap.values
                    .sorted { $0.rssi > $1.rssi }
                    .map { info in
                        CollectorDevice(
                            id: info.deviceId,
                            name: info.name,
                            vendor: "Polar",
                            model: self.resolveModel(from: info.name)
                        )
                    }

                self.log("Scan completed: \(devices.count) device(s)")
                resume(.success(devices))
            }
        }
    }

    func selectDevice(_ device: CollectorDevice) throws {
        guard let info = discoveredDeviceMap[device.id] else {
            throw PolarAdapterError.deviceNotDiscovered
        }

        selectedPolarIdentifier = info.deviceId
        selectedDevice = CollectorDevice(
            id: info.deviceId,
            name: info.name,
            vendor: "Polar",
            model: resolveModel(from: info.name)
        )
        connectionState = .deviceSelected
        discoveredOnlineDataTypes = []
        capabilityProbeInFlight = false
        capabilityProbeCompleted = false
        capabilityProbeAttempt = 0
        isSelectedDeviceOnlineStreamingFeatureReady = false
        isSelectedDeviceOnlineStreamingUnavailable = false
        didReceiveFeaturesReadinessSnapshot = false
        lastKnownTimeFeatureUnavailable = false
        connectStartedAt = nil
        resetBatteryState()
        log("Device selected: \(info.deviceId)")
    }

    func connect() async throws {
        guard isBluetoothOn else {
            log("Connect blocked: Bluetooth is powered off")
            throw PolarAdapterError.bluetoothPoweredOff
        }
        guard let selectedPolarIdentifier else {
            log("Connect blocked: no selected Polar device")
            throw PolarAdapterError.noDeviceSelected
        }

        log("Connect started: \(selectedPolarIdentifier)")
        connectionState = .connecting
        isSelectedDeviceConnected = false
        connectStartedAt = Date()
        didReceiveFeaturesReadinessSnapshot = false
        lastKnownTimeFeatureUnavailable = false
        didRunPostConnectSetup = false
        capabilityProbeInFlight = false
        capabilityProbeCompleted = false
        capabilityProbeAttempt = 0
        discoveredOnlineDataTypes = []
        isSelectedDeviceOnlineStreamingFeatureReady = api.isFeatureReady(
            selectedPolarIdentifier,
            feature: .feature_polar_online_streaming
        )
        isSelectedDeviceOnlineStreamingUnavailable = false

        isSelectedDeviceHrFeatureReady = api.isFeatureReady(selectedPolarIdentifier, feature: .feature_hr)

        try await withCheckedThrowingContinuation { continuation in
            connectContinuation = continuation

            do {
                try api.connectToDevice(selectedPolarIdentifier)
                DispatchQueue.main.asyncAfter(deadline: .now() + 12) { [weak self] in
                    self?.tryResumeConnectIfReady(forceAfterReadinessTimeout: true)
                }
                tryResumeConnectIfReady(forceAfterReadinessTimeout: false)
            } catch {
                connectContinuation = nil
                connectionState = .deviceSelected
                log("Connect failed: \(error.localizedDescription)")
                continuation.resume(throwing: error)
            }
        }
    }

    func disconnect() {
        streamProviders().forEach { $0.stop() }

        timeSetupDisposable?.dispose()
        timeSetupDisposable = nil
        timeReadbackDisposable?.dispose()
        timeReadbackDisposable = nil
        streamCapabilitiesDisposable?.dispose()
        streamCapabilitiesDisposable = nil
        hrCapabilitiesFallbackDisposable?.dispose()
        hrCapabilitiesFallbackDisposable = nil
        streamCapabilitiesRetryWorkItem?.cancel()
        streamCapabilitiesRetryWorkItem = nil
        batteryPollingTask?.cancel()
        batteryPollingTask = nil

        if let selectedPolarIdentifier {
            try? api.disconnectFromDevice(selectedPolarIdentifier)
            log("Disconnect requested: \(selectedPolarIdentifier)")
        }

        isSelectedDeviceConnected = false
        isSelectedDeviceHrFeatureReady = false
        isSelectedDeviceOnlineStreamingFeatureReady = false
        isSelectedDeviceOnlineStreamingUnavailable = false
        didRunPostConnectSetup = false
        capabilityProbeInFlight = false
        capabilityProbeCompleted = false
        capabilityProbeAttempt = 0
        connectStartedAt = nil
        didReceiveFeaturesReadinessSnapshot = false
        lastKnownTimeFeatureUnavailable = false
        connectContinuation = nil
        connectionState = selectedDevice == nil ? .disconnected : .deviceSelected
    }

    func connectability(for device: CollectorDevice) -> DeviceConnectability {
        guard isBluetoothOn else {
            return DeviceConnectability(isConnectable: false, reason: "Bluetooth is off")
        }
        guard let discovered = discoveredDeviceMap[device.id] else {
            return DeviceConnectability(
                isConnectable: false,
                reason: "Device is no longer in current scan results"
            )
        }
        guard discovered.connectable else {
            return DeviceConnectability(
                isConnectable: false,
                reason: "Device advertisement is not connectable yet"
            )
        }
        return .connectable
    }

    func streamProviders() -> [HeartRateStreamProviding] {
        var providers: [HeartRateStreamProviding] = [hrProvider]
        if shouldEnableEcgStream {
            providers.append(ecgProvider)
        }
        if shouldEnableAccStream {
            providers.append(accProvider)
        }
        providers.append(batteryProvider)
        return providers
    }

    func cachedDeviceStatusSnapshot(for deviceID: String) -> DeviceStatusSnapshot? {
        cachedStatusByDeviceID[deviceID]
    }

    func offlineCapabilities() async -> [OfflineStreamCapability] {
        guard let selectedPolarIdentifier else {
            return PolarOfflineStream.allCases.map {
                OfflineStreamCapability(stream: $0, isSupported: false, reason: "Select a device first")
            }
        }
        guard connectionState == .connected else {
            return PolarOfflineStream.allCases.map {
                OfflineStreamCapability(stream: $0, isSupported: false, reason: "Device disconnected")
            }
        }
        guard api.isFeatureReady(selectedPolarIdentifier, feature: .feature_polar_offline_recording) else {
            return PolarOfflineStream.allCases.map {
                OfflineStreamCapability(stream: $0, isSupported: false, reason: "Offline recording feature not ready")
            }
        }

        do {
            let available = try await withCheckedThrowingContinuation { continuation in
                streamCapabilitiesDisposable?.dispose()
                streamCapabilitiesDisposable = api.getAvailableOfflineRecordingDataTypes(selectedPolarIdentifier)
                    .observe(on: MainScheduler.asyncInstance)
                    .subscribe(
                        onSuccess: { types in continuation.resume(returning: types) },
                        onFailure: { error in continuation.resume(throwing: error) }
                    )
            }
            return PolarOfflineStream.allCases.map { stream in
                let dataType = self.dataType(for: stream)
                let supported = available.contains(dataType)
                return OfflineStreamCapability(
                    stream: stream,
                    isSupported: supported,
                    reason: supported ? nil : "Stream unsupported by selected device"
                )
            }
        } catch {
            return PolarOfflineStream.allCases.map {
                OfflineStreamCapability(stream: $0, isSupported: false, reason: "Offline capability query failed: \(error.localizedDescription)")
            }
        }
    }

    func offlineRecordingStatus() async -> [PolarOfflineStream: OfflineStreamStatus] {
        guard let selectedPolarIdentifier else {
            return Dictionary(
                uniqueKeysWithValues: PolarOfflineStream.allCases.map { ($0, .unknown) }
            )
        }
        guard connectionState == .connected else {
            return Dictionary(
                uniqueKeysWithValues: PolarOfflineStream.allCases.map { ($0, .unavailable) }
            )
        }
        guard api.isFeatureReady(selectedPolarIdentifier, feature: .feature_polar_offline_recording) else {
            return Dictionary(
                uniqueKeysWithValues: PolarOfflineStream.allCases.map { ($0, .unavailable) }
            )
        }

        do {
            let statusByType = try await withCheckedThrowingContinuation { continuation in
                streamCapabilitiesDisposable?.dispose()
                streamCapabilitiesDisposable = api.getOfflineRecordingStatus(selectedPolarIdentifier)
                    .observe(on: MainScheduler.asyncInstance)
                    .subscribe(
                        onSuccess: { status in continuation.resume(returning: status) },
                        onFailure: { error in continuation.resume(throwing: error) }
                    )
            }
            var statuses: [PolarOfflineStream: OfflineStreamStatus] = [:]
            for stream in PolarOfflineStream.allCases {
                let type = dataType(for: stream)
                if let isRecording = statusByType[type] {
                    statuses[stream] = isRecording ? .recording : .ready
                } else {
                    statuses[stream] = .unknown
                }
            }
            return statuses
        } catch {
            return Dictionary(
                uniqueKeysWithValues: PolarOfflineStream.allCases.map { ($0, .failed) }
            )
        }
    }

    func startOfflineRecordings(streams: [PolarOfflineStream]) async -> [OfflineStreamOperationResult] {
        let requests = streams.map { stream in
            OfflineRecordingStartRequest(stream: stream, selectedSettings: offlineSelectedSettingsByStream[stream])
        }
        return await startOfflineRecordings(requests: requests)
    }

    func offlineRecordingSettings(for stream: PolarOfflineStream) async -> Result<OfflineStreamSettings, OfflineSettingsFailure> {
        guard let selectedPolarIdentifier else {
            return .failure(OfflineSettingsFailure(message: "No selected device"))
        }
        do {
            let rawSettings = try await withCheckedThrowingContinuation { continuation in
                streamCapabilitiesDisposable?.dispose()
                streamCapabilitiesDisposable = api.requestOfflineRecordingSettings(selectedPolarIdentifier, feature: dataType(for: stream))
                    .observe(on: MainScheduler.asyncInstance)
                    .subscribe(
                        onSuccess: { settings in continuation.resume(returning: settings) },
                        onFailure: { error in continuation.resume(throwing: error) }
                    )
            }
            let options = Self.mapSettingsOptions(from: rawSettings)
            let selected = offlineSelectedSettingsByStream[stream] ?? Self.defaultSelection(from: rawSettings)
            offlineSelectedSettingsByStream[stream] = selected
            return .success(OfflineStreamSettings(stream: stream, options: options, selected: selected))
        } catch {
            if stream == .hr || stream == .ppi {
                let selected = offlineSelectedSettingsByStream[stream] ?? OfflineStreamSettingsSelection(sampleRate: nil, resolution: nil, range: nil, channels: nil)
                return .success(
                    OfflineStreamSettings(
                        stream: stream,
                        options: OfflineStreamSettingsOptions(sampleRates: [], resolutions: [], ranges: [], channels: []),
                        selected: selected
                    )
                )
            }
            return .failure(OfflineSettingsFailure(message: error.localizedDescription))
        }
    }

    func updateOfflineRecordingSettingsSelection(_ selection: OfflineStreamSettingsSelection, for stream: PolarOfflineStream) {
        offlineSelectedSettingsByStream[stream] = selection
    }

    func startOfflineRecordings(requests: [OfflineRecordingStartRequest]) async -> [OfflineStreamOperationResult] {
        guard let selectedPolarIdentifier else {
            return requests.map { OfflineStreamOperationResult(stream: $0.stream, success: false, message: "No selected device") }
        }
        let capabilities = await offlineCapabilities()
        let capabilitiesByStream = Dictionary(uniqueKeysWithValues: capabilities.map { ($0.stream, $0) })
        var results: [OfflineStreamOperationResult] = []
        for request in requests {
            let stream = request.stream
            if let capability = capabilitiesByStream[stream], !capability.isSupported {
                results.append(
                    OfflineStreamOperationResult(
                        stream: stream,
                        success: false,
                        message: capability.reason ?? "Offline stream unsupported"
                    )
                )
                continue
            }
            do {
                let polarSettings = Self.makePolarSensorSetting(from: request.selectedSettings)
                try await retryOfflineGattOperation {
                    try await withCheckedThrowingContinuation { continuation in
                        timeSetupDisposable?.dispose()
                        timeSetupDisposable = api.startOfflineRecording(
                            selectedPolarIdentifier,
                            feature: dataType(for: stream),
                            settings: polarSettings,
                            secret: nil
                        )
                        .observe(on: MainScheduler.asyncInstance)
                        .subscribe(
                            onCompleted: { continuation.resume() },
                            onError: { error in continuation.resume(throwing: error) }
                        )
                    }
                }
                results.append(OfflineStreamOperationResult(stream: stream, success: true, message: "Started"))
            } catch {
                results.append(
                    OfflineStreamOperationResult(
                        stream: stream,
                        success: false,
                        message: Self.offlineOperationErrorMessage(error, action: "start", stream: stream, settings: request.selectedSettings)
                    )
                )
            }
            await sleepMilliseconds(250)
        }
        return results
    }

    func stopOfflineRecordings(streams: [PolarOfflineStream]) async -> [OfflineStreamOperationResult] {
        guard let selectedPolarIdentifier else {
            return streams.map { OfflineStreamOperationResult(stream: $0, success: false, message: "No selected device") }
        }
        var results: [OfflineStreamOperationResult] = []
        for stream in streams {
            do {
                try await retryOfflineGattOperation {
                    try await withCheckedThrowingContinuation { continuation in
                        timeReadbackDisposable?.dispose()
                        timeReadbackDisposable = api.stopOfflineRecording(
                            selectedPolarIdentifier,
                            feature: dataType(for: stream)
                        )
                        .observe(on: MainScheduler.asyncInstance)
                        .subscribe(
                            onCompleted: { continuation.resume() },
                            onError: { error in continuation.resume(throwing: error) }
                        )
                    }
                }
                results.append(OfflineStreamOperationResult(stream: stream, success: true, message: "Stopped"))
            } catch {
                results.append(
                    OfflineStreamOperationResult(
                        stream: stream,
                        success: false,
                        message: Self.offlineOperationErrorMessage(error, action: "stop")
                    )
                )
            }
            await sleepMilliseconds(250)
        }
        return results
    }

    func listOfflineRecordings() async throws -> [OfflineRecordingEntry] {
        guard let selectedPolarIdentifier else {
            return []
        }
        return try await withCheckedThrowingContinuation { continuation in
            var entries: [OfflineRecordingEntry] = []
            streamCapabilitiesDisposable?.dispose()
            streamCapabilitiesDisposable = api.listOfflineRecordings(selectedPolarIdentifier)
                .observe(on: MainScheduler.asyncInstance)
                .subscribe(
                    onNext: { entry in
                        entries.append(
                            OfflineRecordingEntry(
                                id: entry.path,
                                path: entry.path,
                                stream: Self.offlineStream(from: entry.type),
                                sizeBytes: entry.size,
                                startedAt: entry.date,
                                status: "available"
                            )
                        )
                    },
                    onError: { error in continuation.resume(throwing: error) },
                    onCompleted: { continuation.resume(returning: entries) }
                )
        }
    }

    func removeOfflineRecording(path: String) async throws {
        guard let selectedPolarIdentifier else {
            throw PolarAdapterError.noDeviceSelected
        }
        let entries = try await withCheckedThrowingContinuation { continuation in
            var listedEntries: [PolarOfflineRecordingEntry] = []
            streamCapabilitiesDisposable?.dispose()
            streamCapabilitiesDisposable = api.listOfflineRecordings(selectedPolarIdentifier)
                .observe(on: MainScheduler.asyncInstance)
                .subscribe(
                    onNext: { entry in listedEntries.append(entry) },
                    onError: { error in continuation.resume(throwing: error) },
                    onCompleted: { continuation.resume(returning: listedEntries) }
                )
        }
        guard let entryToRemove = entries.first(where: { $0.path == path }) else { return }
        try await retryOfflineGattOperation {
            try await withCheckedThrowingContinuation { continuation in
                streamCapabilitiesDisposable?.dispose()
                streamCapabilitiesDisposable = api.removeOfflineRecord(
                    selectedPolarIdentifier,
                    entry: entryToRemove
                )
                .observe(on: MainScheduler.asyncInstance)
                .subscribe(
                    onCompleted: { continuation.resume() },
                    onError: { error in continuation.resume(throwing: error) }
                )
            }
        }
    }

    func prepareOfflineUploadBatches(allowedPaths: Set<String>? = nil) async -> OfflineUploadPreparationResult {
        guard let selectedPolarIdentifier else {
            return OfflineUploadPreparationResult(
                batches: [],
                messagesByStream: [.hr: "failed: no selected device"]
            )
        }

        let entries: [PolarOfflineRecordingEntry]
        do {
            entries = try await withCheckedThrowingContinuation { continuation in
                var listedEntries: [PolarOfflineRecordingEntry] = []
                streamCapabilitiesDisposable?.dispose()
                streamCapabilitiesDisposable = api.listOfflineRecordings(selectedPolarIdentifier)
                    .observe(on: MainScheduler.asyncInstance)
                    .subscribe(
                        onNext: { entry in listedEntries.append(entry) },
                        onError: { error in continuation.resume(throwing: error) },
                        onCompleted: { continuation.resume(returning: listedEntries) }
                    )
            }
        } catch {
            return OfflineUploadPreparationResult(
                batches: [],
                messagesByStream: [.hr: "failed: list recordings: \(error.localizedDescription)"]
            )
        }

        let selectedEntries: [PolarOfflineRecordingEntry]
        if let allowedPaths {
            // Session-targeted upload: use robust path matching (exact + suffix + basename).
            let normalizedAllowed = Set(allowedPaths.map(Self.normalizePath))
            let allowedBasenames = Set(allowedPaths.map { URL(fileURLWithPath: $0).lastPathComponent.lowercased() })
            selectedEntries = entries.filter { entry in
                let entryPath = Self.normalizePath(entry.path)
                if normalizedAllowed.contains(entryPath) { return true }
                if normalizedAllowed.contains(where: { entryPath.hasSuffix($0) || $0.hasSuffix(entryPath) }) { return true }
                let base = URL(fileURLWithPath: entry.path).lastPathComponent.lowercased()
                return allowedBasenames.contains(base)
            }
        } else {
            // Generic upload path: keep nearest-in-time grouping heuristic.
            selectedEntries = Self.selectSessionEntries(entries)
        }
        var batches: [OfflineUploadBatch] = []
        var messagesByStream: [PolarOfflineStream: String] = [:]
        let fetchStartedAt = Date()

        for entry in entries {
            if let allowedPaths, !allowedPaths.contains(entry.path) {
                continue
            }
            guard let offlineStream = Self.offlineStream(from: entry.type) else { continue }
            if !selectedEntries.contains(where: { $0.path == entry.path }) {
                messagesByStream[offlineStream] = "skipped: out-of-session recording group"
                continue
            }
            messagesByStream[offlineStream] = "fetching"
            do {
                let offlineData = try await fetchOfflineRecord(identifier: selectedPolarIdentifier, entry: entry)
                let (stream, samples, message) = Self.makeOfflineSamples(
                    from: offlineData,
                    fallbackType: entry.type,
                    fetchStartedAt: fetchStartedAt
                )
                if !samples.isEmpty {
                    let fetchCompletedAt = Date()
                    let timezoneOffsetMinutes = TimeZone.current.secondsFromGMT(for: fetchCompletedAt) / 60
                    let estimatedEndUTC = Self.estimatedOfflineRecordingEndUTC(
                        stream: stream,
                        startUTC: entry.date,
                        samples: samples
                    )
                    let timeContext = UploadChunkTimeContext(
                        recordingStartUTC: entry.date,
                        recordingEndUTC: estimatedEndUTC,
                        fileCreatedAtDevice: entry.date,
                        fileClosedAtDevice: estimatedEndUTC,
                        deviceLocalTimeAtFetch: fetchStartedAt,
                        deviceTimezoneOffset: timezoneOffsetMinutes,
                        clockSyncState: "unknown",
                        clockDriftEstimate: nil,
                        sourceAppOrigin: "unknown",
                        sensorRecordingID: entry.path,
                        fetchStartedAtCollector: fetchStartedAt,
                        fetchCompletedAtCollector: fetchCompletedAt
                    )
                    batches.append(
                        OfflineUploadBatch(
                            stream: stream,
                            sourcePath: entry.path,
                            samples: samples,
                            timeContext: timeContext
                        )
                    )
                }
                messagesByStream[offlineStream] = message
            } catch {
                messagesByStream[offlineStream] = "failed: \(error.localizedDescription)"
            }
        }

        batches = Self.unifyBatchSessionWindow(batches)
        return OfflineUploadPreparationResult(batches: batches, messagesByStream: messagesByStream)
    }

    private static func selectSessionEntries(_ entries: [PolarOfflineRecordingEntry]) -> [PolarOfflineRecordingEntry] {
        guard entries.count > 1 else { return entries }
        let known = entries.filter { offlineStream(from: $0.type) != nil }
        guard !known.isEmpty else { return entries }

        let anchor = known.compactMap(\.date).max()
        guard let anchor else { return known }

        func distance(_ date: Date?) -> TimeInterval {
            guard let date else { return .greatestFiniteMagnitude }
            return abs(date.timeIntervalSince(anchor))
        }

        var byStream: [PolarOfflineStream: PolarOfflineRecordingEntry] = [:]
        for entry in known {
            guard let stream = offlineStream(from: entry.type) else { continue }
            guard byStream[stream] == nil || distance(entry.date) < distance(byStream[stream]?.date) else { continue }
            byStream[stream] = entry
        }

        let selected = Array(byStream.values)
        // Soft guard: avoid mixing stale historical recordings into a single upload session.
        // Keep entries close to the anchor; if a stream has no close sample, keep best effort pick.
        let closeThresholdSeconds: TimeInterval = 15 * 60
        let close = selected.filter { distance($0.date) <= closeThresholdSeconds }
        if close.count >= 3 {
            return close
        }
        return selected
    }

    private static func normalizePath(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func unifyBatchSessionWindow(_ batches: [OfflineUploadBatch]) -> [OfflineUploadBatch] {
        let contexts = batches.compactMap(\.timeContext)
        guard !contexts.isEmpty else { return batches }
        let starts = contexts.compactMap(\.recordingStartUTC)
        let ends = contexts.compactMap(\.recordingEndUTC)
        guard let sessionStart = starts.min(), let sessionEnd = ends.max(), sessionEnd >= sessionStart else {
            return batches
        }

        return batches.map { batch in
            guard let ctx = batch.timeContext else { return batch }
            let unified = UploadChunkTimeContext(
                recordingStartUTC: sessionStart,
                recordingEndUTC: sessionEnd,
                fileCreatedAtDevice: sessionStart,
                fileClosedAtDevice: sessionEnd,
                deviceLocalTimeAtFetch: ctx.deviceLocalTimeAtFetch,
                deviceTimezoneOffset: ctx.deviceTimezoneOffset,
                clockSyncState: ctx.clockSyncState,
                clockDriftEstimate: ctx.clockDriftEstimate,
                sourceAppOrigin: ctx.sourceAppOrigin,
                sensorRecordingID: ctx.sensorRecordingID,
                fetchStartedAtCollector: ctx.fetchStartedAtCollector,
                fetchCompletedAtCollector: ctx.fetchCompletedAtCollector
            )
            return OfflineUploadBatch(
                stream: batch.stream,
                sourcePath: batch.sourcePath,
                samples: batch.samples,
                timeContext: unified
            )
        }
    }

    private func tryResumeConnectIfReady(forceAfterReadinessTimeout: Bool = false) {
        guard isSelectedDeviceConnected, isSelectedDeviceHrFeatureReady else { return }
        let onlineReady = isSelectedDeviceOnlineStreamingFeatureReady || isSelectedDeviceOnlineStreamingUnavailable
        guard onlineReady else { return }
        let readinessTimedOut = (connectStartedAt.map { Date().timeIntervalSince($0) >= 12 } ?? false)
        guard didReceiveFeaturesReadinessSnapshot || readinessTimedOut || forceAfterReadinessTimeout else {
            return
        }

        if !didReceiveFeaturesReadinessSnapshot && (readinessTimedOut || forceAfterReadinessTimeout) {
            log("Proceeding without features readiness callback after timeout")
        }

        if !capabilityProbeCompleted {
            beginCapabilityProbe()
            return
        }

        if !didRunPostConnectSetup {
            didRunPostConnectSetup = true
            attemptTimeSync()
            pollBatterySnapshot(trigger: "on_connect")
            startBatteryPollingLoop()
        }

        guard let connectContinuation else { return }

        connectionState = .connected
        connectContinuation.resume()
        self.connectContinuation = nil
        connectStartedAt = nil
        log("Connect succeeded")
    }

    private func retryOfflineGattOperation(
        maxAttempts: Int = 3,
        operation: () async throws -> Void
    ) async throws {
        var attempt = 1
        while true {
            do {
                try await operation()
                return
            } catch {
                guard attempt < maxAttempts, Self.isRetryableOfflineGattError(error) else {
                    throw error
                }
                attempt += 1
                await sleepMilliseconds(350)
            }
        }
    }

    private func sleepMilliseconds(_ milliseconds: UInt64) async {
        try? await Task.sleep(nanoseconds: milliseconds * 1_000_000)
    }

    private static func isRetryableOfflineGattError(_ error: Error) -> Bool {
        if let polarError = error as? PolarErrors {
            switch polarError {
            case .unableToStartStreaming, .serviceNotFound, .notificationNotEnabled, .deviceNotConnected:
                return true
            default:
                break
            }
        }
        if let bleError = error as? BleGattException {
            switch bleError {
            case .gattDisconnected, .gattServiceNotFound, .gattCharacteristicNotifyNotEnabled:
                return true
            case let .gattAttributeError(errorCode, _):
                return errorCode == 1 || errorCode == 8 || errorCode == 12
            default:
                break
            }
        }
        let nsError = error as NSError
        return nsError.code == 1 || nsError.code == 8 || nsError.code == 12
    }

    private static func offlineOperationErrorMessage(
        _ error: Error,
        action: String,
        stream: PolarOfflineStream? = nil,
        settings: OfflineStreamSettingsSelection? = nil
    ) -> String {
        let context = [
            stream.map { "stream=\($0.rawValue)" },
            settings.map { "settings=[\($0.summary())]" }
        ]
        .compactMap { $0 }
        .joined(separator: " ")
        let suffix = context.isEmpty ? "" : " (\(context))"
        if let bleError = error as? BleGattException {
            switch bleError {
            case let .gattAttributeError(errorCode, _):
                if errorCode == 1 {
                    return "Failed to \(action): GATT attribute error 1 (likely busy/not ready/already recording).\((suffix))"
                }
                return "Failed to \(action): GATT attribute error \(errorCode).\((suffix))"
            default:
                return "Failed to \(action): \(bleError.localizedDescription)\((suffix))"
            }
        }
        let nsError = error as NSError
        if nsError.code == 1 {
            return "Failed to \(action): GATT error 1 (likely busy/not ready/already recording).\((suffix))"
        }
        return "Failed to \(action): \(error.localizedDescription)\((suffix))"
    }

    private static func mapSettingsOptions(from settings: PolarSensorSetting) -> OfflineStreamSettingsOptions {
        OfflineStreamSettingsOptions(
            sampleRates: settings.settings[.sampleRate]?.sorted() ?? [],
            resolutions: settings.settings[.resolution]?.sorted() ?? [],
            ranges: settings.settings[.range]?.sorted() ?? [],
            channels: settings.settings[.channels]?.sorted() ?? []
        )
    }

    private static func defaultSelection(from settings: PolarSensorSetting) -> OfflineStreamSettingsSelection {
        let maxSettings = settings.maxSettings()
        return OfflineStreamSettingsSelection(
            sampleRate: maxSettings.settings[.sampleRate]?.first,
            resolution: maxSettings.settings[.resolution]?.first,
            range: maxSettings.settings[.range]?.first,
            channels: maxSettings.settings[.channels]?.first
        )
    }

    private static func makePolarSensorSetting(from selection: OfflineStreamSettingsSelection?) -> PolarSensorSetting? {
        guard let selection else { return nil }
        var raw: [PolarSensorSetting.SettingType: UInt32] = [:]
        if let sampleRate = selection.sampleRate { raw[.sampleRate] = sampleRate }
        if let resolution = selection.resolution { raw[.resolution] = resolution }
        if let range = selection.range { raw[.range] = range }
        if let channels = selection.channels { raw[.channels] = channels }
        if raw.isEmpty { return nil }
        return try? PolarSensorSetting(raw)
    }

    private func beginCapabilityProbe() {
        guard let selectedPolarIdentifier else { return }
        guard isSelectedDeviceOnlineStreamingFeatureReady else {
            capabilityProbeCompleted = true
            return
        }
        guard !capabilityProbeInFlight else { return }

        streamCapabilitiesDisposable?.dispose()
        streamCapabilitiesRetryWorkItem?.cancel()
        streamCapabilitiesRetryWorkItem = nil
        capabilityProbeInFlight = true
        capabilityProbeAttempt += 1
        streamCapabilitiesDisposable = api.getAvailableOnlineStreamDataTypes(selectedPolarIdentifier)
            .observe(on: MainScheduler.asyncInstance)
            .subscribe(
                onSuccess: { [weak self] dataTypes in
                    guard let self else { return }
                    self.capabilityProbeInFlight = false
                    self.capabilityProbeCompleted = true
                    self.discoveredOnlineDataTypes = dataTypes
                    let names = dataTypes.map { "\($0)" }.sorted().joined(separator: ",")
                    self.log("Feature readiness (online data types): [\(names)]")
                    if !dataTypes.contains(.ecg) {
                        self.log("ECG stream unavailable for selected device")
                    }
                    if !dataTypes.contains(.acc) {
                        self.log("ACC stream unavailable for selected device")
                    }
                    self.tryResumeConnectIfReady(forceAfterReadinessTimeout: false)
                },
                onFailure: { [weak self] error in
                    guard let self else { return }
                    self.capabilityProbeInFlight = false
                    self.log("Could not query online stream types (attempt \(self.capabilityProbeAttempt)): \(error.localizedDescription)")
                    guard self.capabilityProbeAttempt < 8 else {
                        if self.isLikelyH10 && self.isSelectedDeviceOnlineStreamingFeatureReady {
                            self.discoveredOnlineDataTypes = [.hr, .ecg, .acc]
                            self.capabilityProbeCompleted = true
                            self.log("Capability probe failed; enabling H10 online defaults: [hr,ecg,acc]")
                            self.tryResumeConnectIfReady(forceAfterReadinessTimeout: false)
                            return
                        }
                        self.hrCapabilitiesFallbackDisposable?.dispose()
                        self.hrCapabilitiesFallbackDisposable = self.api.getAvailableHRServiceDataTypes(identifier: selectedPolarIdentifier)
                            .observe(on: MainScheduler.asyncInstance)
                            .subscribe(
                                onSuccess: { [weak self] dataTypes in
                                    self?.discoveredOnlineDataTypes = dataTypes
                                    self?.log("Falling back to HR-only stream capabilities")
                                    self?.capabilityProbeCompleted = true
                                    self?.tryResumeConnectIfReady(forceAfterReadinessTimeout: false)
                                },
                                onFailure: { [weak self] fallbackError in
                                    self?.log("HR capability fallback failed: \(fallbackError.localizedDescription)")
                                    self?.capabilityProbeCompleted = true
                                    self?.tryResumeConnectIfReady(forceAfterReadinessTimeout: false)
                                }
                            )
                        return
                    }
                    let work = DispatchWorkItem { [weak self] in
                        self?.beginCapabilityProbe()
                    }
                    self.streamCapabilitiesRetryWorkItem = work
                    DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(1200), execute: work)
                }
            )
    }

    private func startBatteryPollingLoop() {
        batteryPollingTask?.cancel()
        batteryPollingTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 120_000_000_000)
                guard !Task.isCancelled else { return }
                guard self.connectionState == .connected else { continue }
                self.pollBatterySnapshot(trigger: "periodic_poll")
            }
        }
    }

    private func pollBatterySnapshot(trigger: String) {
        guard let selectedPolarIdentifier else { return }

        guard api.isFeatureReady(selectedPolarIdentifier, feature: .feature_battery_info) else {
            let reason = "battery feature not ready"
            log("Battery unavailable: \(reason)")
            batteryProvider.publishUnavailable(reason: reason, sdkRaw: "trigger=\(trigger)")
            cacheBatteryStatus(
                levelPercent: nil,
                chargeStateRaw: nil,
                source: .unavailable,
                unavailableReason: reason
            )
            return
        }

        var levelPercent: Int?
        var chargeState: String?

        do {
            let rawLevel = try api.getBatteryLevel(identifier: selectedPolarIdentifier)
            if (0...100).contains(rawLevel) {
                levelPercent = rawLevel
                latestBatteryLevelPercent = rawLevel
            }
        } catch {
            log("Battery level poll failed: \(error.localizedDescription)")
        }

        do {
            let rawCharge = try api.getChargerState(identifier: selectedPolarIdentifier)
            chargeState = serialize(chargeState: rawCharge)
            latestChargeState = chargeState
        } catch {
            log("Battery charge-state poll failed: \(error.localizedDescription)")
        }

        let powerSources = latestPowerSources

        if levelPercent == nil, chargeState == nil, powerSources == nil {
            let reason = "no battery values available"
            batteryProvider.publishUnavailable(reason: reason, sdkRaw: "trigger=\(trigger)")
            log("Battery unavailable: \(reason)")
            cacheBatteryStatus(
                levelPercent: nil,
                chargeStateRaw: nil,
                source: .unavailable,
                unavailableReason: reason
            )
            return
        }

        batteryProvider.publishPollSnapshot(
            levelPercent: levelPercent,
            chargeState: chargeState,
            powerSources: powerSources,
            sdkRaw: "trigger=\(trigger)"
        )
        cacheBatteryStatus(
            levelPercent: levelPercent ?? latestBatteryLevelPercent,
            chargeStateRaw: chargeState ?? latestChargeState,
            source: .poll
        )
        log("Battery poll snapshot: level=\(levelPercent.map(String.init) ?? "n/a") charge=\(chargeState ?? "n/a")")
    }

    private func attemptTimeSync() {
        Task { [weak self] in
            _ = await self?.syncDeviceTimeToPhone(mode: .live)
        }
    }

    func readDeviceTime(mode: CollectionMode) async -> DeviceTimeActionResult {
        let context = mode.transportValue
        guard let selectedDevice else {
            return resultUnavailable(message: "Read-back unavailable", detail: "No selected device", context: context, eventType: .deviceTimeRead)
        }
        guard let selectedPolarIdentifier else {
            return resultUnavailable(message: "Read-back unavailable", detail: "No selected Polar identifier", context: context, eventType: .deviceTimeRead, device: selectedDevice)
        }
        guard connectionState == .connected else {
            return resultUnavailable(message: "Read-back unavailable", detail: "Device disconnected", context: context, eventType: .deviceTimeRead, device: selectedDevice)
        }
        guard api.isFeatureReady(selectedPolarIdentifier, feature: .feature_polar_device_time_setup) else {
            return resultUnavailable(message: "Read-back unavailable", detail: "feature_polar_device_time_setup is not ready", context: context, eventType: .deviceTimeRead, device: selectedDevice)
        }

        do {
            let (deviceDate, deviceZone) = try await getLocalTimeWithZone(identifier: selectedPolarIdentifier)
            let event = makeOperationalEvent(
                eventType: .deviceTimeRead,
                device: selectedDevice,
                context: context,
                requestedLocalTime: nil,
                requestedTimeZone: nil,
                readbackDate: deviceDate,
                readbackZone: deviceZone,
                delta: nil,
                result: .success,
                detail: "getLocalTimeWithZone success"
            )
            return DeviceTimeActionResult(
                state: .success,
                message: "Device time synced",
                debugDetails: "Stream timestamp verification not performed",
                readbackDeviceTime: deviceDate,
                readbackTimeZoneID: deviceZone.identifier,
                verificationDeltaSeconds: nil,
                operationalEvents: [event]
            )
        } catch {
            return resultUnavailable(
                message: "Read-back unavailable",
                detail: "getLocalTimeWithZone failed: \(error.localizedDescription)",
                context: context,
                eventType: .deviceTimeRead,
                device: selectedDevice
            )
        }
    }

    func syncDeviceTimeToPhone(mode: CollectionMode) async -> DeviceTimeActionResult {
        let context = mode.transportValue
        guard let selectedDevice else {
            return resultUnavailable(message: "Read-back unavailable", detail: "No selected device", context: context, eventType: .deviceTimeSet)
        }
        guard let selectedPolarIdentifier else {
            return resultUnavailable(message: "Read-back unavailable", detail: "No selected Polar identifier", context: context, eventType: .deviceTimeSet, device: selectedDevice)
        }
        guard connectionState == .connected else {
            return resultUnavailable(message: "Read-back unavailable", detail: "Device disconnected", context: context, eventType: .deviceTimeSet, device: selectedDevice)
        }
        guard api.isFeatureReady(selectedPolarIdentifier, feature: .feature_polar_device_time_setup) else {
            return resultUnavailable(message: "Read-back unavailable", detail: "feature_polar_device_time_setup is not ready", context: context, eventType: .deviceTimeSet, device: selectedDevice)
        }

        let requestedDate = Date()
        let requestedZone = TimeZone.current
        var events: [DeviceTimeOperationalEvent] = []

        do {
            try await setLocalTime(identifier: selectedPolarIdentifier, date: requestedDate, zone: requestedZone)
            events.append(
                makeOperationalEvent(
                    eventType: .deviceTimeSet,
                    device: selectedDevice,
                    context: context,
                    requestedLocalTime: requestedDate,
                    requestedTimeZone: requestedZone,
                    readbackDate: nil,
                    readbackZone: nil,
                    delta: nil,
                    result: .success,
                    detail: "setLocalTime success"
                )
            )
        } catch {
            events.append(
                makeOperationalEvent(
                    eventType: .deviceTimeSet,
                    device: selectedDevice,
                    context: context,
                    requestedLocalTime: requestedDate,
                    requestedTimeZone: requestedZone,
                    readbackDate: nil,
                    readbackZone: nil,
                    delta: nil,
                    result: .failed,
                    detail: "setLocalTime failed: \(error.localizedDescription)"
                )
            )
            return DeviceTimeActionResult(
                state: .failed,
                message: "Time sync failed",
                debugDetails: "setLocalTime failed: \(error.localizedDescription)",
                readbackDeviceTime: nil,
                readbackTimeZoneID: nil,
                verificationDeltaSeconds: nil,
                operationalEvents: events
            )
        }

        do {
            let (readbackDate, readbackZone) = try await getLocalTimeWithZone(identifier: selectedPolarIdentifier)
            let delta = abs(readbackDate.timeIntervalSince(Date()))
            events.append(
                makeOperationalEvent(
                    eventType: .deviceTimeRead,
                    device: selectedDevice,
                    context: context,
                    requestedLocalTime: requestedDate,
                    requestedTimeZone: requestedZone,
                    readbackDate: readbackDate,
                    readbackZone: readbackZone,
                    delta: nil,
                    result: .success,
                    detail: "getLocalTimeWithZone after set success"
                )
            )
            events.append(
                makeOperationalEvent(
                    eventType: .deviceTimeVerification,
                    device: selectedDevice,
                    context: context,
                    requestedLocalTime: requestedDate,
                    requestedTimeZone: requestedZone,
                    readbackDate: readbackDate,
                    readbackZone: readbackZone,
                    delta: delta,
                    result: .success,
                    detail: "Read-back verification complete"
                )
            )
            return DeviceTimeActionResult(
                state: .success,
                message: "Device time synced",
                debugDetails: "Stream timestamp verification not performed",
                readbackDeviceTime: readbackDate,
                readbackTimeZoneID: readbackZone.identifier,
                verificationDeltaSeconds: delta,
                operationalEvents: events
            )
        } catch {
            events.append(
                makeOperationalEvent(
                    eventType: .deviceTimeVerification,
                    device: selectedDevice,
                    context: context,
                    requestedLocalTime: requestedDate,
                    requestedTimeZone: requestedZone,
                    readbackDate: nil,
                    readbackZone: nil,
                    delta: nil,
                    result: .unavailable,
                    detail: "Read-back unavailable: \(error.localizedDescription)"
                )
            )
            return DeviceTimeActionResult(
                state: .unavailable,
                message: "Read-back unavailable",
                debugDetails: "setLocalTime succeeded, read-back unavailable: \(error.localizedDescription)",
                readbackDeviceTime: nil,
                readbackTimeZoneID: nil,
                verificationDeltaSeconds: nil,
                operationalEvents: events
            )
        }
    }

    func prepareDeviceTimeForOfflineSync() async -> DeviceTimeActionResult {
        await syncDeviceTimeToPhone(mode: .offlineRecording)
    }

    private func setLocalTime(identifier: String, date: Date, zone: TimeZone) async throws {
        try await withCheckedThrowingContinuation { continuation in
            timeSetupDisposable?.dispose()
            timeSetupDisposable = api.setLocalTime(identifier, time: date, zone: zone)
                .observe(on: MainScheduler.asyncInstance)
                .subscribe(
                    onCompleted: {
                        continuation.resume()
                    },
                    onError: { error in
                        continuation.resume(throwing: error)
                    }
                )
        }
    }

    private func getLocalTimeWithZone(identifier: String) async throws -> (Date, TimeZone) {
        try await withCheckedThrowingContinuation { continuation in
            timeReadbackDisposable?.dispose()
            timeReadbackDisposable = api.getLocalTimeWithZone(identifier)
                .observe(on: MainScheduler.asyncInstance)
                .subscribe(
                    onSuccess: { date, zone in
                        continuation.resume(returning: (date, zone))
                    },
                    onFailure: { error in
                        continuation.resume(throwing: error)
                    }
                )
        }
    }

    private func makeOperationalEvent(
        eventType: DeviceTimeOperationalEventType,
        device: CollectorDevice,
        context: String,
        requestedLocalTime: Date?,
        requestedTimeZone: TimeZone?,
        readbackDate: Date?,
        readbackZone: TimeZone?,
        delta: TimeInterval?,
        result: DeviceTimeOperationResult,
        detail: String
    ) -> DeviceTimeOperationalEvent {
        DeviceTimeOperationalEvent(
            eventType: eventType,
            vendor: device.vendor,
            model: device.model,
            deviceID: device.id,
            collectionModeContext: context,
            requestedLocalTime: requestedLocalTime,
            requestedTimeZoneID: requestedTimeZone?.identifier,
            deviceReadbackLocalTime: readbackDate,
            deviceReadbackTimeZoneID: readbackZone?.identifier,
            deltaSeconds: delta,
            result: result,
            collectorTimestamp: Date(),
            detail: detail
        )
    }

    private func resultUnavailable(
        message: String,
        detail: String,
        context: String,
        eventType: DeviceTimeOperationalEventType,
        device: CollectorDevice? = nil
    ) -> DeviceTimeActionResult {
        var events: [DeviceTimeOperationalEvent] = []
        if let device {
            events.append(
                makeOperationalEvent(
                    eventType: eventType,
                    device: device,
                    context: context,
                    requestedLocalTime: nil,
                    requestedTimeZone: nil,
                    readbackDate: nil,
                    readbackZone: nil,
                    delta: nil,
                    result: .unavailable,
                    detail: detail
                )
            )
        }
        return DeviceTimeActionResult(
            state: .unavailable,
            message: message,
            debugDetails: detail,
            readbackDeviceTime: nil,
            readbackTimeZoneID: nil,
            verificationDeltaSeconds: nil,
            operationalEvents: events
        )
    }

    private func resolveModel(from deviceName: String) -> String {
        let lowered = deviceName.lowercased()
        if lowered.contains("h10") {
            return "H10"
        }

        let trimmed = deviceName
            .replacingOccurrences(of: "Polar", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Unknown" : trimmed
    }

    private func dataType(for stream: PolarOfflineStream) -> PolarDeviceDataType {
        switch stream {
        case .hr: return .hr
        case .ppi: return .ppi
        case .acc: return .acc
        case .ppg: return .ppg
        case .mag: return .magnetometer
        case .gyro: return .gyro
        }
    }

    private static func offlineStream(from type: PolarDeviceDataType) -> PolarOfflineStream? {
        switch type {
        case .hr: return .hr
        case .ppi: return .ppi
        case .acc: return .acc
        case .ppg: return .ppg
        case .magnetometer: return .mag
        case .gyro: return .gyro
        default: return nil
        }
    }

    private func fetchOfflineRecord(
        identifier: String,
        entry: PolarOfflineRecordingEntry
    ) async throws -> PolarOfflineRecordingData {
        try await withCheckedThrowingContinuation { continuation in
            timeReadbackDisposable?.dispose()
            timeReadbackDisposable = api.getOfflineRecord(
                identifier,
                entry: entry,
                secret: nil
            )
            .observe(on: MainScheduler.asyncInstance)
            .subscribe(
                onSuccess: { data in continuation.resume(returning: data) },
                onFailure: { error in continuation.resume(throwing: error) }
            )
        }
    }

    private static func makeAccSamples(
        from data: PolarAccData,
        collectorTimestamp: Date,
        settings: PolarSensorSetting
    ) -> [HeartRateSample] {
        let sampleRate = settings.settings[.sampleRate]?.first.map { UInt32($0) }
        let range = settings.settings[.range]?.first.map { UInt32($0) }
        let streamSettings = mapStreamSettings(from: settings)

        return data.enumerated().map { index, sample in
            return HeartRateSample(
                stream: .accelerometer,
                collectorReceivedAtUTC: collectorTimestamp,
                deviceTimestampRaw: nil,
                sourceTimestampKind: .deviceReported,
                sampleSequenceNumber: index + 1,
                payload: .acc(
                    PolarAccSampleData(
                        deviceTimeNS: sample.timeStamp,
                        xMg: sample.x,
                        yMg: sample.y,
                        zMg: sample.z,
                        sampleRateHz: sampleRate,
                        rangeMg: range
                    )
                ),
                streamSettings: streamSettings
            )
        }
    }

    private static func makeHrSamples(
        from data: PolarHrData,
        collectorTimestamp: Date
    ) -> [HeartRateSample] {
        data.enumerated().map { index, sample in
            return HeartRateSample(
                stream: .heartRate,
                collectorReceivedAtUTC: collectorTimestamp,
                deviceTimestampRaw: nil,
                sourceTimestampKind: .deviceReported,
                sampleSequenceNumber: index + 1,
                payload: .hr(
                    PolarHrStreamData(
                        hr: Int(sample.hr),
                        ppgQuality: Int(sample.ppgQuality),
                        correctedHr: Int(sample.correctedHr),
                        rrsMs: sample.rrsMs,
                        rrAvailable: sample.rrAvailable,
                        contactStatus: sample.contactStatus,
                        contactStatusSupported: sample.contactStatusSupported
                    )
                ),
                streamSettings: nil
            )
        }
    }

    private static func makePpiSamples(from data: PolarPpiData, collectorTimestamp: Date) -> [HeartRateSample] {
        data.samples.enumerated().map { index, sample in
            HeartRateSample(
                stream: .ppi,
                collectorReceivedAtUTC: collectorTimestamp,
                deviceTimestampRaw: nil,
                sourceTimestampKind: .deviceReported,
                sampleSequenceNumber: index + 1,
                payload: .ppi(
                    PolarPpiSampleData(
                        timeStamp: sample.timeStamp,
                        hr: sample.hr,
                        ppiMs: sample.ppInMs,
                        errorEstimateMs: sample.ppErrorEstimate,
                        blockerBit: sample.blockerBit,
                        skinContactStatus: sample.skinContactStatus,
                        skinContactSupported: sample.skinContactSupported
                    )
                ),
                streamSettings: nil
            )
        }
    }

    private static func makePpgSamples(from data: PolarPpgData, collectorTimestamp: Date, settings: PolarSensorSetting) -> [HeartRateSample] {
        let streamSettings = mapStreamSettings(from: settings)
        return data.samples.enumerated().map { index, sample in
            let channels = sample.channelSamples
            return HeartRateSample(
                stream: .ppg,
                collectorReceivedAtUTC: collectorTimestamp,
                deviceTimestampRaw: nil,
                sourceTimestampKind: .deviceReported,
                sampleSequenceNumber: index + 1,
                payload: .ppg(
                    PolarPpgSampleData(
                        deviceTimeNS: sample.timeStamp,
                        ppg0: channels.indices.contains(0) ? channels[0] : nil,
                        ppg1: channels.indices.contains(1) ? channels[1] : nil,
                        ppg2: channels.indices.contains(2) ? channels[2] : nil,
                        ambient: channels.indices.contains(3) ? channels[3] : nil,
                        channelSamples: channels
                    )
                ),
                streamSettings: streamSettings
            )
        }
    }

    private static func makeMagSamples(from data: PolarMagnetometerData, collectorTimestamp: Date, settings: PolarSensorSetting) -> [HeartRateSample] {
        let streamSettings = mapStreamSettings(from: settings)
        return data.enumerated().map { index, sample in
            HeartRateSample(
                stream: .magnetometer,
                collectorReceivedAtUTC: collectorTimestamp,
                deviceTimestampRaw: nil,
                sourceTimestampKind: .deviceReported,
                sampleSequenceNumber: index + 1,
                payload: .mag(
                    PolarMagSampleData(deviceTimeNS: sample.timeStamp, xGauss: sample.x, yGauss: sample.y, zGauss: sample.z)
                ),
                streamSettings: streamSettings
            )
        }
    }

    private static func makeGyroSamples(from data: PolarGyroData, collectorTimestamp: Date, settings: PolarSensorSetting) -> [HeartRateSample] {
        let streamSettings = mapStreamSettings(from: settings)
        return data.enumerated().map { index, sample in
            HeartRateSample(
                stream: .gyroscope,
                collectorReceivedAtUTC: collectorTimestamp,
                deviceTimestampRaw: nil,
                sourceTimestampKind: .deviceReported,
                sampleSequenceNumber: index + 1,
                payload: .gyro(
                    PolarGyroSampleData(deviceTimeNS: sample.timeStamp, xDps: sample.x, yDps: sample.y, zDps: sample.z)
                ),
                streamSettings: streamSettings
            )
        }
    }

    private static func makeOfflineSamples(
        from offlineData: PolarOfflineRecordingData,
        fallbackType: PolarDeviceDataType,
        fetchStartedAt: Date
    ) -> (CollectorStream, [HeartRateSample], String) {
        switch offlineData {
        case .hrOfflineRecordingData(let hrData, _):
            let samples = makeHrSamples(from: hrData, collectorTimestamp: fetchStartedAt)
            return (.heartRate, samples, samples.isEmpty ? "skipped: no samples" : "uploaded-ready: \(samples.count)")
        case .ppiOfflineRecordingData(let ppiData, _):
            let samples = makePpiSamples(from: ppiData, collectorTimestamp: fetchStartedAt)
            return (.ppi, samples, samples.isEmpty ? "skipped: no samples" : "uploaded-ready: \(samples.count)")
        case .accOfflineRecordingData(let accData, _, let settings):
            let samples = makeAccSamples(from: accData, collectorTimestamp: fetchStartedAt, settings: settings)
            return (.accelerometer, samples, samples.isEmpty ? "skipped: no samples" : "uploaded-ready: \(samples.count)")
        case .ppgOfflineRecordingData(let ppgData, _, let settings):
            let samples = makePpgSamples(from: ppgData, collectorTimestamp: fetchStartedAt, settings: settings)
            return (.ppg, samples, samples.isEmpty ? "skipped: no samples" : "uploaded-ready: \(samples.count)")
        case .magOfflineRecordingData(let magData, _, let settings):
            let samples = makeMagSamples(from: magData, collectorTimestamp: fetchStartedAt, settings: settings)
            return (.magnetometer, samples, samples.isEmpty ? "skipped: no samples" : "uploaded-ready: \(samples.count)")
        case .gyroOfflineRecordingData(let gyrData, _, let settings):
            let samples = makeGyroSamples(from: gyrData, collectorTimestamp: fetchStartedAt, settings: settings)
            return (.gyroscope, samples, samples.isEmpty ? "skipped: no samples" : "uploaded-ready: \(samples.count)")
        default:
            let stream: CollectorStream = {
                switch fallbackType {
                case .hr: return .heartRate
                case .ppi: return .ppi
                case .acc: return .accelerometer
                case .ppg: return .ppg
                case .magnetometer: return .magnetometer
                case .gyro: return .gyroscope
                default: return .heartRate
                }
            }()
            return (stream, [], "skipped: unsupported payload")
        }
    }

    private static func estimatedOfflineRecordingEndUTC(
        stream: CollectorStream,
        startUTC: Date?,
        samples: [HeartRateSample]
    ) -> Date? {
        guard let startUTC else { return nil }
        guard samples.count > 1 else { return startUTC }

        switch stream {
        case .heartRate:
            return startUTC.addingTimeInterval(Double(samples.count - 1))
        case .ppi:
            var totalSeconds: TimeInterval = 0
            for sample in samples.dropLast() {
                guard case .ppi(let ppiData) = sample.payload else {
                    totalSeconds += 1
                    continue
                }
                if ppiData.ppiMs > 0 {
                    totalSeconds += TimeInterval(ppiData.ppiMs) / 1000.0
                } else {
                    totalSeconds += 1
                }
            }
            return startUTC.addingTimeInterval(totalSeconds)
        default:
            let timestamps = samples.compactMap { $0.deviceTimeNS }.sorted()
            guard let first = timestamps.first, let last = timestamps.last, last >= first else {
                return nil
            }
            let deltaNs = last - first
            return startUTC.addingTimeInterval(TimeInterval(deltaNs) / 1_000_000_000.0)
        }
    }

    private static func mapStreamSettings(from settings: PolarSensorSetting) -> [String: StreamSettingValue] {
        var mapped: [String: StreamSettingValue] = [:]
        for (key, values) in settings.settings {
            mapped[String(describing: key)] = .array(values.map { .number(Double($0)) })
        }
        return mapped
    }

    private func resetBatteryState() {
        latestBatteryLevelPercent = nil
        latestChargeState = nil
        latestPowerSources = nil
    }

    private func cacheBatteryStatus(
        levelPercent: Int?,
        chargeStateRaw: String?,
        source: BatteryStatusSource?,
        unavailableReason: String? = nil
    ) {
        guard let selectedPolarIdentifier else { return }
        let updatedAt = Date()
        let battery = BatteryStatus(
            levelPercent: levelPercent,
            chargeState: BatteryChargeState(rawOrNil: chargeStateRaw),
            lastUpdatedAt: updatedAt,
            source: source,
            unavailableReason: unavailableReason
        )
        cachedStatusByDeviceID[selectedPolarIdentifier] = DeviceStatusSnapshot(
            deviceID: selectedPolarIdentifier,
            status: DeviceStatus(battery: battery),
            updatedAt: updatedAt
        )
    }

    private func serialize(chargeState: BleBasClient.ChargeState) -> String {
        switch chargeState {
        case .charging:
            return "charging"
        case .dischargingActive:
            return "discharging_active"
        case .dischargingInactive:
            return "discharging_inactive"
        case .unknown:
            return "unknown"
        }
    }

    private func serialize(powerSourcesState: BleBasClient.PowerSourcesState) -> [String] {
        var values: [String] = []

        switch powerSourcesState.batteryPresent {
        case .present:
            values.append("battery_present")
        case .notPresent:
            values.append("battery_not_present")
        case .unknown:
            values.append("battery_presence_unknown")
        }

        switch powerSourcesState.wiredExternalPowerConnected {
        case .connected:
            values.append("wired_connected")
        case .notConnected:
            values.append("wired_not_connected")
        case .reservedForFutureUse:
            values.append("wired_reserved")
        case .unknown:
            values.append("wired_unknown")
        }

        switch powerSourcesState.wirelessExternalPowerConnected {
        case .connected:
            values.append("wireless_connected")
        case .notConnected:
            values.append("wireless_not_connected")
        case .reservedForFutureUse:
            values.append("wireless_reserved")
        case .unknown:
            values.append("wireless_unknown")
        }

        return values
    }

    private func log(_ message: String) {
        print("[polar-adapter] \(message)")
    }
}

extension PolarDeviceAdapter: PolarBleApiObserver {
    func deviceConnecting(_ identifier: PolarDeviceInfo) {
        guard identifier.deviceId == selectedPolarIdentifier else { return }
        connectionState = .connecting
        log("BLE connecting: \(identifier.deviceId)")
    }

    func deviceConnected(_ identifier: PolarDeviceInfo) {
        guard identifier.deviceId == selectedPolarIdentifier else { return }

        selectedDevice = CollectorDevice(
            id: identifier.deviceId,
            name: identifier.name,
            vendor: "Polar",
            model: resolveModel(from: identifier.name)
        )

        isSelectedDeviceConnected = true
        log("BLE connected: \(identifier.deviceId)")
        tryResumeConnectIfReady()
    }

    func deviceDisconnected(_ identifier: PolarDeviceInfo, pairingError: Bool) {
        guard identifier.deviceId == selectedPolarIdentifier else { return }

        isSelectedDeviceConnected = false
        isSelectedDeviceHrFeatureReady = false
        isSelectedDeviceOnlineStreamingFeatureReady = false
        isSelectedDeviceOnlineStreamingUnavailable = false
        didRunPostConnectSetup = false
        capabilityProbeInFlight = false
        capabilityProbeCompleted = false
        capabilityProbeAttempt = 0
        connectStartedAt = nil
        didReceiveFeaturesReadinessSnapshot = false
        lastKnownTimeFeatureUnavailable = false
        connectionState = .deviceSelected

        batteryPollingTask?.cancel()
        batteryPollingTask = nil

        log("BLE disconnected: \(identifier.deviceId), pairingError: \(pairingError)")

        if let connectContinuation {
            connectContinuation.resume(throwing: PolarAdapterError.connectionInterrupted)
            self.connectContinuation = nil
        }
    }
}

extension PolarDeviceAdapter: PolarBleApiPowerStateObserver {
    func blePowerOn() {
        isBluetoothOn = true
        log("Bluetooth power on")
    }

    func blePowerOff() {
        isBluetoothOn = false
        log("Bluetooth power off")
    }
}

extension PolarDeviceAdapter: PolarBleApiDeviceFeaturesObserver {
    func bleSdkFeatureReady(_ identifier: String, feature: PolarBleSdkFeature) {
        guard identifier == selectedPolarIdentifier else { return }

        switch feature {
        case .feature_hr:
            isSelectedDeviceHrFeatureReady = true
            log("Feature ready: hr")
            tryResumeConnectIfReady(forceAfterReadinessTimeout: false)
        case .feature_polar_online_streaming:
            isSelectedDeviceOnlineStreamingFeatureReady = true
            log("Feature ready: polar_online_streaming")
            tryResumeConnectIfReady(forceAfterReadinessTimeout: false)
        case .feature_battery_info:
            log("Feature ready: battery_info")
            pollBatterySnapshot(trigger: "feature_ready")
        case .feature_polar_device_time_setup:
            log("Feature ready: polar_device_time_setup")
        default:
            break
        }
    }

    func bleSdkFeaturesReadiness(_ identifier: String, ready: [PolarBleSdkFeature], unavailable: [PolarBleSdkFeature]) {
        guard identifier == selectedPolarIdentifier else { return }
        didReceiveFeaturesReadinessSnapshot = true
        log("Features readiness callback: ready=\(ready) unavailable=\(unavailable)")

        if ready.contains(.feature_polar_online_streaming) {
            isSelectedDeviceOnlineStreamingFeatureReady = true
        }
        if unavailable.contains(.feature_polar_online_streaming) {
            isSelectedDeviceOnlineStreamingUnavailable = true
        }
        if unavailable.contains(.feature_polar_device_time_setup) {
            lastKnownTimeFeatureUnavailable = true
        }
        if ready.contains(.feature_polar_device_time_setup) {
            lastKnownTimeFeatureUnavailable = false
        }
        tryResumeConnectIfReady(forceAfterReadinessTimeout: false)

        if unavailable.contains(.feature_battery_info) {
            batteryProvider.publishUnavailable(reason: "battery feature unavailable")
            cacheBatteryStatus(
                levelPercent: nil,
                chargeStateRaw: nil,
                source: .unavailable,
                unavailableReason: "battery feature unavailable"
            )
            log("Battery feature unavailable for selected device")
        }
    }
}

extension PolarDeviceAdapter: PolarBleApiDeviceInfoObserver {
    func batteryLevelReceived(_ identifier: String, batteryLevel: UInt) {
        guard identifier == selectedPolarIdentifier else { return }

        let level = Int(batteryLevel)
        latestBatteryLevelPercent = level

        batteryProvider.publishCallbackUpdate(
            levelPercent: level,
            chargeState: latestChargeState,
            powerSources: latestPowerSources,
            sdkRaw: "battery_level_callback"
        )
        cacheBatteryStatus(
            levelPercent: level,
            chargeStateRaw: latestChargeState,
            source: .callback
        )
        log("Battery callback level=\(level)")
    }

    func batteryChargingStatusReceived(_ identifier: String, chargingStatus: BleBasClient.ChargeState) {
        guard identifier == selectedPolarIdentifier else { return }

        let chargeState = serialize(chargeState: chargingStatus)
        latestChargeState = chargeState

        batteryProvider.publishCallbackUpdate(
            levelPercent: latestBatteryLevelPercent,
            chargeState: chargeState,
            powerSources: latestPowerSources,
            sdkRaw: "battery_charge_state_callback"
        )
        cacheBatteryStatus(
            levelPercent: latestBatteryLevelPercent,
            chargeStateRaw: chargeState,
            source: .callback
        )
        log("Battery callback charge_state=\(chargeState)")
    }

    func batteryPowerSourcesStateReceived(_ identifier: String, powerSourcesState: BleBasClient.PowerSourcesState) {
        guard identifier == selectedPolarIdentifier else { return }

        let powerSources = serialize(powerSourcesState: powerSourcesState)
        latestPowerSources = powerSources

        batteryProvider.publishCallbackUpdate(
            levelPercent: latestBatteryLevelPercent,
            chargeState: latestChargeState,
            powerSources: powerSources,
            sdkRaw: "battery_power_sources_callback"
        )
        cacheBatteryStatus(
            levelPercent: latestBatteryLevelPercent,
            chargeStateRaw: latestChargeState,
            source: .callback
        )
        log("Battery callback power_sources=\(powerSources.joined(separator: ","))")
    }

    func disInformationReceived(_ identifier: String, uuid: CBUUID, value: String) {}

    func disInformationReceivedWithKeysAsStrings(_ identifier: String, key: String, value: String) {}
}
#else
enum PolarAdapterError: LocalizedError {
    case unsupportedEnvironment

    var errorDescription: String? {
        switch self {
        case .unsupportedEnvironment:
            return "Polar BLE SDK is unavailable"
        }
    }
}

final class PolarDeviceAdapter: CollectorDeviceAdapter {
    private(set) var connectionState: ConnectionState = .disconnected
    let sourceIdentifier: String = "polar"
    let deviceSelectionActionTitle: String = "Scan Polar Devices"

    let deviceIdentity: CollectorDevice = CollectorDevice(
        id: "polar-unavailable",
        name: "Polar Device",
        vendor: "Polar",
        model: "Unavailable"
    )

    let availableStreams: [CollectorStream] = [.heartRate, .ecg, .accelerometer, .battery]
    let deviceStatusCapabilities: [DeviceStatusCapability] = [
        DeviceStatusCapability(
            kind: .battery,
            isSupported: false,
            supportsCallbacks: false,
            supportsPolling: false,
            requiresConnection: true
        )
    ]

    func scanDevices() async throws -> [CollectorDevice] {
        throw PolarAdapterError.unsupportedEnvironment
    }

    func scanDevices(onDiscovered: @escaping @Sendable ([CollectorDevice]) -> Void) async throws -> [CollectorDevice] {
        let devices = try await scanDevices()
        onDiscovered(devices)
        return devices
    }

    func selectDevice(_ device: CollectorDevice) throws {
        throw PolarAdapterError.unsupportedEnvironment
    }

    func connect() async throws {
        throw PolarAdapterError.unsupportedEnvironment
    }

    func disconnect() {
        connectionState = .disconnected
    }

    func streamProviders() -> [HeartRateStreamProviding] {
        []
    }

    func heartRateStreamProvider() -> HeartRateStreamProviding? {
        nil
    }

    func cachedDeviceStatusSnapshot(for deviceID: String) -> DeviceStatusSnapshot? {
        nil
    }
}
#endif
#endif
