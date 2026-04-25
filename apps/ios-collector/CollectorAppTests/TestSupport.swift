import XCTest
@testable import CollectorApp

final class ImmediateHeartRateProvider: HeartRateStreamProviding {
    let streamType: CollectorStream = .heartRate

    private let samples: [HeartRateSample]
    private var isStopped = false

    init(samples: [HeartRateSample]) {
        self.samples = samples
    }

    func start(onSample: @escaping @Sendable (HeartRateSample) -> Void) {
        isStopped = false
        for sample in samples where !isStopped {
            onSample(sample)
        }
    }

    func stop() {
        isStopped = true
    }
}

enum TestUploadError: LocalizedError {
    case rejected

    var errorDescription: String? {
        "upload rejected"
    }
}

final class LockedValueBox<Value> {
    private var value: Value
    private let lock = NSLock()

    init(_ value: Value) {
        self.value = value
    }

    func withValue<T>(_ mutation: (inout Value) -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return mutation(&value)
    }
}

func makeSample(
    hr: Int,
    receivedAt: Date,
    sequence: Int,
    deviceTimestamp: Date? = nil,
    sourceTimestampKind: SourceTimestampKind? = .collectorObserved,
    streamData: PolarHrStreamData? = nil
) -> HeartRateSample {
    HeartRateSample(
        hrBPM: hr,
        collectorReceivedAtUTC: receivedAt,
        deviceTimestampRaw: deviceTimestamp,
        sourceTimestampKind: sourceTimestampKind,
        sampleSequenceNumber: sequence,
        streamData: streamData
    )
}

func waitUntil(
    timeoutNanoseconds: UInt64 = 1_000_000_000,
    pollIntervalNanoseconds: UInt64 = 10_000_000,
    _ condition: @escaping @MainActor () -> Bool
) async -> Bool {
    let started = DispatchTime.now().uptimeNanoseconds
    while !(await condition()) {
        let elapsed = DispatchTime.now().uptimeNanoseconds - started
        if elapsed >= timeoutNanoseconds {
            return false
        }
        try? await Task.sleep(nanoseconds: pollIntervalNanoseconds)
    }
    return true
}
