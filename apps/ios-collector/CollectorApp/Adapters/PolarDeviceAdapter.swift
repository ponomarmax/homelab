import Foundation

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

    let deviceIdentity: CollectorDevice = CollectorDevice(
        id: "polar-unavailable",
        name: "Polar Device",
        vendor: "Polar",
        model: "Unavailable"
    )

    let availableStreams: [CollectorStream] = [.heartRate]

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

    var deviceIdentity: CollectorDevice {
        selectedDevice ?? CollectorDevice(
            id: "polar-unknown",
            name: "Polar Device",
            vendor: "Polar",
            model: "Unknown"
        )
    }

    let availableStreams: [CollectorStream] = [.heartRate]

    private var api: PolarBleApi
    private let scanTimeoutSeconds: Int
    private let scanNamePrefix: String?

    private var selectedDevice: CollectorDevice?
    private var selectedPolarIdentifier: String?
    private var discoveredDeviceMap: [String: PolarDeviceInfo] = [:]
    private var hrProvider: PolarHrStreamProvider

    private var scanDisposable: Disposable?
    private var connectContinuation: CheckedContinuation<Void, Error>?
    private var isBluetoothOn = true
    private var isSelectedDeviceConnected = false
    private var isSelectedDeviceHrFeatureReady = false

    init(
        scanTimeoutSeconds: Int = 8,
        scanNamePrefix: String? = "Polar"
    ) {
        let api = PolarBleApiDefaultImpl.polarImplementation(
            DispatchQueue.main,
            features: [.feature_hr]
        )

        self.api = api
        self.scanTimeoutSeconds = scanTimeoutSeconds
        self.scanNamePrefix = scanNamePrefix
        self.hrProvider = PolarHrStreamProvider(api: api)

        super.init()

        self.hrProvider = PolarHrStreamProvider(
            api: self.api,
            deviceIDProvider: { [weak self] in self?.selectedPolarIdentifier }
        )
        self.api.observer = self
        self.api.powerStateObserver = self
        self.api.deviceFeaturesObserver = self
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

            scanDisposable = scanStream
                .observe(on: MainScheduler.instance)
                .subscribe(
                    onNext: { [weak self] info in
                        self?.discoveredDeviceMap[info.deviceId] = info
                    },
                    onError: { [weak self] error in
                        self?.scanDisposable = nil
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
    }

    func connect() async throws {
        guard isBluetoothOn else {
            throw PolarAdapterError.bluetoothPoweredOff
        }
        guard let selectedPolarIdentifier else {
            throw PolarAdapterError.noDeviceSelected
        }

        connectionState = .connecting
        isSelectedDeviceConnected = false
        isSelectedDeviceHrFeatureReady = api.isFeatureReady(selectedPolarIdentifier, feature: .feature_hr)

        try await withCheckedThrowingContinuation { continuation in
            connectContinuation = continuation

            do {
                try api.connectToDevice(selectedPolarIdentifier)
                tryResumeConnectIfReady()
            } catch {
                connectContinuation = nil
                connectionState = .deviceSelected
                continuation.resume(throwing: error)
            }
        }
    }

    func disconnect() {
        hrProvider.stop()

        if let selectedPolarIdentifier {
            try? api.disconnectFromDevice(selectedPolarIdentifier)
        }

        isSelectedDeviceConnected = false
        isSelectedDeviceHrFeatureReady = false
        connectContinuation = nil
        connectionState = selectedDevice == nil ? .disconnected : .deviceSelected
    }

    func heartRateStreamProvider() -> HeartRateStreamProviding? {
        hrProvider
    }

    private func tryResumeConnectIfReady() {
        guard isSelectedDeviceConnected, isSelectedDeviceHrFeatureReady else { return }
        guard let connectContinuation else { return }

        connectionState = .connected
        connectContinuation.resume()
        self.connectContinuation = nil
    }

    private func resolveModel(from deviceName: String) -> String {
        let trimmed = deviceName
            .replacingOccurrences(of: "Polar", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Unknown" : trimmed
    }
}

extension PolarDeviceAdapter: PolarBleApiObserver {
    func deviceConnecting(_ identifier: PolarDeviceInfo) {
        guard identifier.deviceId == selectedPolarIdentifier else { return }
        connectionState = .connecting
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
        tryResumeConnectIfReady()
    }

    func deviceDisconnected(_ identifier: PolarDeviceInfo, pairingError: Bool) {
        guard identifier.deviceId == selectedPolarIdentifier else { return }

        isSelectedDeviceConnected = false
        isSelectedDeviceHrFeatureReady = false
        connectionState = .deviceSelected

        if let connectContinuation {
            connectContinuation.resume(throwing: PolarAdapterError.connectionInterrupted)
            self.connectContinuation = nil
        }
    }
}

extension PolarDeviceAdapter: PolarBleApiPowerStateObserver {
    func blePowerOn() {
        isBluetoothOn = true
    }

    func blePowerOff() {
        isBluetoothOn = false
    }
}

extension PolarDeviceAdapter: PolarBleApiDeviceFeaturesObserver {
    func bleSdkFeatureReady(_ identifier: String, feature: PolarBleSdkFeature) {
        guard identifier == selectedPolarIdentifier else { return }
        guard feature == .feature_hr else { return }

        isSelectedDeviceHrFeatureReady = true
        tryResumeConnectIfReady()
    }
}
#else
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

    let deviceIdentity: CollectorDevice = CollectorDevice(
        id: "polar-unavailable",
        name: "Polar Device",
        vendor: "Polar",
        model: "Unavailable"
    )

    let availableStreams: [CollectorStream] = [.heartRate]

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

    func heartRateStreamProvider() -> HeartRateStreamProviding? {
        nil
    }
}
#endif
#endif
