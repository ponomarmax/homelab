import Foundation

@MainActor
final class CollectorCore: ObservableObject {
    private enum FlushTrigger: Equatable {
        case manual
        case sampleCount
        case timer
        case finalOnStop
    }

    private enum CoreLogLevel: String {
        case debug = "DEBUG"
        case info = "INFO"
        case warning = "WARN"
        case error = "ERROR"
    }

    @Published private(set) var status: CollectorStatus = .disconnected
    @Published private(set) var uploadStatus: UploadStatus = .idle
    @Published private(set) var discoveredDevices: [CollectorDevice] = []
    @Published private(set) var selectedDevice: CollectorDevice?
    @Published private(set) var activeSession: CollectionSession?
    @Published private(set) var streamDescriptor: StreamDescriptor?
    @Published private(set) var latestHeartRateSample: HeartRateSample?
    @Published private(set) var totalSamplesReceived: Int = 0
    @Published private(set) var bufferedSamplesCount: Int = 0
    @Published private(set) var pendingUploadChunksCount: Int = 0
    @Published private(set) var lastPreparedChunk: UploadChunk?
    @Published private(set) var debugExportFileURL: URL?
    @Published private(set) var logExportFileURL: URL?
    @Published private(set) var lastErrorMessage: String?
    @Published private(set) var shouldSuggestLogExport: Bool = false
    @Published private(set) var isScanningDevices: Bool = false
    @Published private(set) var isConnectingDevice: Bool = false
    @Published private(set) var isPreparingChunk: Bool = false
    @Published private(set) var isUploadingChunk: Bool = false
    @Published private(set) var activityMessage: String = "Idle"
    @Published private(set) var eventLogs: [String] = []

    let defaultCollectionMode: CollectionMode = .live

    private let adapter: CollectorDeviceAdapter
    private let transport: CollectorTransporting
    private let uploadConfiguration: CollectorUploadConfiguration
    private let nowProvider: @Sendable () -> Date
    private let sleepProvider: @Sendable (UInt64) async -> Void
    private let debugExporter = HrSampleDebugExporter()
    private let isVerboseLoggingEnabled: Bool
    private var pendingUploadChunks: [UploadChunk] = []
    private var bufferedSamples: [HeartRateSample] = []
    private var nextChunkSequenceNumber: Int = 1
    private var lastFlushAtUTC: Date?
    private var autoFlushTask: Task<Void, Never>?
    private var isAutoFlushing: Bool = false

    init(
        adapter: CollectorDeviceAdapter,
        transport: CollectorTransporting,
        uploadConfiguration: CollectorUploadConfiguration = .default,
        nowProvider: @escaping @Sendable () -> Date = { Date() },
        sleepProvider: @escaping @Sendable (UInt64) async -> Void = { nanoseconds in
            try? await Task.sleep(nanoseconds: nanoseconds)
        }
    ) {
        self.adapter = adapter
        self.transport = transport
        self.uploadConfiguration = uploadConfiguration
        self.nowProvider = nowProvider
        self.sleepProvider = sleepProvider
        let environment = ProcessInfo.processInfo.environment
        self.isVerboseLoggingEnabled = environment["COLLECTOR_VERBOSE_LOGS"] == "1"
            || environment["COLLECTOR_LOG_LEVEL"]?.lowercased() == "debug"

        log("Collector initialized", category: "core")
        log("Upload target: \(transport.uploadDestinationDescription)", category: "transport")
        if !transport.isNetworkUploadConfigured {
            log(
                "Server upload endpoint is not configured. Upload uses mock mode only.",
                level: .warning,
                category: "transport"
            )
        }
    }

    deinit {
        autoFlushTask?.cancel()
    }

    var deviceActionTitle: String {
        adapter.deviceSelectionActionTitle
    }

    var uploadDestinationDescription: String {
        transport.uploadDestinationDescription
    }

    func appDidBecomeActive() {
        log("App became active", category: "lifecycle")
    }

    func appDidEnterBackground() {
        log("App moved to background", category: "lifecycle")
    }

    func selectDevice() {
        clearFailureState()
        activityMessage = "Selecting mock device..."
        log("Select device tapped")
        do {
            try adapter.selectDevice(adapter.deviceIdentity)
            selectedDevice = adapter.deviceIdentity
            if let mockAdapter = adapter as? MockDeviceAdapter {
                mockAdapter.markSelected()
            }
            status = .deviceSelected
            uploadStatus = .idle
            activityMessage = "Device selected"
            log("Device selected: \(selectedDevice?.name ?? "unknown")")
        } catch {
            selectedDevice = nil
            status = .disconnected
            uploadStatus = .idle
            reportFailure(
                userMessage: "Device selection failed: \(error.localizedDescription)",
                activity: "Device selection failed",
                technical: "Device selection failed: \(error.localizedDescription)",
                category: "device"
            )
        }
    }

    func scanAndSelectDevice() async {
        clearFailureState()
        selectedDevice = nil
        status = .disconnected
        uploadStatus = .idle
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
            uploadStatus = .idle
            reportFailure(
                userMessage: "Scan failed: \(error.localizedDescription)",
                activity: "Scan failed",
                technical: "Scan failed: \(error.localizedDescription)",
                category: "device"
            )
        }
    }

    func selectScannedDevice(_ device: CollectorDevice) {
        clearFailureState()
        activityMessage = "Selecting \(device.name)..."
        log("Selecting scanned device: \(device.name)")

        do {
            try adapter.selectDevice(device)
            selectedDevice = adapter.deviceIdentity
            status = .deviceSelected
            uploadStatus = .idle
            activityMessage = "Device selected: \(selectedDevice?.name ?? "Unknown")"
            log("Device selected: \(selectedDevice?.id ?? "unknown")")
        } catch {
            selectedDevice = nil
            status = .disconnected
            uploadStatus = .idle
            reportFailure(
                userMessage: "Device selection failed: \(error.localizedDescription)",
                activity: "Device selection failed",
                technical: "Scanned device selection failed: \(error.localizedDescription)",
                category: "device"
            )
        }
    }

    func startCollection() async {
        guard status == .deviceSelected || status == .stopped else { return }
        guard let provider = adapter.heartRateStreamProvider() else { return }
        guard selectedDevice != nil else { return }

        clearFailureState()
        uploadStatus = .idle
        isConnectingDevice = true
        activityMessage = "Connecting to device..."
        log("Start tapped")
        totalSamplesReceived = 0
        bufferedSamples = []
        bufferedSamplesCount = 0
        pendingUploadChunks = []
        pendingUploadChunksCount = 0
        nextChunkSequenceNumber = 1
        lastFlushAtUTC = nowProvider()
        latestHeartRateSample = nil
        lastPreparedChunk = nil
        debugExportFileURL = nil
        logExportFileURL = nil
        autoFlushTask?.cancel()
        startAutoFlushTask()

        do {
            try await adapter.connect()
        } catch {
            status = .deviceSelected
            isConnectingDevice = false
            reportFailure(
                userMessage: "Connection failed: \(error.localizedDescription)",
                activity: "Connection failed",
                technical: "Connection failed: \(error.localizedDescription)",
                category: "device"
            )
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
            source: adapter.sourceIdentifier
        )
        prepareDebugExport(for: session)

        provider.start { [weak self] sample in
            guard let self else { return }
            Task { @MainActor in
                await self.handle(sample: sample)
            }
        }

        status = .collecting
        activityMessage = "Collecting HR samples..."
        log("Collection started. Session: \(session.sessionID.uuidString)", category: "core")
    }

    func stopCollection() {
        log("Stop tapped")
        autoFlushTask?.cancel()
        autoFlushTask = nil
        adapter.heartRateStreamProvider()?.stop()
        adapter.disconnect()
        debugExporter.stopSession()
        if activeSession != nil {
            activeSession?.markStopped(at: Date())
        }
        status = selectedDevice == nil ? .disconnected : .stopped
        activityMessage = "Collection stopped"
        log("Collection stopped")
        if !bufferedSamples.isEmpty {
            log(
                "Final flush requested on stop, buffered samples: \(bufferedSamples.count)",
                category: "upload"
            )
            Task { @MainActor [weak self] in
                await self?.flushAndUploadBufferedSamples(trigger: .finalOnStop)
            }
        }
        if let debugExportFileURL {
            log("Export ready: \(debugExportFileURL.lastPathComponent)")
        }
    }

    @discardableResult
    func prepareUploadChunk() -> UploadChunk? {
        prepareUploadChunk(trigger: .manual)
    }

    @discardableResult
    private func prepareUploadChunk(trigger: FlushTrigger) -> UploadChunk? {
        isPreparingChunk = true
        uploadStatus = .idle
        switch trigger {
        case .manual:
            activityMessage = "Preparing upload chunk..."
            log("Prepare Chunk tapped")
        case .sampleCount:
            activityMessage = "Auto flush: sample threshold reached"
            log(
                "Auto flush triggered by sample count (\(bufferedSamples.count) >= \(uploadConfiguration.autoFlushSampleCount))",
                category: "upload"
            )
        case .timer:
            activityMessage = "Auto flush: interval reached"
            log(
                "Auto flush triggered by timer (\(Int(uploadConfiguration.autoFlushIntervalSeconds))s)",
                category: "upload"
            )
        case .finalOnStop:
            activityMessage = "Final flush on stop..."
            log("Final flush on stop triggered", category: "upload")
        }
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
            let firstSampleAt = Self.iso8601(from: chunk.samples.first?.collectorReceivedAtUTC)
            let lastSampleAt = Self.iso8601(from: chunk.samples.last?.collectorReceivedAtUTC)
            let sessionID = chunk.sessionID.uuidString.lowercased()
            pendingUploadChunks.append(chunk)
            pendingUploadChunksCount = pendingUploadChunks.count
            lastPreparedChunk = pendingUploadChunks.last
            nextChunkSequenceNumber += 1
            bufferedSamples.removeAll()
            bufferedSamplesCount = 0
            lastFlushAtUTC = nowProvider()
            activityMessage = "Chunk #\(chunk.chunkSequenceNumber) prepared (\(chunk.samples.count) samples)"
            log(
                "Chunk prepared session_id=\(sessionID) stream_type=\(chunk.streamType) sequence=\(chunk.chunkSequenceNumber) chunk_id=\(chunk.chunkID.uuidString.lowercased()) samples=\(chunk.samples.count) first_sample=\(firstSampleAt) last_sample=\(lastSampleAt) pending=\(pendingUploadChunksCount)",
                category: "upload"
            )
        } else {
            activityMessage = "Chunk preparation returned no data"
            log("Prepare returned nil chunk", level: .warning, category: "upload")
        }

        return chunk
    }

    func uploadLastPreparedChunk() async {
        guard !pendingUploadChunks.isEmpty else {
            reportFailure(
                userMessage: "No prepared chunk available",
                activity: "Nothing to upload (prepare chunk first)",
                technical: "Upload requested with empty pending queue",
                category: "upload"
            )
            uploadStatus = .failure
            return
        }

        isUploadingChunk = true
        uploadStatus = .idle
        clearFailureState()
        let firstChunk = pendingUploadChunks[0]
        let firstSampleAt = Self.iso8601(from: firstChunk.samples.first?.collectorReceivedAtUTC)
        let lastSampleAt = Self.iso8601(from: firstChunk.samples.last?.collectorReceivedAtUTC)
        activityMessage = "Uploading chunk #\(firstChunk.chunkSequenceNumber) to server..."
        let firstSessionID = firstChunk.sessionID.uuidString.lowercased()
        log(
            "Upload started session_id=\(firstSessionID) stream_type=\(firstChunk.streamType) sequence=\(firstChunk.chunkSequenceNumber) chunk_id=\(firstChunk.chunkID.uuidString.lowercased()) samples=\(firstChunk.samples.count) first_sample=\(firstSampleAt) last_sample=\(lastSampleAt) destination=\(transport.uploadDestinationDescription) pending_before=\(pendingUploadChunksCount)",
            category: "upload"
        )
        if !transport.isNetworkUploadConfigured {
            log(
                "Network upload endpoint is not configured. This upload runs in mock mode and does not send an HTTP request.",
                level: .warning,
                category: "upload"
            )
        }
        defer {
            isUploadingChunk = false
        }

        var uploadedCount = 0

        while let chunk = pendingUploadChunks.first {
            do {
                let ack = try await transport.upload(chunk: chunk)
                pendingUploadChunks.removeFirst()
                pendingUploadChunksCount = pendingUploadChunks.count
                lastPreparedChunk = pendingUploadChunks.last
                uploadedCount += 1
                uploadStatus = .success
                activityMessage = "Uploaded \(uploadedCount) chunk(s). Pending: \(pendingUploadChunksCount)"
                let uploadedFirstSampleAt = Self.iso8601(from: chunk.samples.first?.collectorReceivedAtUTC)
                let uploadedLastSampleAt = Self.iso8601(from: chunk.samples.last?.collectorReceivedAtUTC)
                let sessionID = chunk.sessionID.uuidString.lowercased()
                log(
                    "Upload succeeded session_id=\(sessionID) stream_type=\(chunk.streamType) sequence=\(chunk.chunkSequenceNumber) chunk_id=\(chunk.chunkID.uuidString.lowercased()) samples=\(chunk.samples.count) first_sample=\(uploadedFirstSampleAt) last_sample=\(uploadedLastSampleAt) ack_status=\(ack.status) accepted=\(ack.accepted) pending_after=\(pendingUploadChunksCount) message=\(ack.message ?? "none")",
                    category: "upload"
                )
            } catch {
                uploadStatus = .failure
                let message = error.localizedDescription
                reportFailure(
                    userMessage: "Upload failed: \(message)",
                    activity: "Upload failed after \(uploadedCount) success(es). Pending: \(pendingUploadChunksCount)",
                    technical: "Upload failed session_id=\(chunk.sessionID.uuidString.lowercased()) stream_type=\(chunk.streamType) sequence=\(chunk.chunkSequenceNumber) chunk_id=\(chunk.chunkID.uuidString.lowercased()) error=\(message). Chunk kept in pending queue for retry.",
                    category: "upload"
                )
                return
            }
        }
    }

    private func handle(sample: HeartRateSample) async {
        latestHeartRateSample = sample
        totalSamplesReceived += 1
        bufferedSamples.append(sample)
        bufferedSamplesCount = bufferedSamples.count
        if totalSamplesReceived == 1 {
            log("First HR sample received: \(sample.hrBPM) bpm", category: "samples")
        } else if totalSamplesReceived.isMultiple(of: 25) {
            log("HR samples received: \(totalSamplesReceived)", level: .debug, category: "samples")
        }

        if let sessionID = activeSession?.sessionID {
            debugExporter.appendSample(
                sessionID: sessionID,
                sample: sample
            )
        }

        if status == .collecting, bufferedSamples.count >= uploadConfiguration.autoFlushSampleCount {
            await flushAndUploadBufferedSamples(trigger: .sampleCount)
        }
    }

    private func startAutoFlushTask() {
        autoFlushTask = Task { @MainActor [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                await self.sleepProvider(1_000_000_000)
                guard !Task.isCancelled else { return }
                guard self.status == .collecting else { continue }
                guard !self.bufferedSamples.isEmpty else { continue }
                guard let lastFlushAtUTC else { continue }

                let elapsed = self.nowProvider().timeIntervalSince(lastFlushAtUTC)
                if elapsed >= self.uploadConfiguration.autoFlushIntervalSeconds {
                    await self.flushAndUploadBufferedSamples(trigger: .timer)
                }
            }
        }
    }

    private func flushAndUploadBufferedSamples(trigger: FlushTrigger) async {
        guard !isAutoFlushing else { return }
        guard !bufferedSamples.isEmpty else { return }

        isAutoFlushing = true
        defer { isAutoFlushing = false }

        var currentTrigger = trigger
        while !bufferedSamples.isEmpty {
            if currentTrigger == .sampleCount, bufferedSamples.count < uploadConfiguration.autoFlushSampleCount {
                return
            }

            guard prepareUploadChunk(trigger: currentTrigger) != nil else { return }
            await uploadLastPreparedChunk()

            guard status == .collecting else { return }
            guard bufferedSamples.count >= uploadConfiguration.autoFlushSampleCount else { return }
            currentTrigger = .sampleCount
        }
    }

    func prepareLogExportFile() {
        guard !eventLogs.isEmpty else {
            reportFailure(
                userMessage: "No logs available for export",
                activity: "No logs to export",
                technical: "Log export skipped: no logs",
                category: "logging"
            )
            return
        }

        let fileName = "collector-events-\(Self.logFileDateFormatter.string(from: Date())).log"
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        let payload = eventLogs.joined(separator: "\n") + "\n"

        do {
            try payload.write(to: fileURL, atomically: true, encoding: .utf8)
            logExportFileURL = fileURL
            activityMessage = "Log export ready"
            log("Log export created: \(fileURL.lastPathComponent)", category: "logging")
        } catch {
            reportFailure(
                userMessage: "Failed to export logs: \(error.localizedDescription)",
                activity: "Log export failed",
                technical: "Failed to export logs: \(error.localizedDescription)",
                category: "logging"
            )
        }
    }

    private func clearFailureState() {
        lastErrorMessage = nil
        shouldSuggestLogExport = false
    }

    private func reportFailure(
        userMessage: String,
        activity: String,
        technical: String,
        category: String
    ) {
        lastErrorMessage = userMessage
        activityMessage = activity
        shouldSuggestLogExport = true
        log(technical, level: .error, category: category)
    }

    private func log(
        _ message: String,
        level: CoreLogLevel = .info,
        category: String = "core"
    ) {
        if level == .debug && !isVerboseLoggingEnabled {
            return
        }

        let timestamp = Self.logTimestampFormatter.string(from: Date())
        let line = "[\(timestamp)] [\(level.rawValue)] [\(category)] \(message)"
        print(line)
        eventLogs.append(line)
        if eventLogs.count > 1000 {
            eventLogs.removeFirst(eventLogs.count - 1000)
        }
    }

    private static let logTimestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    private static let logFileDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter
    }()

    private static let uploadIso8601Formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }()

    private static func iso8601(from date: Date?) -> String {
        guard let date else { return "n/a" }
        return uploadIso8601Formatter.string(from: date)
    }

    private func prepareDebugExport(for session: CollectionSession) {
        debugExportFileURL = debugExporter.startSession(sessionID: session.sessionID)
        if let debugExportFileURL {
            log("Raw export file created: \(debugExportFileURL.lastPathComponent)", category: "export")
            activityMessage = "Collecting and writing JSONL export"
        } else {
            reportFailure(
                userMessage: "Failed to create JSONL export file",
                activity: "Export file creation failed",
                technical: "Failed to create JSONL export file",
                category: "export"
            )
        }
    }
}
