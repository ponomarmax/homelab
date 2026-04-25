import Foundation

@MainActor
final class CollectorCore: ObservableObject {
    @Published private(set) var status: CollectorStatus = .disconnected
    @Published private(set) var discoveredDevices: [CollectorDevice] = []
    @Published private(set) var selectedDevice: CollectorDevice?
    @Published private(set) var activeSession: CollectionSession?
    @Published private(set) var streamDescriptor: StreamDescriptor?
    @Published private(set) var latestHeartRateSample: HeartRateSample?
    @Published private(set) var totalSamplesReceived: Int = 0
    @Published private(set) var bufferedSamplesCount: Int = 0
    @Published private(set) var lastPreparedChunk: UploadChunk?
    @Published private(set) var debugExportFileURL: URL?
    @Published private(set) var lastErrorMessage: String?
    @Published private(set) var isScanningDevices: Bool = false
    @Published private(set) var isConnectingDevice: Bool = false
    @Published private(set) var isPreparingChunk: Bool = false
    @Published private(set) var activityMessage: String = "Idle"
    @Published private(set) var eventLogs: [String] = []

    let defaultCollectionMode: CollectionMode = .live

    private let adapter: CollectorDeviceAdapter
    private let transport: CollectorTransporting
    private let debugExporter = HrSampleDebugExporter()
    private var bufferedSamples: [HeartRateSample] = []
    private var nextChunkSequenceNumber: Int = 1

    init(
        adapter: CollectorDeviceAdapter,
        transport: CollectorTransporting
    ) {
        self.adapter = adapter
        self.transport = transport
        log("Collector initialized")
    }

    var deviceActionTitle: String {
        adapter is PolarDeviceAdapter ? "Scan Polar Devices" : "Select Mock Device"
    }

    func selectDevice() {
        lastErrorMessage = nil
        activityMessage = "Selecting mock device..."
        log("Select device tapped")
        do {
            try adapter.selectDevice(adapter.deviceIdentity)
            selectedDevice = adapter.deviceIdentity
            if let mockAdapter = adapter as? MockDeviceAdapter {
                mockAdapter.markSelected()
            }
            status = .deviceSelected
            activityMessage = "Device selected"
            log("Device selected: \(selectedDevice?.name ?? "unknown")")
        } catch {
            selectedDevice = nil
            status = .disconnected
            lastErrorMessage = "Device selection failed: \(error.localizedDescription)"
            activityMessage = "Device selection failed"
            log("Device selection failed: \(error.localizedDescription)")
        }
    }

    func scanAndSelectDevice() async {
        lastErrorMessage = nil
        selectedDevice = nil
        status = .disconnected
        isScanningDevices = true
        activityMessage = "Scanning for Polar devices..."
        log("Scan started")
        defer {
            isScanningDevices = false
        }

        do {
            let devices = try await adapter.scanDevices()
            discoveredDevices = devices
            log("Scan finished: found \(devices.count) device(s)")

            if let mockAdapter = adapter as? MockDeviceAdapter, let first = devices.first {
                try mockAdapter.selectDevice(first)
                selectedDevice = first
                status = .deviceSelected
                activityMessage = "Mock device selected"
                log("Mock device auto-selected: \(first.name)")
                return
            }

            if devices.isEmpty {
                lastErrorMessage = "No Polar devices found"
                activityMessage = "No devices found"
            } else {
                lastErrorMessage = "Select a device from the list below"
                activityMessage = "Select device from list"
            }
        } catch {
            discoveredDevices = []
            selectedDevice = nil
            status = .disconnected
            lastErrorMessage = "Scan failed: \(error.localizedDescription)"
            activityMessage = "Scan failed"
            log("Scan failed: \(error.localizedDescription)")
        }
    }

    func selectScannedDevice(_ device: CollectorDevice) {
        lastErrorMessage = nil
        activityMessage = "Selecting \(device.name)..."
        log("Selecting scanned device: \(device.name)")

        do {
            try adapter.selectDevice(device)
            selectedDevice = adapter.deviceIdentity
            status = .deviceSelected
            activityMessage = "Device selected: \(selectedDevice?.name ?? "Unknown")"
            log("Device selected: \(selectedDevice?.id ?? "unknown")")
        } catch {
            selectedDevice = nil
            status = .disconnected
            lastErrorMessage = "Device selection failed: \(error.localizedDescription)"
            activityMessage = "Device selection failed"
            log("Device selection failed: \(error.localizedDescription)")
        }
    }

    func startCollection() async {
        guard status == .deviceSelected || status == .stopped else { return }
        guard let provider = adapter.heartRateStreamProvider() else { return }
        guard selectedDevice != nil else { return }

        lastErrorMessage = nil
        isConnectingDevice = true
        activityMessage = "Connecting to device..."
        log("Start tapped")
        totalSamplesReceived = 0
        bufferedSamples = []
        bufferedSamplesCount = 0
        nextChunkSequenceNumber = 1
        latestHeartRateSample = nil
        lastPreparedChunk = nil
        debugExportFileURL = nil

        do {
            try await adapter.connect()
        } catch {
            status = .deviceSelected
            lastErrorMessage = "Connection failed: \(error.localizedDescription)"
            isConnectingDevice = false
            activityMessage = "Connection failed"
            log("Connection failed: \(error.localizedDescription)")
            return
        }
        isConnectingDevice = false

        let session = CollectionSession(
            device: adapter.deviceIdentity,
            collectionMode: defaultCollectionMode,
            startedAtUTC: Date(),
            supportedStreams: adapter.availableStreams
        )

        activeSession = session
        streamDescriptor = transport.makeStreamDescriptor(
            for: provider.streamType,
            source: adapter is PolarDeviceAdapter ? "polar" : "mock"
        )
        prepareDebugExport(for: session)

        provider.start { [weak self] sample in
            guard let self else { return }
            Task { @MainActor in
                self.handle(sample: sample)
            }
        }

        status = .collecting
        activityMessage = "Collecting HR samples..."
        log("Collection started. Session: \(session.sessionID.uuidString)")
    }

    func stopCollection() {
        log("Stop tapped")
        adapter.heartRateStreamProvider()?.stop()
        adapter.disconnect()
        debugExporter.stopSession()
        if activeSession != nil {
            activeSession?.markStopped(at: Date())
        }
        status = selectedDevice == nil ? .disconnected : .stopped
        activityMessage = "Collection stopped"
        log("Collection stopped")
        if let debugExportFileURL {
            log("Export ready: \(debugExportFileURL.lastPathComponent)")
        }
    }

    @discardableResult
    func prepareUploadChunk() -> UploadChunk? {
        isPreparingChunk = true
        activityMessage = "Preparing upload chunk..."
        log("Prepare Chunk tapped")
        defer {
            isPreparingChunk = false
        }

        guard
            let session = activeSession,
            let streamDescriptor,
            !bufferedSamples.isEmpty
        else {
            activityMessage = "Nothing to prepare (no buffered samples)"
            log("Prepare skipped: no buffered samples")
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
            activityMessage = "Chunk #\(chunk.chunkSequenceNumber) prepared (\(chunk.samples.count) samples)"
            log("Prepared chunk #\(chunk.chunkSequenceNumber), samples: \(chunk.samples.count)")
        } else {
            activityMessage = "Chunk preparation returned no data"
            log("Prepare returned nil chunk")
        }

        return chunk
    }

    private func handle(sample: HeartRateSample) {
        latestHeartRateSample = sample
        totalSamplesReceived += 1
        bufferedSamples.append(sample)
        bufferedSamplesCount = bufferedSamples.count
        if totalSamplesReceived == 1 {
            log("First HR sample received: \(sample.hrBPM) bpm")
        } else if totalSamplesReceived.isMultiple(of: 25) {
            log("HR samples received: \(totalSamplesReceived)")
        }

        if let sessionID = activeSession?.sessionID {
            debugExporter.appendSample(
                sessionID: sessionID,
                sample: sample
            )
        }
    }

    private func log(_ message: String) {
        let timestamp = Self.logTimestampFormatter.string(from: Date())
        let line = "[\(timestamp)] \(message)"
        print(line)
        eventLogs.append(line)
        if eventLogs.count > 200 {
            eventLogs.removeFirst(eventLogs.count - 200)
        }
    }

    private static let logTimestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    private func prepareDebugExport(for session: CollectionSession) {
        debugExportFileURL = debugExporter.startSession(sessionID: session.sessionID)
        if let debugExportFileURL {
            log("Export file created: \(debugExportFileURL.lastPathComponent)")
            activityMessage = "Collecting and writing JSONL export"
        } else {
            lastErrorMessage = "Failed to create JSONL export file"
            activityMessage = "Export file creation failed"
            log("Failed to create JSONL export file")
        }
    }
}
