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

    func scanDevices() async throws -> [CollectorDevice] {
        throw PolarAdapterError.unsupportedEnvironment
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

    private var isLikelyH10: Bool {
        let name = selectedDevice?.name.lowercased() ?? ""
        let model = selectedDevice?.model.lowercased() ?? ""
        return name.contains("h10") || model.contains("h10")
    }

    private var shouldEnableEcgStream: Bool {
        discoveredOnlineDataTypes.contains(.ecg)
            || (isLikelyH10 && isSelectedDeviceOnlineStreamingFeatureReady)
    }

    private var shouldEnableAccStream: Bool {
        discoveredOnlineDataTypes.contains(.acc)
            || (isLikelyH10 && isSelectedDeviceOnlineStreamingFeatureReady)
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
                        self?.discoveredDeviceMap[info.deviceId] = info
                        self?.log("Device discovered: \(info.deviceId) (\(info.name))")
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
        connectContinuation = nil
        connectionState = selectedDevice == nil ? .disconnected : .deviceSelected
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
            return
        }

        batteryProvider.publishPollSnapshot(
            levelPercent: levelPercent,
            chargeState: chargeState,
            powerSources: powerSources,
            sdkRaw: "trigger=\(trigger)"
        )
        log("Battery poll snapshot: level=\(levelPercent.map(String.init) ?? "n/a") charge=\(chargeState ?? "n/a")")
    }

    private func attemptTimeSync() {
        guard let selectedPolarIdentifier else { return }

        guard api.isFeatureReady(selectedPolarIdentifier, feature: .feature_polar_device_time_setup) else {
            log("Time sync skipped: feature not ready")
            return
        }

        log("Time sync attempt started")

        timeSetupDisposable?.dispose()
        timeSetupDisposable = api.setLocalTime(selectedPolarIdentifier, time: Date(), zone: TimeZone.current)
            .observe(on: MainScheduler.asyncInstance)
            .subscribe(
                onCompleted: { [weak self] in
                    self?.log("Time sync setLocalTime succeeded")
                    self?.verifyDeviceTimeReadback()
                },
                onError: { [weak self] error in
                    self?.log("Time sync failed: \(error.localizedDescription)")
                }
            )
    }

    private func verifyDeviceTimeReadback() {
        guard let selectedPolarIdentifier else { return }

        timeReadbackDisposable?.dispose()
        timeReadbackDisposable = api.getLocalTimeWithZone(selectedPolarIdentifier)
            .observe(on: MainScheduler.asyncInstance)
            .subscribe(
                onSuccess: { [weak self] deviceDate, deviceZone in
                    self?.log("Time sync readback succeeded: date=\(deviceDate) zone=\(deviceZone.identifier)")
                },
                onFailure: { [weak self] error in
                    self?.log("Time sync readback unavailable: \(error.localizedDescription)")
                }
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

    private func resetBatteryState() {
        latestBatteryLevelPercent = nil
        latestChargeState = nil
        latestPowerSources = nil
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
        tryResumeConnectIfReady(forceAfterReadinessTimeout: false)

        if unavailable.contains(.feature_battery_info) {
            batteryProvider.publishUnavailable(reason: "battery feature unavailable")
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

    func scanDevices() async throws -> [CollectorDevice] {
        throw PolarAdapterError.unsupportedEnvironment
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
}
#endif
#endif
