import Foundation

#if targetEnvironment(simulator) && arch(x86_64)
final class PolarHrStreamProvider: HeartRateStreamProviding {
    let streamType: CollectorStream = .heartRate

    init(
        api: Any? = nil,
        deviceIDProvider: @escaping () -> String? = { nil },
        timestampProvider: @escaping () -> Date = { Date() }
    ) {}

    func start(onSample: @escaping @Sendable (HeartRateSample) -> Void) {}

    func stop() {}
}
#else
#if canImport(PolarBleSdk) && canImport(RxSwift)
@preconcurrency import PolarBleSdk
@preconcurrency import RxSwift

final class PolarHrStreamProvider: HeartRateStreamProviding {
    let streamType: CollectorStream = .heartRate

    private let api: PolarBleApi
    private let deviceIDProvider: () -> String?
    private let timestampProvider: () -> Date

    private var streamDisposable: Disposable?
    private var sampleSequenceNumber: Int = 0

    init(
        api: PolarBleApi,
        deviceIDProvider: @escaping () -> String? = { nil },
        timestampProvider: @escaping () -> Date = { Date() }
    ) {
        self.api = api
        self.deviceIDProvider = deviceIDProvider
        self.timestampProvider = timestampProvider
    }

    func start(onSample: @escaping @Sendable (HeartRateSample) -> Void) {
        stop()

        guard let identifier = deviceIDProvider() else { return }
        sampleSequenceNumber = 0

        streamDisposable = api.startHrStreaming(identifier)
            .observe(on: MainScheduler.instance)
            .subscribe(
                onNext: { [weak self] hrData in
                    guard let self else { return }
                    for entry in hrData {
                        let streamData = PolarHrStreamData(
                            hr: Int(entry.hr),
                            ppgQuality: Int(entry.ppgQuality),
                            correctedHr: Int(entry.correctedHr),
                            rrsMs: entry.rrsMs,
                            rrAvailable: entry.rrAvailable,
                            contactStatus: entry.contactStatus,
                            contactStatusSupported: entry.contactStatusSupported
                        )

                        let sample = HeartRateSample(
                            hrBPM: streamData.hr,
                            collectorReceivedAtUTC: self.timestampProvider(),
                            deviceTimestampRaw: nil,
                            sourceTimestampKind: .collectorObserved,
                            sampleSequenceNumber: self.sampleSequenceNumber,
                            streamData: streamData
                        )
                        

                        self.sampleSequenceNumber += 1
                        onSample(sample)
                    }
                },
                onError: { error in
                    print("Polar HR stream error: \(error)")
                }
            )
    }

    func stop() {
        streamDisposable?.dispose()
        streamDisposable = nil
    }
}
#else
final class PolarHrStreamProvider: HeartRateStreamProviding {
    let streamType: CollectorStream = .heartRate

    init(
        api: Any? = nil,
        deviceIDProvider: @escaping () -> String? = { nil },
        timestampProvider: @escaping () -> Date = { Date() }
    ) {}

    func start(onSample: @escaping @Sendable (HeartRateSample) -> Void) {}

    func stop() {}
}
#endif
#endif
