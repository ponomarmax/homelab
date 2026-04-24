import Foundation

@MainActor
final class CollectorCore: ObservableObject {
    @Published private(set) var status: CollectorStatus = .disconnected
    @Published private(set) var selectedDevice: CollectorDevice?
    @Published private(set) var activeSession: CollectionSession?
    @Published private(set) var latestHeartRateSample: HeartRateSample?
    @Published private(set) var totalSamplesReceived: Int = 0
    @Published private(set) var lastPreparedChunkBoundary: PreparedChunkBoundary?

    let defaultCollectionMode: CollectionMode = .live

    private let adapter: CollectorDeviceAdapter
    private let transport: CollectorTransporting

    private(set) var preparedSessionBoundary: PreparedSessionBoundary?

    init(
        adapter: CollectorDeviceAdapter,
        transport: CollectorTransporting
    ) {
        self.adapter = adapter
        self.transport = transport
    }

    func selectDevice() {
        selectedDevice = adapter.deviceIdentity
        if let mockAdapter = adapter as? MockDeviceAdapter {
            mockAdapter.markSelected()
        }
        status = .deviceSelected
    }

    func startCollection() async {
        guard status == .deviceSelected || status == .stopped else { return }
        guard let provider = adapter.heartRateStreamProvider() else { return }

        totalSamplesReceived = 0
        latestHeartRateSample = nil

        do {
            try await adapter.connect()
        } catch {
            status = .deviceSelected
            return
        }

        let session = CollectionSession(
            device: adapter.deviceIdentity,
            metadata: .init(
                mode: defaultCollectionMode,
                startedAt: Date(),
                collectorID: "ios-collector"
            )
        )

        activeSession = session
        preparedSessionBoundary = transport.prepareSessionBoundary(
            session: session,
            streamTypes: adapter.availableStreams
        )

        let streamType = provider.streamType
        provider.start { [weak self] sample in
            guard let self else { return }
            Task { @MainActor in
                self.handle(sample: sample, stream: streamType)
            }
        }

        status = .collecting
    }

    func stopCollection() {
        adapter.heartRateStreamProvider()?.stop()
        adapter.disconnect()
        activeSession = nil
        status = selectedDevice == nil ? .disconnected : .stopped
    }

    private func handle(sample: HeartRateSample, stream: CollectorStream) {
        latestHeartRateSample = sample
        totalSamplesReceived += 1

        if let session = activeSession {
            lastPreparedChunkBoundary = transport.prepareChunkBoundary(
                session: session,
                stream: stream,
                sequenceNumber: totalSamplesReceived,
                sampleCount: totalSamplesReceived
            )
        }
    }
}
