import Foundation

@MainActor
final class CollectorCore: ObservableObject {
    @Published private(set) var status: CollectorStatus = .disconnected
    @Published private(set) var selectedDevice: CollectorDevice?
    @Published private(set) var activeSession: CollectionSession?
    @Published private(set) var streamDescriptor: StreamDescriptor?
    @Published private(set) var latestHeartRateSample: HeartRateSample?
    @Published private(set) var totalSamplesReceived: Int = 0
    @Published private(set) var bufferedSamplesCount: Int = 0
    @Published private(set) var lastPreparedChunk: UploadChunk?

    let defaultCollectionMode: CollectionMode = .live

    private let adapter: CollectorDeviceAdapter
    private let transport: CollectorTransporting
    private var bufferedSamples: [HeartRateSample] = []
    private var nextChunkSequenceNumber: Int = 1

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
        bufferedSamples = []
        bufferedSamplesCount = 0
        nextChunkSequenceNumber = 1
        latestHeartRateSample = nil
        lastPreparedChunk = nil

        do {
            try await adapter.connect()
        } catch {
            status = .deviceSelected
            return
        }

        let session = CollectionSession(
            device: adapter.deviceIdentity,
            collectionMode: defaultCollectionMode,
            startedAtUTC: Date(),
            supportedStreams: adapter.availableStreams
        )

        activeSession = session
        streamDescriptor = transport.makeStreamDescriptor(for: provider.streamType, source: "mock")

        provider.start { [weak self] sample in
            guard let self else { return }
            Task { @MainActor in
                self.handle(sample: sample)
            }
        }

        status = .collecting
    }

    func stopCollection() {
        adapter.heartRateStreamProvider()?.stop()
        adapter.disconnect()
        if activeSession != nil {
            activeSession?.markStopped(at: Date())
        }
        status = selectedDevice == nil ? .disconnected : .stopped
    }

    @discardableResult
    func prepareUploadChunk() -> UploadChunk? {
        guard
            let session = activeSession,
            let streamDescriptor,
            !bufferedSamples.isEmpty
        else {
            return nil
        }

        let chunk = transport.prepareUploadChunk(
            session: session,
            streamDescriptor: streamDescriptor,
            chunkSequenceNumber: nextChunkSequenceNumber,
            samples: bufferedSamples
        )

        if let chunk {
            lastPreparedChunk = chunk
            nextChunkSequenceNumber += 1
            bufferedSamples.removeAll()
            bufferedSamplesCount = 0
        }

        return chunk
    }

    private func handle(sample: HeartRateSample) {
        latestHeartRateSample = sample
        totalSamplesReceived += 1
        bufferedSamples.append(sample)
        bufferedSamplesCount = bufferedSamples.count
    }
}
