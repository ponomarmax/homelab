import Foundation

#if targetEnvironment(simulator) && arch(x86_64)
struct PolarStreamSettingsMetadata: Equatable, Sendable {
    let sampleRateHz: UInt32?
    let rangeMg: UInt32?
}

struct PolarCollectorEventMapper {
    static func mapHr(
        entry: (hr: UInt8, ppgQuality: UInt8, correctedHr: UInt8, rrsMs: [Int], rrAvailable: Bool, contactStatus: Bool, contactStatusSupported: Bool),
        sequenceNumber: Int,
        receivedAt: Date
    ) -> HeartRateSample {
        let streamData = PolarHrStreamData(
            hr: Int(entry.hr),
            ppgQuality: Int(entry.ppgQuality),
            correctedHr: Int(entry.correctedHr),
            rrsMs: entry.rrsMs,
            rrAvailable: entry.rrAvailable,
            contactStatus: entry.contactStatus,
            contactStatusSupported: entry.contactStatusSupported
        )
        return HeartRateSample(
            stream: .heartRate,
            collectorReceivedAtUTC: receivedAt,
            sourceTimestampKind: .collectorObserved,
            sampleSequenceNumber: sequenceNumber,
            payload: .hr(streamData)
        )
    }

    static func mapEcg(
        sample: (timeStamp: UInt64, voltage: Int32),
        sequenceNumber: Int,
        receivedAt: Date,
        settings: PolarStreamSettingsMetadata
    ) -> HeartRateSample {
        HeartRateSample(
            stream: .ecg,
            collectorReceivedAtUTC: receivedAt,
            sourceTimestampKind: .deviceReported,
            sampleSequenceNumber: sequenceNumber,
            payload: .ecg(
                PolarEcgSampleData(
                    deviceTimeNS: sample.timeStamp,
                    ecgUv: sample.voltage,
                    sampleRateHz: settings.sampleRateHz
                )
            )
        )
    }

    static func mapAcc(
        sample: (timeStamp: UInt64, x: Int32, y: Int32, z: Int32),
        sequenceNumber: Int,
        receivedAt: Date,
        settings: PolarStreamSettingsMetadata
    ) -> HeartRateSample {
        HeartRateSample(
            stream: .accelerometer,
            collectorReceivedAtUTC: receivedAt,
            sourceTimestampKind: .deviceReported,
            sampleSequenceNumber: sequenceNumber,
            payload: .acc(
                PolarAccSampleData(
                    deviceTimeNS: sample.timeStamp,
                    xMg: sample.x,
                    yMg: sample.y,
                    zMg: sample.z,
                    sampleRateHz: settings.sampleRateHz,
                    rangeMg: settings.rangeMg
                )
            )
        )
    }

    static func mapBattery(
        eventType: PolarBatteryEventType,
        sequenceNumber: Int,
        receivedAt: Date,
        levelPercent: Int?,
        chargeState: String?,
        powerSources: [String]?,
        sdkRaw: String?,
        unavailableReason: String?
    ) -> HeartRateSample {
        HeartRateSample(
            stream: .battery,
            collectorReceivedAtUTC: receivedAt,
            sourceTimestampKind: .collectorObserved,
            sampleSequenceNumber: sequenceNumber,
            payload: .battery(
                PolarBatteryData(
                    eventType: eventType,
                    levelPercent: levelPercent,
                    chargeState: chargeState,
                    powerSources: powerSources,
                    sdkRaw: sdkRaw,
                    unavailableReason: unavailableReason
                )
            )
        )
    }
}

final class PolarHrStreamProvider: HeartRateStreamProviding {
    let streamType: CollectorStream = .heartRate

    init(
        api: Any? = nil,
        deviceIDProvider: @escaping () -> String? = { nil },
        timestampProvider: @escaping () -> Date = { Date() },
        logger: @escaping @Sendable (String) -> Void = { _ in }
    ) {}

    func start(onSample: @escaping @Sendable (HeartRateSample) -> Void) {}

    func stop() {}
}

final class PolarEcgStreamProvider: HeartRateStreamProviding {
    let streamType: CollectorStream = .ecg

    init(
        api: Any? = nil,
        deviceIDProvider: @escaping () -> String? = { nil },
        timestampProvider: @escaping () -> Date = { Date() },
        logger: @escaping @Sendable (String) -> Void = { _ in }
    ) {}

    func start(onSample: @escaping @Sendable (HeartRateSample) -> Void) {}

    func stop() {}
}

final class PolarAccStreamProvider: HeartRateStreamProviding {
    let streamType: CollectorStream = .accelerometer

    init(
        api: Any? = nil,
        deviceIDProvider: @escaping () -> String? = { nil },
        timestampProvider: @escaping () -> Date = { Date() },
        logger: @escaping @Sendable (String) -> Void = { _ in }
    ) {}

    func start(onSample: @escaping @Sendable (HeartRateSample) -> Void) {}

    func stop() {}
}

final class PolarBatteryStreamProvider: HeartRateStreamProviding {
    let streamType: CollectorStream = .battery

    init(
        timestampProvider: @escaping () -> Date = { Date() },
        logger: @escaping @Sendable (String) -> Void = { _ in }
    ) {}

    func start(onSample: @escaping @Sendable (HeartRateSample) -> Void) {}

    func stop() {}

    func publishCallbackUpdate(
        levelPercent: Int?,
        chargeState: String?,
        powerSources: [String]?,
        sdkRaw: String?
    ) {}

    func publishPollSnapshot(
        levelPercent: Int?,
        chargeState: String?,
        powerSources: [String]?,
        sdkRaw: String?
    ) {}

    func publishUnavailable(reason: String, sdkRaw: String? = nil) {}
}
#else
#if canImport(PolarBleSdk) && canImport(RxSwift)
@preconcurrency import PolarBleSdk
@preconcurrency import RxSwift

struct PolarStreamSettingsMetadata: Equatable, Sendable {
    let sampleRateHz: UInt32?
    let rangeMg: UInt32?
}

struct PolarCollectorEventMapper {
    static func mapHr(
        entry: (hr: UInt8, ppgQuality: UInt8, correctedHr: UInt8, rrsMs: [Int], rrAvailable: Bool, contactStatus: Bool, contactStatusSupported: Bool),
        sequenceNumber: Int,
        receivedAt: Date
    ) -> HeartRateSample {
        let streamData = PolarHrStreamData(
            hr: Int(entry.hr),
            ppgQuality: Int(entry.ppgQuality),
            correctedHr: Int(entry.correctedHr),
            rrsMs: entry.rrsMs,
            rrAvailable: entry.rrAvailable,
            contactStatus: entry.contactStatus,
            contactStatusSupported: entry.contactStatusSupported
        )
        return HeartRateSample(
            stream: .heartRate,
            collectorReceivedAtUTC: receivedAt,
            sourceTimestampKind: .collectorObserved,
            sampleSequenceNumber: sequenceNumber,
            payload: .hr(streamData)
        )
    }

    static func mapEcg(
        sample: (timeStamp: UInt64, voltage: Int32),
        sequenceNumber: Int,
        receivedAt: Date,
        settings: PolarStreamSettingsMetadata
    ) -> HeartRateSample {
        HeartRateSample(
            stream: .ecg,
            collectorReceivedAtUTC: receivedAt,
            sourceTimestampKind: .deviceReported,
            sampleSequenceNumber: sequenceNumber,
            payload: .ecg(
                PolarEcgSampleData(
                    deviceTimeNS: sample.timeStamp,
                    ecgUv: sample.voltage,
                    sampleRateHz: settings.sampleRateHz
                )
            )
        )
    }

    static func mapAcc(
        sample: (timeStamp: UInt64, x: Int32, y: Int32, z: Int32),
        sequenceNumber: Int,
        receivedAt: Date,
        settings: PolarStreamSettingsMetadata
    ) -> HeartRateSample {
        HeartRateSample(
            stream: .accelerometer,
            collectorReceivedAtUTC: receivedAt,
            sourceTimestampKind: .deviceReported,
            sampleSequenceNumber: sequenceNumber,
            payload: .acc(
                PolarAccSampleData(
                    deviceTimeNS: sample.timeStamp,
                    xMg: sample.x,
                    yMg: sample.y,
                    zMg: sample.z,
                    sampleRateHz: settings.sampleRateHz,
                    rangeMg: settings.rangeMg
                )
            )
        )
    }

    static func mapBattery(
        eventType: PolarBatteryEventType,
        sequenceNumber: Int,
        receivedAt: Date,
        levelPercent: Int?,
        chargeState: String?,
        powerSources: [String]?,
        sdkRaw: String?,
        unavailableReason: String?
    ) -> HeartRateSample {
        HeartRateSample(
            stream: .battery,
            collectorReceivedAtUTC: receivedAt,
            sourceTimestampKind: .collectorObserved,
            sampleSequenceNumber: sequenceNumber,
            payload: .battery(
                PolarBatteryData(
                    eventType: eventType,
                    levelPercent: levelPercent,
                    chargeState: chargeState,
                    powerSources: powerSources,
                    sdkRaw: sdkRaw,
                    unavailableReason: unavailableReason
                )
            )
        )
    }
}

final class PolarHrStreamProvider: HeartRateStreamProviding {
    let streamType: CollectorStream = .heartRate

    private let api: PolarBleApi
    private let deviceIDProvider: () -> String?
    private let timestampProvider: () -> Date
    private let logger: @Sendable (String) -> Void

    private var streamDisposable: Disposable?
    private var sampleSequenceNumber: Int = 0

    init(
        api: PolarBleApi,
        deviceIDProvider: @escaping () -> String? = { nil },
        timestampProvider: @escaping () -> Date = { Date() },
        logger: @escaping @Sendable (String) -> Void = { _ in }
    ) {
        self.api = api
        self.deviceIDProvider = deviceIDProvider
        self.timestampProvider = timestampProvider
        self.logger = logger
    }

    func start(onSample: @escaping @Sendable (HeartRateSample) -> Void) {
        stop()

        guard let identifier = deviceIDProvider() else {
            logger("[polar-hr] start skipped: missing device identifier")
            return
        }
        sampleSequenceNumber = 0

        streamDisposable = api.startHrStreaming(identifier)
            .observe(on: MainScheduler.asyncInstance)
            .subscribe(
                onNext: { [weak self] hrData in
                    guard let self else { return }
                    for entry in hrData {
                        let sample = PolarCollectorEventMapper.mapHr(
                            entry: entry,
                            sequenceNumber: self.sampleSequenceNumber,
                            receivedAt: self.timestampProvider()
                        )
                        self.sampleSequenceNumber += 1
                        onSample(sample)
                    }
                },
                onError: { [logger] error in
                    logger("[polar-hr] stream error: \(error.localizedDescription)")
                }
            )
    }

    func stop() {
        streamDisposable?.dispose()
        streamDisposable = nil
    }
}

final class PolarEcgStreamProvider: HeartRateStreamProviding {
    let streamType: CollectorStream = .ecg

    private let api: PolarBleApi
    private let deviceIDProvider: () -> String?
    private let timestampProvider: () -> Date
    private let logger: @Sendable (String) -> Void

    private var streamDisposable: Disposable?
    private var settingsDisposable: Disposable?
    private var retryWorkItem: DispatchWorkItem?
    private var sampleSequenceNumber: Int = 0
    private var settingsMetadata = PolarStreamSettingsMetadata(sampleRateHz: nil, rangeMg: nil)

    init(
        api: PolarBleApi,
        deviceIDProvider: @escaping () -> String? = { nil },
        timestampProvider: @escaping () -> Date = { Date() },
        logger: @escaping @Sendable (String) -> Void = { _ in }
    ) {
        self.api = api
        self.deviceIDProvider = deviceIDProvider
        self.timestampProvider = timestampProvider
        self.logger = logger
    }

    func start(onSample: @escaping @Sendable (HeartRateSample) -> Void) {
        stop()

        guard let identifier = deviceIDProvider() else {
            logger("[polar-ecg] start skipped: missing device identifier")
            return
        }

        sampleSequenceNumber = 0
        logger("[polar-ecg] start requested")
        startStreaming(identifier: identifier, onSample: onSample, attempt: 1)
    }

    func stop() {
        retryWorkItem?.cancel()
        retryWorkItem = nil
        settingsDisposable?.dispose()
        settingsDisposable = nil
        streamDisposable?.dispose()
        streamDisposable = nil
    }

    private func startStreaming(
        identifier: String,
        onSample: @escaping @Sendable (HeartRateSample) -> Void,
        attempt: Int
    ) {
        settingsMetadata = PolarStreamSettingsMetadata(sampleRateHz: nil, rangeMg: nil)

        requestPreferredSettings(
            identifier: identifier,
            attempt: attempt,
            onSample: onSample
        )
    }

    private func requestPreferredSettings(
        identifier: String,
        attempt: Int,
        onSample: @escaping @Sendable (HeartRateSample) -> Void
    ) {
        settingsDisposable?.dispose()
        settingsDisposable = api.requestStreamSettings(identifier, feature: .ecg)
            .observe(on: MainScheduler.asyncInstance)
            .subscribe(
                onSuccess: { [weak self] availableSettings in
                    guard let self else { return }
                    self.settingsDisposable = nil
                    self.startStreamSubscription(
                        identifier: identifier,
                        availableSettings: availableSettings,
                        settingsSource: "requestStreamSettings",
                        attempt: attempt,
                        onSample: onSample
                    )
                },
                onFailure: { [weak self] error in
                    guard let self else { return }
                    self.settingsDisposable = nil
                    self.logger("[polar-ecg] requestStreamSettings failed (attempt \(attempt)): \(Self.describe(error))")
                    self.requestFullSettings(
                        identifier: identifier,
                        attempt: attempt,
                        onSample: onSample,
                        priorError: error
                    )
                }
            )
    }

    private func requestFullSettings(
        identifier: String,
        attempt: Int,
        onSample: @escaping @Sendable (HeartRateSample) -> Void,
        priorError: Error
    ) {
        settingsDisposable?.dispose()
        settingsDisposable = api.requestFullStreamSettings(identifier, feature: .ecg)
            .observe(on: MainScheduler.asyncInstance)
            .subscribe(
                onSuccess: { [weak self] availableSettings in
                    guard let self else { return }
                    self.settingsDisposable = nil
                    self.startStreamSubscription(
                        identifier: identifier,
                        availableSettings: availableSettings,
                        settingsSource: "requestFullStreamSettings",
                        attempt: attempt,
                        onSample: onSample
                    )
                },
                onFailure: { [weak self] fullSettingsError in
                    guard let self else { return }
                    self.settingsDisposable = nil
                    self.logger("[polar-ecg] requestFullStreamSettings failed (attempt \(attempt)): \(Self.describe(fullSettingsError))")

                    let effectiveError = Self.isRetryableStartError(fullSettingsError) ? fullSettingsError : priorError
                    if self.scheduleRetryIfNeeded(
                        error: effectiveError,
                        attempt: attempt,
                        identifier: identifier,
                        onSample: onSample,
                        tag: "settings query"
                    ) {
                        return
                    }

                    guard let fallbackSettings = Self.makeDefaultSettings() else {
                        self.logger("[polar-ecg] failed to create fallback stream settings")
                        return
                    }
                    self.logger("[polar-ecg] starting with fallback empty settings")
                    self.startStreamSubscription(
                        identifier: identifier,
                        settings: fallbackSettings,
                        settingsSource: "fallback_empty",
                        attempt: attempt,
                        onSample: onSample
                    )
                }
            )
    }

    private func startStreamSubscription(
        identifier: String,
        availableSettings: PolarSensorSetting,
        settingsSource: String,
        attempt: Int,
        onSample: @escaping @Sendable (HeartRateSample) -> Void
    ) {
        let chosen = Self.preferredSettings(from: availableSettings) ?? availableSettings
        startStreamSubscription(
            identifier: identifier,
            settings: chosen,
            settingsSource: settingsSource,
            attempt: attempt,
            onSample: onSample
        )
    }

    private func startStreamSubscription(
        identifier: String,
        settings: PolarSensorSetting,
        settingsSource: String,
        attempt: Int,
        onSample: @escaping @Sendable (HeartRateSample) -> Void
    ) {
        streamDisposable?.dispose()
        settingsMetadata = Self.metadata(from: settings)

        logger(
            "[polar-ecg] stream start settings source=\(settingsSource) sample_rate_hz=\(settingsMetadata.sampleRateHz.map(String.init) ?? "n/a") raw=\(Self.describe(settings: settings))"
        )

        streamDisposable = api.startEcgStreaming(identifier, settings: settings)
            .observe(on: MainScheduler.asyncInstance)
            .subscribe(
                onNext: { [weak self] ecgData in
                    guard let self else { return }
                    for entry in ecgData {
                        let sample = PolarCollectorEventMapper.mapEcg(
                            sample: entry,
                            sequenceNumber: self.sampleSequenceNumber,
                            receivedAt: self.timestampProvider(),
                            settings: self.settingsMetadata
                        )
                        self.sampleSequenceNumber += 1
                        if self.sampleSequenceNumber == 1 {
                            self.logger("[polar-ecg] first sample received")
                        } else if self.sampleSequenceNumber.isMultiple(of: 130) {
                            self.logger("[polar-ecg] samples received=\(self.sampleSequenceNumber)")
                        }
                        onSample(sample)
                    }
                },
                onError: { [weak self] error in
                    guard let self else { return }
                    self.streamDisposable = nil
                    if self.scheduleRetryIfNeeded(
                        error: error,
                        attempt: attempt,
                        identifier: identifier,
                        onSample: onSample,
                        tag: "stream start"
                    ) {
                        return
                    }
                    self.logger("[polar-ecg] stream error: \(Self.describe(error))")
                }
            )
    }

    private func scheduleRetryIfNeeded(
        error: Error,
        attempt: Int,
        identifier: String,
        onSample: @escaping @Sendable (HeartRateSample) -> Void,
        tag: String
    ) -> Bool {
        guard attempt < 8, Self.isRetryableStartError(error) else { return false }
        retryWorkItem?.cancel()
        let delay = 0.6 + (Double(attempt) * 0.4)
        logger("[polar-ecg] \(tag) failed (attempt \(attempt)): \(Self.describe(error)). Retrying...")
        let work = DispatchWorkItem { [weak self] in
            self?.startStreaming(identifier: identifier, onSample: onSample, attempt: attempt + 1)
        }
        retryWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
        return true
    }

    private static func makeDefaultSettings() -> PolarSensorSetting? {
        try? PolarSensorSetting([:])
    }

    private static func preferredSettings(from availableSettings: PolarSensorSetting) -> PolarSensorSetting? {
        var selected: [PolarSensorSetting.SettingType: UInt32] = [:]
        for (settingType, values) in availableSettings.settings {
            guard let selectedValue = values.max() else { continue }
            selected[settingType] = selectedValue
        }
        guard !selected.isEmpty else { return nil }
        return try? PolarSensorSetting(selected)
    }

    private static func metadata(from settings: PolarSensorSetting) -> PolarStreamSettingsMetadata {
        PolarStreamSettingsMetadata(
            sampleRateHz: settings.settings[.sampleRate]?.max(),
            rangeMg: settings.settings[.range]?.max()
        )
    }

    private static func describe(settings: PolarSensorSetting) -> String {
        let entries = settings.settings
            .map { key, values in
                let sortedValues = values.sorted().map(String.init).joined(separator: ",")
                return "\(key)=\(sortedValues)"
            }
            .sorted()
        return entries.isEmpty ? "empty" : entries.joined(separator: " ")
    }

    private static func isRetryableStartError(_ error: Error) -> Bool {
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
                return errorCode == 8 || errorCode == 12
            default:
                break
            }
        }
        let nsError = error as NSError
        return nsError.code == 8 || nsError.code == 12
    }

    private static func describe(_ error: Error) -> String {
        let nsError = error as NSError
        return "\(error) | domain=\(nsError.domain) code=\(nsError.code) desc=\(nsError.localizedDescription)"
    }
}

final class PolarAccStreamProvider: HeartRateStreamProviding {
    let streamType: CollectorStream = .accelerometer

    private let api: PolarBleApi
    private let deviceIDProvider: () -> String?
    private let timestampProvider: () -> Date
    private let logger: @Sendable (String) -> Void

    private var streamDisposable: Disposable?
    private var settingsDisposable: Disposable?
    private var retryWorkItem: DispatchWorkItem?
    private var sampleSequenceNumber: Int = 0
    private var settingsMetadata = PolarStreamSettingsMetadata(sampleRateHz: nil, rangeMg: nil)

    init(
        api: PolarBleApi,
        deviceIDProvider: @escaping () -> String? = { nil },
        timestampProvider: @escaping () -> Date = { Date() },
        logger: @escaping @Sendable (String) -> Void = { _ in }
    ) {
        self.api = api
        self.deviceIDProvider = deviceIDProvider
        self.timestampProvider = timestampProvider
        self.logger = logger
    }

    func start(onSample: @escaping @Sendable (HeartRateSample) -> Void) {
        stop()

        guard let identifier = deviceIDProvider() else {
            logger("[polar-acc] start skipped: missing device identifier")
            return
        }
        sampleSequenceNumber = 0
        logger("[polar-acc] start requested")
        startStreaming(identifier: identifier, onSample: onSample, attempt: 1)
    }

    func stop() {
        retryWorkItem?.cancel()
        retryWorkItem = nil
        settingsDisposable?.dispose()
        settingsDisposable = nil
        streamDisposable?.dispose()
        streamDisposable = nil
    }

    private func startStreaming(
        identifier: String,
        onSample: @escaping @Sendable (HeartRateSample) -> Void,
        attempt: Int
    ) {
        settingsMetadata = PolarStreamSettingsMetadata(sampleRateHz: nil, rangeMg: nil)

        requestPreferredSettings(
            identifier: identifier,
            attempt: attempt,
            onSample: onSample
        )
    }

    private func requestPreferredSettings(
        identifier: String,
        attempt: Int,
        onSample: @escaping @Sendable (HeartRateSample) -> Void
    ) {
        settingsDisposable?.dispose()
        settingsDisposable = api.requestStreamSettings(identifier, feature: .acc)
            .observe(on: MainScheduler.asyncInstance)
            .subscribe(
                onSuccess: { [weak self] availableSettings in
                    guard let self else { return }
                    self.settingsDisposable = nil
                    self.startStreamSubscription(
                        identifier: identifier,
                        availableSettings: availableSettings,
                        settingsSource: "requestStreamSettings",
                        attempt: attempt,
                        onSample: onSample
                    )
                },
                onFailure: { [weak self] error in
                    guard let self else { return }
                    self.settingsDisposable = nil
                    self.logger("[polar-acc] requestStreamSettings failed (attempt \(attempt)): \(Self.describe(error))")
                    self.requestFullSettings(
                        identifier: identifier,
                        attempt: attempt,
                        onSample: onSample,
                        priorError: error
                    )
                }
            )
    }

    private func requestFullSettings(
        identifier: String,
        attempt: Int,
        onSample: @escaping @Sendable (HeartRateSample) -> Void,
        priorError: Error
    ) {
        settingsDisposable?.dispose()
        settingsDisposable = api.requestFullStreamSettings(identifier, feature: .acc)
            .observe(on: MainScheduler.asyncInstance)
            .subscribe(
                onSuccess: { [weak self] availableSettings in
                    guard let self else { return }
                    self.settingsDisposable = nil
                    self.startStreamSubscription(
                        identifier: identifier,
                        availableSettings: availableSettings,
                        settingsSource: "requestFullStreamSettings",
                        attempt: attempt,
                        onSample: onSample
                    )
                },
                onFailure: { [weak self] fullSettingsError in
                    guard let self else { return }
                    self.settingsDisposable = nil
                    self.logger("[polar-acc] requestFullStreamSettings failed (attempt \(attempt)): \(Self.describe(fullSettingsError))")

                    let effectiveError = Self.isRetryableStartError(fullSettingsError) ? fullSettingsError : priorError
                    if self.scheduleRetryIfNeeded(
                        error: effectiveError,
                        attempt: attempt,
                        identifier: identifier,
                        onSample: onSample,
                        tag: "settings query"
                    ) {
                        return
                    }

                    guard let fallbackSettings = Self.makeDefaultSettings() else {
                        self.logger("[polar-acc] failed to create fallback stream settings")
                        return
                    }
                    self.logger("[polar-acc] starting with fallback empty settings")
                    self.startStreamSubscription(
                        identifier: identifier,
                        settings: fallbackSettings,
                        settingsSource: "fallback_empty",
                        attempt: attempt,
                        onSample: onSample
                    )
                }
            )
    }

    private func startStreamSubscription(
        identifier: String,
        availableSettings: PolarSensorSetting,
        settingsSource: String,
        attempt: Int,
        onSample: @escaping @Sendable (HeartRateSample) -> Void
    ) {
        let chosen = Self.preferredSettings(from: availableSettings) ?? availableSettings
        startStreamSubscription(
            identifier: identifier,
            settings: chosen,
            settingsSource: settingsSource,
            attempt: attempt,
            onSample: onSample
        )
    }

    private func startStreamSubscription(
        identifier: String,
        settings: PolarSensorSetting,
        settingsSource: String,
        attempt: Int,
        onSample: @escaping @Sendable (HeartRateSample) -> Void
    ) {
        streamDisposable?.dispose()
        settingsMetadata = Self.metadata(from: settings)

        logger(
            "[polar-acc] stream start settings source=\(settingsSource) sample_rate_hz=\(settingsMetadata.sampleRateHz.map(String.init) ?? "n/a") range_mg=\(settingsMetadata.rangeMg.map(String.init) ?? "n/a") raw=\(Self.describe(settings: settings))"
        )

        streamDisposable = api.startAccStreaming(identifier, settings: settings)
            .observe(on: MainScheduler.asyncInstance)
            .subscribe(
                onNext: { [weak self] accData in
                    guard let self else { return }
                    for entry in accData {
                        let sample = PolarCollectorEventMapper.mapAcc(
                            sample: entry,
                            sequenceNumber: self.sampleSequenceNumber,
                            receivedAt: self.timestampProvider(),
                            settings: self.settingsMetadata
                        )
                        self.sampleSequenceNumber += 1
                        if self.sampleSequenceNumber == 1 {
                            self.logger("[polar-acc] first sample received")
                        } else if self.sampleSequenceNumber.isMultiple(of: 200) {
                            self.logger("[polar-acc] samples received=\(self.sampleSequenceNumber)")
                        }
                        onSample(sample)
                    }
                },
                onError: { [weak self] error in
                    guard let self else { return }
                    self.streamDisposable = nil
                    if self.scheduleRetryIfNeeded(
                        error: error,
                        attempt: attempt,
                        identifier: identifier,
                        onSample: onSample,
                        tag: "stream start"
                    ) {
                        return
                    }
                    self.logger("[polar-acc] stream error: \(Self.describe(error))")
                }
            )
    }

    private func scheduleRetryIfNeeded(
        error: Error,
        attempt: Int,
        identifier: String,
        onSample: @escaping @Sendable (HeartRateSample) -> Void,
        tag: String
    ) -> Bool {
        guard attempt < 8, Self.isRetryableStartError(error) else { return false }
        retryWorkItem?.cancel()
        let delay = 0.6 + (Double(attempt) * 0.4)
        logger("[polar-acc] \(tag) failed (attempt \(attempt)): \(Self.describe(error)). Retrying...")
        let work = DispatchWorkItem { [weak self] in
            self?.startStreaming(identifier: identifier, onSample: onSample, attempt: attempt + 1)
        }
        retryWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
        return true
    }

    private static func makeDefaultSettings() -> PolarSensorSetting? {
        try? PolarSensorSetting([:])
    }

    private static func preferredSettings(from availableSettings: PolarSensorSetting) -> PolarSensorSetting? {
        var selected: [PolarSensorSetting.SettingType: UInt32] = [:]
        for (settingType, values) in availableSettings.settings {
            guard let selectedValue = values.max() else { continue }
            selected[settingType] = selectedValue
        }
        guard !selected.isEmpty else { return nil }
        return try? PolarSensorSetting(selected)
    }

    private static func metadata(from settings: PolarSensorSetting) -> PolarStreamSettingsMetadata {
        PolarStreamSettingsMetadata(
            sampleRateHz: settings.settings[.sampleRate]?.max(),
            rangeMg: settings.settings[.range]?.max()
        )
    }

    private static func describe(settings: PolarSensorSetting) -> String {
        let entries = settings.settings
            .map { key, values in
                let sortedValues = values.sorted().map(String.init).joined(separator: ",")
                return "\(key)=\(sortedValues)"
            }
            .sorted()
        return entries.isEmpty ? "empty" : entries.joined(separator: " ")
    }

    private static func isRetryableStartError(_ error: Error) -> Bool {
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
                return errorCode == 8 || errorCode == 12
            default:
                break
            }
        }
        let nsError = error as NSError
        return nsError.code == 8 || nsError.code == 12
    }

    private static func describe(_ error: Error) -> String {
        let nsError = error as NSError
        return "\(error) | domain=\(nsError.domain) code=\(nsError.code) desc=\(nsError.localizedDescription)"
    }
}

final class PolarBatteryStreamProvider: HeartRateStreamProviding {
    let streamType: CollectorStream = .battery

    private let timestampProvider: () -> Date
    private let logger: @Sendable (String) -> Void
    private let emitQueue = DispatchQueue(label: "polar.battery.emit.serial")

    private var onSample: (@Sendable (HeartRateSample) -> Void)?
    private var sampleSequenceNumber: Int = 0
    private var pendingEvents: [PendingBatteryEvent] = []

    private struct PendingBatteryEvent {
        let eventType: PolarBatteryEventType
        let levelPercent: Int?
        let chargeState: String?
        let powerSources: [String]?
        let sdkRaw: String?
        let unavailableReason: String?
    }

    init(
        timestampProvider: @escaping () -> Date = { Date() },
        logger: @escaping @Sendable (String) -> Void = { _ in }
    ) {
        self.timestampProvider = timestampProvider
        self.logger = logger
    }

    func start(onSample: @escaping @Sendable (HeartRateSample) -> Void) {
        emitQueue.async { [weak self] in
            guard let self else { return }
            self.onSample = onSample
            self.sampleSequenceNumber = 0
            let buffered = self.pendingEvents
            self.pendingEvents.removeAll(keepingCapacity: true)
            for event in buffered {
                self.emit(
                    eventType: event.eventType,
                    levelPercent: event.levelPercent,
                    chargeState: event.chargeState,
                    powerSources: event.powerSources,
                    sdkRaw: event.sdkRaw,
                    unavailableReason: event.unavailableReason
                )
            }
        }
    }

    func stop() {
        emitQueue.async { [weak self] in
            self?.onSample = nil
        }
    }

    func publishCallbackUpdate(
        levelPercent: Int?,
        chargeState: String?,
        powerSources: [String]?,
        sdkRaw: String?
    ) {
        emit(
            eventType: .callbackUpdate,
            levelPercent: levelPercent,
            chargeState: chargeState,
            powerSources: powerSources,
            sdkRaw: sdkRaw,
            unavailableReason: nil
        )
    }

    func publishPollSnapshot(
        levelPercent: Int?,
        chargeState: String?,
        powerSources: [String]?,
        sdkRaw: String?
    ) {
        emit(
            eventType: .pollSnapshot,
            levelPercent: levelPercent,
            chargeState: chargeState,
            powerSources: powerSources,
            sdkRaw: sdkRaw,
            unavailableReason: nil
        )
    }

    func publishUnavailable(reason: String, sdkRaw: String? = nil) {
        emit(
            eventType: .batteryUnavailable,
            levelPercent: nil,
            chargeState: nil,
            powerSources: nil,
            sdkRaw: sdkRaw,
            unavailableReason: reason
        )
    }

    private func emit(
        eventType: PolarBatteryEventType,
        levelPercent: Int?,
        chargeState: String?,
        powerSources: [String]?,
        sdkRaw: String?,
        unavailableReason: String?
    ) {
        emitQueue.async { [weak self] in
            guard let self else { return }
            guard let onSample = self.onSample else {
                if self.pendingEvents.count >= 32 {
                    self.pendingEvents.removeFirst()
                }
                self.pendingEvents.append(
                    PendingBatteryEvent(
                        eventType: eventType,
                        levelPercent: levelPercent,
                        chargeState: chargeState,
                        powerSources: powerSources,
                        sdkRaw: sdkRaw,
                        unavailableReason: unavailableReason
                    )
                )
                return
            }

            let sample = PolarCollectorEventMapper.mapBattery(
                eventType: eventType,
                sequenceNumber: self.sampleSequenceNumber,
                receivedAt: self.timestampProvider(),
                levelPercent: levelPercent,
                chargeState: chargeState,
                powerSources: powerSources,
                sdkRaw: sdkRaw,
                unavailableReason: unavailableReason
            )

            self.sampleSequenceNumber += 1
            DispatchQueue.main.async {
                onSample(sample)
            }
        }
    }
}

#else
struct PolarStreamSettingsMetadata: Equatable, Sendable {
    let sampleRateHz: UInt32?
    let rangeMg: UInt32?
}

struct PolarCollectorEventMapper {
    static func mapHr(
        entry: (hr: UInt8, ppgQuality: UInt8, correctedHr: UInt8, rrsMs: [Int], rrAvailable: Bool, contactStatus: Bool, contactStatusSupported: Bool),
        sequenceNumber: Int,
        receivedAt: Date
    ) -> HeartRateSample {
        let streamData = PolarHrStreamData(
            hr: Int(entry.hr),
            ppgQuality: Int(entry.ppgQuality),
            correctedHr: Int(entry.correctedHr),
            rrsMs: entry.rrsMs,
            rrAvailable: entry.rrAvailable,
            contactStatus: entry.contactStatus,
            contactStatusSupported: entry.contactStatusSupported
        )
        return HeartRateSample(
            stream: .heartRate,
            collectorReceivedAtUTC: receivedAt,
            sourceTimestampKind: .collectorObserved,
            sampleSequenceNumber: sequenceNumber,
            payload: .hr(streamData)
        )
    }

    static func mapEcg(
        sample: (timeStamp: UInt64, voltage: Int32),
        sequenceNumber: Int,
        receivedAt: Date,
        settings: PolarStreamSettingsMetadata
    ) -> HeartRateSample {
        HeartRateSample(
            stream: .ecg,
            collectorReceivedAtUTC: receivedAt,
            sourceTimestampKind: .deviceReported,
            sampleSequenceNumber: sequenceNumber,
            payload: .ecg(
                PolarEcgSampleData(
                    deviceTimeNS: sample.timeStamp,
                    ecgUv: sample.voltage,
                    sampleRateHz: settings.sampleRateHz
                )
            )
        )
    }

    static func mapAcc(
        sample: (timeStamp: UInt64, x: Int32, y: Int32, z: Int32),
        sequenceNumber: Int,
        receivedAt: Date,
        settings: PolarStreamSettingsMetadata
    ) -> HeartRateSample {
        HeartRateSample(
            stream: .accelerometer,
            collectorReceivedAtUTC: receivedAt,
            sourceTimestampKind: .deviceReported,
            sampleSequenceNumber: sequenceNumber,
            payload: .acc(
                PolarAccSampleData(
                    deviceTimeNS: sample.timeStamp,
                    xMg: sample.x,
                    yMg: sample.y,
                    zMg: sample.z,
                    sampleRateHz: settings.sampleRateHz,
                    rangeMg: settings.rangeMg
                )
            )
        )
    }

    static func mapBattery(
        eventType: PolarBatteryEventType,
        sequenceNumber: Int,
        receivedAt: Date,
        levelPercent: Int?,
        chargeState: String?,
        powerSources: [String]?,
        sdkRaw: String?,
        unavailableReason: String?
    ) -> HeartRateSample {
        HeartRateSample(
            stream: .battery,
            collectorReceivedAtUTC: receivedAt,
            sourceTimestampKind: .collectorObserved,
            sampleSequenceNumber: sequenceNumber,
            payload: .battery(
                PolarBatteryData(
                    eventType: eventType,
                    levelPercent: levelPercent,
                    chargeState: chargeState,
                    powerSources: powerSources,
                    sdkRaw: sdkRaw,
                    unavailableReason: unavailableReason
                )
            )
        )
    }
}

final class PolarHrStreamProvider: HeartRateStreamProviding {
    let streamType: CollectorStream = .heartRate

    init(
        api: Any? = nil,
        deviceIDProvider: @escaping () -> String? = { nil },
        timestampProvider: @escaping () -> Date = { Date() },
        logger: @escaping @Sendable (String) -> Void = { _ in }
    ) {}

    func start(onSample: @escaping @Sendable (HeartRateSample) -> Void) {}

    func stop() {}
}

final class PolarEcgStreamProvider: HeartRateStreamProviding {
    let streamType: CollectorStream = .ecg

    init(
        api: Any? = nil,
        deviceIDProvider: @escaping () -> String? = { nil },
        timestampProvider: @escaping () -> Date = { Date() },
        logger: @escaping @Sendable (String) -> Void = { _ in }
    ) {}

    func start(onSample: @escaping @Sendable (HeartRateSample) -> Void) {}

    func stop() {}
}

final class PolarAccStreamProvider: HeartRateStreamProviding {
    let streamType: CollectorStream = .accelerometer

    init(
        api: Any? = nil,
        deviceIDProvider: @escaping () -> String? = { nil },
        timestampProvider: @escaping () -> Date = { Date() },
        logger: @escaping @Sendable (String) -> Void = { _ in }
    ) {}

    func start(onSample: @escaping @Sendable (HeartRateSample) -> Void) {}

    func stop() {}
}

final class PolarBatteryStreamProvider: HeartRateStreamProviding {
    let streamType: CollectorStream = .battery

    init(
        timestampProvider: @escaping () -> Date = { Date() },
        logger: @escaping @Sendable (String) -> Void = { _ in }
    ) {}

    func start(onSample: @escaping @Sendable (HeartRateSample) -> Void) {}

    func stop() {}

    func publishCallbackUpdate(
        levelPercent: Int?,
        chargeState: String?,
        powerSources: [String]?,
        sdkRaw: String?
    ) {}

    func publishPollSnapshot(
        levelPercent: Int?,
        chargeState: String?,
        powerSources: [String]?,
        sdkRaw: String?
    ) {}

    func publishUnavailable(reason: String, sdkRaw: String? = nil) {}
}
#endif
#endif
