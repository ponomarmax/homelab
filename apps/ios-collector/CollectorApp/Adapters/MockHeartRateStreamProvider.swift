import Foundation

final class MockHeartRateStreamProvider: HeartRateStreamProviding {
    let streamType: CollectorStream = .heartRate

    private let values: [Int]
    private let intervalNanoseconds: UInt64
    private let timestampProvider: @Sendable () -> Date
    private var task: Task<Void, Never>?

    init(
        values: [Int] = [64, 66, 67, 69, 71, 72, 74, 73],
        intervalNanoseconds: UInt64 = 1_000_000_000,
        timestampProvider: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.values = values
        self.intervalNanoseconds = intervalNanoseconds
        self.timestampProvider = timestampProvider
    }

    func start(onSample: @escaping @Sendable (HeartRateSample) -> Void) {
        stop()

        task = Task { [values, intervalNanoseconds, timestampProvider] in
            var index = 0
            var sequenceNumber = 0
            while !Task.isCancelled {
                let sample = HeartRateSample(
                    value: values[index % values.count],
                    collectorReceivedAtUTC: timestampProvider(),
                    rawDeviceTimestamp: nil,
                    sourceTimestampKind: .collectorObserved,
                    sampleSequenceNumber: sequenceNumber
                )

                onSample(sample)
                sequenceNumber += 1
                index += 1

                do {
                    try await Task.sleep(nanoseconds: intervalNanoseconds)
                } catch {
                    break
                }
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }
}
