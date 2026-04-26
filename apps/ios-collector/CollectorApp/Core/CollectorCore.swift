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
    private var bufferedSamplesByStream: [CollectorStream: [HeartRateSample]] = [:]
    private var streamDescriptorsByType: [CollectorStream: StreamDescriptor] = [:]
    private var nextChunkSequenceNumberByStream: [CollectorStream: Int] = [:]
    private var lastFlushAtUTCByStream: [CollectorStream: Date] = [:]
    private var activeProviders: [HeartRateStreamProviding] = []

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
        guard selectedDevice != nil else { return }

        clearFailureState()
        uploadStatus = .idle
        isConnectingDevice = true
        activityMessage = "Connecting to device..."
        log("Start tapped")

        totalSamplesReceived = 0
        bufferedSamplesByStream.removeAll()
        bufferedSamplesCount = 0
        pendingUploadChunks = []
        pendingUploadChunksCount = 0
        nextChunkSequenceNumberByStream.removeAll()
        lastFlushAtUTCByStream.removeAll()
        latestHeartRateSample = nil
        lastPreparedChunk = nil
        debugExportFileURL = nil
        logExportFileURL = nil
        streamDescriptorsByType.removeAll()

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

        let providers = adapter.streamProviders()
        guard !providers.isEmpty else {
            status = .deviceSelected
            reportFailure(
                userMessage: "No stream providers available for selected device",
                activity: "Cannot start collection",
                technical: "Start blocked after connect: streamProviders() returned empty",
                category: "core"
            )
            return
        }

        let session = CollectionSession(
            device: adapter.deviceIdentity,
            collectionMode: defaultCollectionMode,
            startedAtUTC: Date(),
            supportedStreams: adapter.availableStreams
        )

        activeProviders = providers
        activeSession = session

        for provider in providers {
            streamDescriptorsByType[provider.streamType] = transport.makeStreamDescriptor(
                for: provider.streamType,
                source: adapter.sourceIdentifier
            )
            nextChunkSequenceNumberByStream[provider.streamType] = 1
            lastFlushAtUTCByStream[provider.streamType] = nowProvider()
            log("Stream provider prepared: \(provider.streamType.transportType)", category: "core")
        }

        streamDescriptor = streamDescriptorsByType[.heartRate] ?? providers.first.flatMap { streamDescriptorsByType[$0.streamType] }
        prepareDebugExport(for: session)

        let streamStartPriority: [CollectorStream] = [.battery, .heartRate, .ecg, .accelerometer, .ppi, .eeg]
        let orderedProviders = providers.sorted {
            let leftIndex = streamStartPriority.firstIndex(of: $0.streamType) ?? Int.max
            let rightIndex = streamStartPriority.firstIndex(of: $1.streamType) ?? Int.max
            return leftIndex < rightIndex
        }

        for provider in orderedProviders {
            provider.start { [weak self] sample in
                guard let self else { return }
                Task { @MainActor in
                    await self.handle(sample: sample)
                }
            }
            // Start streams in sequence to avoid PMD control-point contention on device startup.
            if provider.streamType == .heartRate || provider.streamType == .ecg {
                await sleepProvider(350_000_000)
            }
        }

        status = .collecting
        activityMessage = "Collecting live streams..."
        log("Collection started. Session: \(session.sessionID.uuidString)", category: "core")
    }

    func stopCollection() {
        log("Stop tapped")
        autoFlushTask?.cancel()
        autoFlushTask = nil

        activeProviders.forEach { $0.stop() }
        activeProviders.removeAll()

        adapter.disconnect()
        debugExporter.stopSession()
        if activeSession != nil {
            activeSession?.markStopped(at: Date())
        }
        status = selectedDevice == nil ? .disconnected : .stopped
        activityMessage = "Collection stopped"
        log("Collection stopped")

        if bufferedSamplesCount > 0 {
            log(
                "Final flush requested on stop, buffered samples: \(bufferedSamplesCount)",
                category: "upload"
            )
            Task { @MainActor [weak self] in
                await self?.flushAndUploadAllBufferedSamples(trigger: .finalOnStop)
            }
        }

        if let debugExportFileURL {
            log("Export ready: \(debugExportFileURL.lastPathComponent)")
        }
    }

    @discardableResult
    func prepareUploadChunk() -> UploadChunk? {
        guard let stream = firstBufferedStream() else {
            activityMessage = "Nothing to prepare (no buffered samples)"
            log("Prepare skipped: no buffered samples")
            return nil
        }
        return prepareUploadChunk(for: stream, trigger: .manual)
    }

    @discardableResult
    private func prepareUploadChunk(for stream: CollectorStream, trigger: FlushTrigger) -> UploadChunk? {
        isPreparingChunk = true
        uploadStatus = .idle

        let streamLabel = stream.transportType
        switch trigger {
        case .manual:
            activityMessage = "Preparing \(streamLabel) chunk..."
            log("Prepare Chunk tapped for stream=\(streamLabel)")
        case .sampleCount:
            activityMessage = "Auto flush: \(streamLabel) threshold reached"
            log(
                "Auto flush triggered by sample count for stream=\(streamLabel)",
                category: "upload"
            )
        case .timer:
            activityMessage = "Auto flush: interval reached for \(streamLabel)"
            log(
                "Auto flush triggered by timer for stream=\(streamLabel)",
                category: "upload"
            )
        case .finalOnStop:
            activityMessage = "Final flush on stop (\(streamLabel))..."
            log("Final flush on stop triggered for stream=\(streamLabel)", category: "upload")
        }
        defer {
            isPreparingChunk = false
        }

        guard
            let session = activeSession,
            let streamDescriptor = streamDescriptorsByType[stream],
            let streamSamples = bufferedSamplesByStream[stream],
            !streamSamples.isEmpty
        else {
            activityMessage = "Nothing to prepare (no buffered samples)"
            log("Prepare skipped: no buffered samples for stream=\(streamLabel)")
            return nil
        }

        let streamProfile = uploadConfiguration.streamProfile(for: stream)
        let chunkSequenceNumber = nextChunkSequenceNumberByStream[stream] ?? 1

        let chunk = transport.prepareUploadChunk(
            session: session,
            streamDescriptor: streamDescriptor,
            streamProfile: streamProfile,
            chunkSequenceNumber: chunkSequenceNumber,
            samples: streamSamples
        )

        if let chunk {
            let firstSampleAt = Self.iso8601(from: chunk.samples.first?.collectorReceivedAtUTC)
            let lastSampleAt = Self.iso8601(from: chunk.samples.last?.collectorReceivedAtUTC)
            let sessionID = chunk.sessionID.uuidString.lowercased()
            pendingUploadChunks.append(chunk)
            pendingUploadChunksCount = pendingUploadChunks.count
            lastPreparedChunk = pendingUploadChunks.last

            nextChunkSequenceNumberByStream[stream] = chunkSequenceNumber + 1
            bufferedSamplesByStream[stream] = []
            bufferedSamplesCount = bufferedSampleTotalCount()
            lastFlushAtUTCByStream[stream] = nowProvider()
            self.streamDescriptor = streamDescriptor

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
        if sample.stream == .heartRate {
            latestHeartRateSample = sample
        }

        totalSamplesReceived += 1

        var streamSamples = bufferedSamplesByStream[sample.stream] ?? []
        streamSamples.append(sample)
        bufferedSamplesByStream[sample.stream] = streamSamples
        bufferedSamplesCount = bufferedSampleTotalCount()

        if totalSamplesReceived == 1 {
            log("First sample received for stream=\(sample.stream.transportType)", category: "samples")
        } else if totalSamplesReceived.isMultiple(of: 25) {
            log("Samples received total: \(totalSamplesReceived)", level: .debug, category: "samples")
        }

        if let sessionID = activeSession?.sessionID {
            debugExporter.appendSample(
                sessionID: sessionID,
                sample: sample
            )
        }

        if status == .collecting {
            let flushCount = uploadConfiguration.sampleFlushCount(for: sample.stream)
            if streamSamples.count >= flushCount {
                await flushAndUploadBufferedSamples(
                    for: sample.stream,
                    trigger: .sampleCount,
                    enforceThreshold: true
                )
            }
        }
    }

    private func startAutoFlushTask() {
        autoFlushTask = Task { @MainActor [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                await self.sleepProvider(1_000_000_000)
                guard !Task.isCancelled else { return }
                guard self.status == .collecting else { continue }
                guard self.bufferedSamplesCount > 0 else { continue }

                for stream in self.streamFlushOrder() {
                    guard let streamSamples = self.bufferedSamplesByStream[stream], !streamSamples.isEmpty else {
                        continue
                    }
                    guard let lastFlushAtUTC = self.lastFlushAtUTCByStream[stream] else { continue }

                    let elapsed = self.nowProvider().timeIntervalSince(lastFlushAtUTC)
                    if elapsed >= self.uploadConfiguration.autoFlushIntervalSeconds {
                        await self.flushAndUploadBufferedSamples(
                            for: stream,
                            trigger: .timer,
                            enforceThreshold: false
                        )
                    }
                }
            }
        }
    }

    private func flushAndUploadAllBufferedSamples(trigger: FlushTrigger) async {
        for stream in streamFlushOrder() {
            await flushAndUploadBufferedSamples(
                for: stream,
                trigger: trigger,
                enforceThreshold: false
            )
        }
    }

    private func flushAndUploadBufferedSamples(
        for stream: CollectorStream,
        trigger: FlushTrigger,
        enforceThreshold: Bool
    ) async {
        guard !isAutoFlushing else { return }
        guard let buffered = bufferedSamplesByStream[stream], !buffered.isEmpty else { return }

        isAutoFlushing = true
        defer { isAutoFlushing = false }

        var currentTrigger = trigger

        while let currentBuffered = bufferedSamplesByStream[stream], !currentBuffered.isEmpty {
            let threshold = uploadConfiguration.sampleFlushCount(for: stream)
            if enforceThreshold && currentBuffered.count < threshold {
                return
            }

            guard prepareUploadChunk(for: stream, trigger: currentTrigger) != nil else { return }
            await uploadLastPreparedChunk()

            if status != .collecting && trigger != .finalOnStop {
                return
            }

            guard let remaining = bufferedSamplesByStream[stream], !remaining.isEmpty else { return }

            if trigger == .sampleCount {
                guard remaining.count >= threshold else { return }
                currentTrigger = .sampleCount
                continue
            }

            if trigger == .timer || trigger == .finalOnStop {
                currentTrigger = trigger
                continue
            }

            return
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

    private func bufferedSampleTotalCount() -> Int {
        bufferedSamplesByStream.values.reduce(0) { $0 + $1.count }
    }

    private func streamFlushOrder() -> [CollectorStream] {
        [
            .heartRate,
            .ecg,
            .accelerometer,
            .battery,
            .ppi,
            .eeg
        ]
    }

    private func firstBufferedStream() -> CollectorStream? {
        streamFlushOrder().first { stream in
            let samples = bufferedSamplesByStream[stream] ?? []
            return !samples.isEmpty
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
