import Foundation

enum ManagedSessionOrigin: String, Codable, Sendable {
    case ourApp = "our_app"
    case externalApp = "external_app"
    case unknown = "unknown"
}

enum ManagedSessionLifecycle: String, Codable, Sendable {
    case started
    case stopped
    case stoppedExternal
    case uploaded
    case partiallyUploaded
    case orphaned
}

struct ManagedSessionFile: Codable, Equatable, Hashable, Sendable {
    let path: String
    let stream: String
    let startedAtUTC: Date?
    let sizeBytes: UInt?
}

struct ManagedSessionRecord: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let clientSessionID: String
    let deviceID: String
    let deviceType: String
    let collectionMode: CollectionMode
    var origin: ManagedSessionOrigin
    var lifecycle: ManagedSessionLifecycle
    let startedAtUTC: Date
    var stoppedAtUTC: Date?
    var linkedFiles: [ManagedSessionFile]
    var notes: String?
}

struct SessionManifestPayload: Codable, Equatable, Sendable {
    struct Collector: Codable, Equatable, Sendable {
        let collectorID: String
        let runtimeType: String
        let appVersion: String
        let buildVersion: String?

        enum CodingKeys: String, CodingKey {
            case collectorID = "collector_id"
            case runtimeType = "runtime_type"
            case appVersion = "app_version"
            case buildVersion = "build_version"
        }
    }

    struct Device: Codable, Equatable, Sendable {
        let vendor: String
        let model: String
        let deviceID: String

        enum CodingKeys: String, CodingKey {
            case vendor
            case model
            case deviceID = "device_id"
        }
    }

    struct Time: Codable, Equatable, Sendable {
        let startedAtSource: String
        let startedAtServer: String?

        enum CodingKeys: String, CodingKey {
            case startedAtSource = "started_at_source"
            case startedAtServer = "started_at_server"
        }
    }

    struct Metadata: Codable, Equatable, Sendable {
        let notes: String?
        let tags: [String]?
    }

    let schemaVersion: String
    let sessionID: String
    let deviceSessionID: String?
    let sessionMode: String
    let collector: Collector
    let device: Device
    let time: Time
    let metadata: Metadata?

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case sessionID = "session_id"
        case deviceSessionID = "device_session_id"
        case sessionMode = "session_mode"
        case collector
        case device
        case time
        case metadata
    }
}

struct PendingSessionManifest: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let sessionID: UUID
    let clientSessionID: String
    var lastError: String?
    var retryCount: Int
    var updatedAtUTC: Date
}

private struct ManagedSessionSnapshot: Codable {
    var sessions: [ManagedSessionRecord]
    var pendingManifests: [PendingSessionManifest]

    enum CodingKeys: String, CodingKey {
        case sessions
        case pendingManifests
    }

    init(sessions: [ManagedSessionRecord], pendingManifests: [PendingSessionManifest]) {
        self.sessions = sessions
        self.pendingManifests = pendingManifests
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sessions = try container.decodeIfPresent([ManagedSessionRecord].self, forKey: .sessions) ?? []
        pendingManifests = try container.decodeIfPresent([PendingSessionManifest].self, forKey: .pendingManifests) ?? []
    }
}

@MainActor
final class SessionLedgerStore {
    private let storageURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(fileManager: FileManager = .default) {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let dir = appSupport.appendingPathComponent("CollectorApp", isDirectory: true)
        if !fileManager.fileExists(atPath: dir.path) {
            try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        self.storageURL = dir.appendingPathComponent("session-ledger.json")
        self.encoder = JSONEncoder()
        self.encoder.dateEncodingStrategy = .iso8601
        self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.decoder = JSONDecoder()
        self.decoder.dateDecodingStrategy = .iso8601
    }

    func loadSessions() -> [ManagedSessionRecord] {
        guard let data = try? Data(contentsOf: storageURL) else { return [] }
        guard let snapshot = try? decoder.decode(ManagedSessionSnapshot.self, from: data) else { return [] }
        return snapshot.sessions.sorted { $0.startedAtUTC > $1.startedAtUTC }
    }

    func loadPendingManifests() -> [PendingSessionManifest] {
        guard let data = try? Data(contentsOf: storageURL) else { return [] }
        guard let snapshot = try? decoder.decode(ManagedSessionSnapshot.self, from: data) else { return [] }
        return snapshot.pendingManifests.sorted { $0.updatedAtUTC > $1.updatedAtUTC }
    }

    func save(sessions: [ManagedSessionRecord], pendingManifests: [PendingSessionManifest]) {
        let snapshot = ManagedSessionSnapshot(
            sessions: sessions.sorted { $0.startedAtUTC > $1.startedAtUTC },
            pendingManifests: pendingManifests.sorted { $0.updatedAtUTC > $1.updatedAtUTC }
        )
        guard let data = try? encoder.encode(snapshot) else { return }
        try? data.write(to: storageURL, options: .atomic)
    }
}

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
    @Published private(set) var latestDeviceStatusSnapshot: DeviceStatusSnapshot?
    @Published private(set) var discoveredDeviceStatusByID: [String: DeviceStatusSnapshot] = [:]
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
    @Published private(set) var selectedOnlineStreams: Set<CollectorStream> = []
    @Published private(set) var selectedOfflineStreams: Set<PolarOfflineStream> = []
    @Published private(set) var offlineLifecycleState: OfflineLifecycleState = .notLoaded
    @Published private(set) var offlineStatusMessage: String = "Disconnected"
    @Published private(set) var offlineStreamCapabilities: [PolarOfflineStream: OfflineStreamCapability] = [:]
    @Published private(set) var offlineSettingsByStream: [PolarOfflineStream: OfflineStreamSettings] = [:]
    @Published private(set) var offlineSettingsLoadStateByStream: [PolarOfflineStream: OfflineSettingsLoadState] = [:]
    @Published private(set) var offlineStreamRunMessages: [PolarOfflineStream: String] = [:]
    @Published private(set) var offlineStreamRunStates: [PolarOfflineStream: OfflineStreamRunState] = [:]
    @Published private(set) var offlineRecoveredStateByStream: [PolarOfflineStream: OfflineStreamRecoveredState] = [:]
    @Published private(set) var offlineRecordings: [OfflineRecordingEntry] = []
    @Published private(set) var offlineOperation: OfflineOperation = .none
    @Published private(set) var offlineIsOperationRunning: Bool = false
    @Published private(set) var offlineLastSuccessAction: String = "None"
    @Published private(set) var offlineLastErrorMessage: String?
    @Published private(set) var offlineRecordErrorsByID: [String: String] = [:]
    @Published private(set) var deletingOfflineRecordingIDs: Set<String> = []
    @Published private(set) var unassignedOfflineRecordings: [OfflineRecordingEntry] = []
    @Published private(set) var unassignedRecordingGroups: [UnassignedRecordingGroup] = []
    @Published private(set) var deviceTimeSyncState: DeviceTimeSyncState = .idle
    @Published private(set) var deviceTimeStatusMessage: String = "Not synced"
    @Published private(set) var deviceTimeDebugDetails: String = "Stream timestamp verification not performed"
    @Published private(set) var lastDeviceTimeReadResult: String = "Not synced"
    @Published private(set) var lastDeviceTimeSyncResult: String = "Not synced"
    @Published private(set) var lastDeviceTimeDeltaSeconds: TimeInterval?
    @Published private(set) var operationalTimeEvents: [DeviceTimeOperationalEvent] = []
    @Published private(set) var managedSessions: [ManagedSessionRecord] = []
    @Published private(set) var pendingSessionManifests: [PendingSessionManifest] = []
    @Published private(set) var isManifestSyncRunning: Bool = false
    @Published private(set) var manifestSyncStatusMessage: String = "Idle"

    let defaultCollectionMode: CollectionMode = .live

    private let adapter: CollectorDeviceAdapter
    private let transport: CollectorTransporting
    private let uploadConfiguration: CollectorUploadConfiguration
    private let nowProvider: @Sendable () -> Date
    private let sleepProvider: @Sendable (UInt64) async -> Void
    private let debugExporter = HrSampleDebugExporter()
    private let sessionLedgerStore = SessionLedgerStore()
    private let isVerboseLoggingEnabled: Bool
    private let unassignedClusterGapSeconds: TimeInterval
    private let isManifestAutoRetryEnabled: Bool
    private let manifestRetryBatchSize: Int

    private var pendingUploadChunks: [UploadChunk] = []
    private var bufferedSamplesByStream: [CollectorStream: [HeartRateSample]] = [:]
    private var pendingTimeContextByStream: [CollectorStream: UploadChunkTimeContext] = [:]
    private var streamDescriptorsByType: [CollectorStream: StreamDescriptor] = [:]
    private var nextChunkSequenceNumberByStream: [CollectorStream: Int] = [:]
    private var lastFlushAtUTCByStream: [CollectorStream: Date] = [:]
    private var activeProviders: [HeartRateStreamProviding] = []
    private var latestStatusByDeviceID: [String: DeviceStatusSnapshot] = [:]

    private var autoFlushTask: Task<Void, Never>?
    private var isAutoFlushing: Bool = false
    private var consecutiveUploadFailureCount: Int = 0
    private var nextUploadRetryAtUTC: Date?

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
        self.unassignedClusterGapSeconds = TimeInterval(environment["COLLECTOR_UNASSIGNED_CLUSTER_GAP_SECONDS"] ?? "") ?? 180
        self.isManifestAutoRetryEnabled = environment["COLLECTOR_MANIFEST_AUTO_RETRY"] == "1"
        self.manifestRetryBatchSize = max(1, Int(environment["COLLECTOR_MANIFEST_RETRY_BATCH_SIZE"] ?? "") ?? 3)
        self.managedSessions = sessionLedgerStore.loadSessions()
        self.pendingSessionManifests = sessionLedgerStore.loadPendingManifests()
        refreshUnassignedRecordingGroups()

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

    var polarCapabilities: PolarDeviceProfile {
        PolarDeviceProfile.from(
            device: selectedDevice,
            availableOnlineStreams: adapter.availableStreams,
            supportsManualTimeSync: adapter.deviceTimeAvailability.canSyncDeviceTime
        )
    }

    var deviceTimeAvailability: DeviceTimeActionAvailability {
        adapter.deviceTimeAvailability
    }

    func selectedDeviceBatteryDisplayText() -> String {
        guard let selectedDevice else {
            return "unknown"
        }
        return batteryDisplayText(for: selectedDevice.id)
    }

    func batteryDisplayText(for deviceID: String) -> String {
        let snapshot = latestStatusByDeviceID[deviceID] ?? adapter.cachedDeviceStatusSnapshot(for: deviceID)
        if let snapshot {
            return formatBattery(snapshot.status.battery)
        }

        if let batteryCapability = adapter.deviceStatusCapabilities.first(where: { $0.kind == .battery }) {
            guard batteryCapability.isSupported else {
                return "unsupported"
            }
            return batteryCapability.requiresConnection ? "available after connection" : "unknown"
        }

        return "unknown"
    }

    func connectability(for device: CollectorDevice) -> DeviceConnectability {
        adapter.connectability(for: device)
    }

    func appDidBecomeActive() {
        log("App became active", category: "lifecycle")
        reconcileOpenSessionsAfterLifecycleEvent()
        refreshUnassignedRecordingGroups()
        guard isManifestAutoRetryEnabled else { return }
        Task { @MainActor [weak self] in
            await self?.retryPendingSessionManifestSync()
        }
    }

    func appDidEnterBackground() {
        log("App moved to background", category: "lifecycle")
    }

    func readDeviceTime() async {
        deviceTimeSyncState = .running
        deviceTimeStatusMessage = "Syncing device time..."
        let result = await adapter.readDeviceTime(mode: .live)
        applyDeviceTimeActionResult(result, isSyncAction: false)
    }

    func syncDeviceTimeToPhoneNow() async {
        deviceTimeSyncState = .running
        deviceTimeStatusMessage = "Syncing device time..."
        let result = await adapter.syncDeviceTimeToPhone(mode: .live)
        applyDeviceTimeActionResult(result, isSyncAction: true)
    }

    func runPreOfflineSyncTimeCheck() async -> DeviceTimeActionResult {
        deviceTimeSyncState = .running
        deviceTimeStatusMessage = "Syncing device time..."
        let result = await adapter.prepareDeviceTimeForOfflineSync()
        applyDeviceTimeActionResult(result, isSyncAction: true)
        return result
    }

    func selectDevice() {
        clearFailureState()
        activityMessage = "Selecting mock device..."
        log("Select device tapped")
        do {
            try adapter.selectDevice(adapter.deviceIdentity)
            selectedDevice = adapter.deviceIdentity
            refreshCachedStatus(for: adapter.deviceIdentity.id)
            status = .deviceSelected
            selectedOnlineStreams = Set(adapter.availableStreams)
            selectedOfflineStreams = Set(polarCapabilities.availableOfflineStreams)
            offlineStreamCapabilities = [:]
            offlineSettingsByStream = [:]
            offlineSettingsLoadStateByStream = [:]
            offlineStreamRunMessages = [:]
            offlineRecordings = []
            offlineLifecycleState = .disconnected
            offlineStatusMessage = "Connect to use offline recording"
            offlineSettingsByStream = [:]
            offlineSettingsLoadStateByStream = [:]
            uploadStatus = .idle
            activityMessage = "Device selected"
            log("Device selected: \(selectedDevice?.name ?? "unknown")")
        } catch {
            selectedDevice = nil
            latestDeviceStatusSnapshot = nil
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
        latestDeviceStatusSnapshot = nil
        status = .disconnected
        uploadStatus = .idle
        isScanningDevices = true
        activityMessage = "Scanning for Polar devices..."
        log("Scan started")
        defer {
            isScanningDevices = false
        }

        do {
            let devices = try await adapter.scanDevices { [weak self] progressive in
                Task { @MainActor in
                    self?.discoveredDevices = progressive
                    self?.refreshCachedStatuses(for: progressive)
                }
            }
            discoveredDevices = devices
            refreshCachedStatuses(for: devices)
            log("Scan finished: found \(devices.count) device(s)")

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
            latestDeviceStatusSnapshot = nil
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
            refreshCachedStatus(for: adapter.deviceIdentity.id)
            status = .deviceSelected
            selectedOnlineStreams = Set(adapter.availableStreams)
            selectedOfflineStreams = Set(polarCapabilities.availableOfflineStreams)
            offlineLifecycleState = .disconnected
            offlineStatusMessage = "Connect to use offline recording"
            uploadStatus = .idle
            activityMessage = "Device selected: \(selectedDevice?.name ?? "Unknown")"
            log("Device selected: \(selectedDevice?.id ?? "unknown")")
        } catch {
            selectedDevice = nil
            latestDeviceStatusSnapshot = nil
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

    func connectSelectedDevice() async {
        guard status == .deviceSelected || status == .stopped else { return }
        guard let selectedDevice else { return }
        let connectability = adapter.connectability(for: selectedDevice)
        guard connectability.isConnectable else {
            reportFailure(
                userMessage: connectability.reason ?? "Device is not connectable",
                activity: "Cannot connect selected device",
                technical: "Connect blocked: \(connectability.reason ?? "unknown reason")",
                category: "device"
            )
            return
        }

        clearFailureState()
        isConnectingDevice = true
        activityMessage = "Connecting to device..."

        do {
            try await adapter.connect()
            status = .connected
            activityMessage = "Connected"
            await recoverOfflineStateAfterReconnect()
        } catch {
            status = .deviceSelected
            reportFailure(
                userMessage: "Connection failed: \(error.localizedDescription)",
                activity: "Connection failed",
                technical: "Connection failed: \(error.localizedDescription)",
                category: "device"
            )
        }
        isConnectingDevice = false
    }

    func startCollection() async {
        guard status == .deviceSelected || status == .connected || status == .stopped else { return }
        guard let selectedDevice else { return }
        refreshCachedStatus(for: selectedDevice.id)

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
        consecutiveUploadFailureCount = 0
        nextUploadRetryAtUTC = nil
        latestHeartRateSample = nil
        lastPreparedChunk = nil
        debugExportFileURL = nil
        logExportFileURL = nil
        streamDescriptorsByType.removeAll()

        autoFlushTask?.cancel()
        startAutoFlushTask()

        if adapter.connectionState != .connected {
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
        }
        isConnectingDevice = false

        let providers = adapter.streamProviders().filter { selectedOnlineStreams.contains($0.streamType) }
        guard !providers.isEmpty else {
            status = .deviceSelected
            reportFailure(
                userMessage: "No online streams selected or available for selected device",
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
        upsertManagedSession(
            id: session.sessionID,
            clientSessionID: session.clientSessionID,
            mode: session.collectionMode,
            origin: .ourApp,
            lifecycle: .started,
            startedAtUTC: session.startedAtUTC,
            stoppedAtUTC: nil,
            linkedFiles: [],
            notes: "started_in_app"
        )

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

    func disconnectDevice() {
        stopCollection()
        selectedDevice = nil
        latestDeviceStatusSnapshot = nil
        discoveredDevices = []
        status = .disconnected
        offlineLifecycleState = .disconnected
        offlineStatusMessage = "Disconnected"
    }

    func toggleOnlineStream(_ stream: CollectorStream) {
        guard status != .collecting else { return }
        guard adapter.availableStreams.contains(stream) else { return }
        if selectedOnlineStreams.contains(stream) {
            selectedOnlineStreams.remove(stream)
        } else {
            selectedOnlineStreams.insert(stream)
        }
    }

    func toggleOfflineStream(_ stream: PolarOfflineStream) {
        guard let capability = offlineStreamCapabilities[stream], capability.isSupported else { return }
        if selectedOfflineStreams.contains(stream) {
            selectedOfflineStreams.remove(stream)
        } else {
            selectedOfflineStreams.insert(stream)
        }
    }

    func capabilityForOfflineStream(_ stream: PolarOfflineStream) -> OfflineStreamCapability {
        if let capability = offlineStreamCapabilities[stream] {
            return capability
        }
        let isSupported = polarCapabilities.availableOfflineStreams.contains(stream)
        return OfflineStreamCapability(
            stream: stream,
            isSupported: isSupported,
            reason: isSupported ? nil : "Unsupported"
        )
    }

    func refreshOfflineCapabilities() async {
        let capabilities = await adapter.offlineCapabilities()
        offlineStreamCapabilities = Dictionary(uniqueKeysWithValues: capabilities.map { ($0.stream, $0) })
        let supported = capabilities.filter(\.isSupported).map(\.stream)
        selectedOfflineStreams = Set(selectedOfflineStreams.filter { supported.contains($0) })
        if selectedOfflineStreams.isEmpty {
            selectedOfflineStreams = Set(supported)
        }
        if adapter.connectionState != .connected {
            offlineLifecycleState = .disconnected
            offlineStatusMessage = "Device disconnected"
            return
        }
        if supported.isEmpty {
            offlineLifecycleState = .featureUnavailable
            offlineStatusMessage = capabilities.first(where: { !$0.isSupported })?.reason ?? "Offline recording unavailable"
        } else {
            offlineLifecycleState = .ready
            offlineStatusMessage = "Ready"
            for stream in supported {
                if offlineStreamRunStates[stream] == nil {
                    offlineStreamRunStates[stream] = .ready
                }
                if offlineSettingsLoadStateByStream[stream] == nil {
                    offlineSettingsLoadStateByStream[stream] = .notLoaded
                }
            }
        }
        updateRecoveredStates()
    }

    func recoverOfflineStateAfterReconnect() async {
        offlineLifecycleState = .refreshing
        offlineStatusMessage = "Refreshing device offline state..."
        offlineLastErrorMessage = nil

        let capabilities = await adapter.offlineCapabilities()
        offlineStreamCapabilities = Dictionary(uniqueKeysWithValues: capabilities.map { ($0.stream, $0) })
        let supportedStreams = Set(capabilities.filter(\.isSupported).map(\.stream))

        let statusByStream = await adapter.offlineRecordingStatus()
        for stream in PolarOfflineStream.allCases {
            let capability = offlineStreamCapabilities[stream]
            let status = statusByStream[stream] ?? .unknown
            if capability?.isSupported == false {
                offlineStreamRunStates[stream] = .unavailable
                offlineStreamRunMessages[stream] = capability?.reason ?? "Unsupported"
                continue
            }
            switch status {
            case .recording:
                offlineStreamRunStates[stream] = .recording
                offlineStreamRunMessages[stream] = "Recording"
            case .ready:
                offlineStreamRunStates[stream] = .ready
                offlineStreamRunMessages[stream] = "Ready"
            case .unavailable:
                offlineStreamRunStates[stream] = .unavailable
                offlineStreamRunMessages[stream] = "Unavailable"
            case .failed:
                offlineStreamRunStates[stream] = .failed
                offlineStreamRunMessages[stream] = "Failed"
            case .unknown:
                offlineStreamRunStates[stream] = .unknown
                offlineStreamRunMessages[stream] = "Unknown"
            }
        }

        if selectedOfflineStreams.isEmpty {
            selectedOfflineStreams = supportedStreams
        } else {
            selectedOfflineStreams = Set(selectedOfflineStreams.filter { supportedStreams.contains($0) })
        }

        do {
            offlineRecordings = try await adapter.listOfflineRecordings()
        } catch {
            offlineLastErrorMessage = "Listing failed during reconnect refresh: \(error.localizedDescription)"
        }

        for stream in supportedStreams where offlineSettingsLoadStateByStream[stream] == nil {
            offlineSettingsLoadStateByStream[stream] = .notLoaded
        }

        updateRecoveredStates()
        let hasRecording = offlineRecoveredStateByStream.values.contains(where: { $0.isRecording })
        let hasFailedStream = offlineRecoveredStateByStream.values.contains(where: { $0.status == .failed || $0.status == .unknown })
        if hasRecording {
            offlineLifecycleState = .recoveredRecording
            offlineStatusMessage = "Device already has active offline recordings. State restored after reconnect."
        } else if hasFailedStream {
            offlineLifecycleState = .failed
            offlineStatusMessage = "Failed to refresh offline state"
        } else if supportedStreams.isEmpty {
            offlineLifecycleState = .featureUnavailable
            offlineStatusMessage = capabilities.first(where: { !$0.isSupported })?.reason ?? "Offline recording unavailable"
        } else {
            offlineLifecycleState = .ready
            offlineStatusMessage = "Ready"
        }
    }

    func offlineSettingsSummary(for stream: PolarOfflineStream) -> String {
        if let settings = offlineSettingsByStream[stream] {
            return settings.selected.summary()
        }
        switch offlineSettingsLoadStateByStream[stream] ?? .notLoaded {
        case .notLoaded:
            return "Not loaded"
        case .loading:
            return "Loading..."
        case .ready:
            return "Ready"
        case .failed(let message):
            return "Failed: \(message)"
        }
    }

    func canConfigureOfflineStream(_ stream: PolarOfflineStream) -> Bool {
        guard let capability = offlineStreamCapabilities[stream], capability.isSupported else { return false }
        if let settings = offlineSettingsByStream[stream] {
            return settings.options.isConfigurable
        }
        return true
    }

    func loadOfflineSettings(for stream: PolarOfflineStream) async {
        guard let capability = offlineStreamCapabilities[stream], capability.isSupported else { return }
        offlineSettingsLoadStateByStream[stream] = .loading
        offlineStreamRunStates[stream] = .loadingSettings
        offlineStreamRunMessages[stream] = "Loading settings..."
        let result = await adapter.offlineRecordingSettings(for: stream)
        switch result {
        case .success(let settings):
            offlineSettingsByStream[stream] = settings
            offlineSettingsLoadStateByStream[stream] = .ready
            offlineStreamRunStates[stream] = .ready
            offlineStreamRunMessages[stream] = settings.options.isConfigurable ? "Settings ready" : "No configurable settings"
        case .failure(let failure):
            let message = failure.message
            offlineSettingsLoadStateByStream[stream] = .failed(message: message)
            offlineStreamRunStates[stream] = .failed
            offlineStreamRunMessages[stream] = "Settings failed: \(message)"
        }
    }

    func updateOfflineSettingsSelection(
        for stream: PolarOfflineStream,
        sampleRate: UInt32?,
        resolution: UInt32?,
        range: UInt32?,
        channels: UInt32?
    ) {
        guard let existing = offlineSettingsByStream[stream] else { return }
        let selection = OfflineStreamSettingsSelection(
            sampleRate: sampleRate,
            resolution: resolution,
            range: range,
            channels: channels
        )
        let updated = OfflineStreamSettings(stream: stream, options: existing.options, selected: selection)
        offlineSettingsByStream[stream] = updated
        adapter.updateOfflineRecordingSettingsSelection(selection, for: stream)
    }

    var offlineProgressSummary: String {
        let all = PolarOfflineStream.allCases
        let failed = all.filter { offlineStreamRunStates[$0] == .failed }.count
        let recording = all.filter { offlineStreamRunStates[$0] == .recording }.count
        let uploaded = all.filter { offlineStreamRunStates[$0] == .uploaded }.count
        return "recording: \(recording), uploaded: \(uploaded), failed: \(failed)"
    }

    func isOfflineActionDisabled(_ action: OfflineOperation) -> Bool {
        if action == .uploading && hasActiveOfflineRecording() {
            return true
        }
        if action == .deleting && hasActiveOfflineRecording() {
            return true
        }
        guard offlineIsOperationRunning else { return false }
        return offlineOperation != action
    }

    func canStartOfflineSelected() -> Bool {
        selectedOfflineStreams.contains { stream in
            guard capabilityForOfflineStream(stream).isSupported else { return false }
            return offlineStreamRunStates[stream] != .recording
        }
    }

    func canStopOfflineSelected() -> Bool {
        selectedOfflineStreams.contains { offlineStreamRunStates[$0] == .recording }
    }

    func startOfflineSelected() async {
        await startOffline(streams: selectedOfflineStreams.sorted { $0.rawValue < $1.rawValue })
    }

    func startOfflineAllSupported() async {
        let streams = offlineStreamCapabilities.values.filter(\.isSupported).map(\.stream).sorted { $0.rawValue < $1.rawValue }
        await startOffline(streams: streams)
    }

    func stopOfflineSelected() async {
        await stopOffline(streams: selectedOfflineStreams.sorted { $0.rawValue < $1.rawValue })
    }

    func stopOfflineAllSupported() async {
        let streams = offlineStreamCapabilities.values.filter(\.isSupported).map(\.stream).sorted { $0.rawValue < $1.rawValue }
        await stopOffline(streams: streams)
        await uploadOfflineRecordings()
    }

    func listOfflineRecordings() async {
        guard beginOfflineOperation(.listing, lifecycle: .listing, statusMessage: "Listing offline recordings...") else { return }
        defer { completeOfflineOperation() }
        guard adapter.connectionState == .connected else {
            offlineLifecycleState = .disconnected
            offlineStatusMessage = "Device disconnected"
            offlineLastErrorMessage = "Device disconnected"
            return
        }
        do {
            let entries = try await adapter.listOfflineRecordings()
            offlineRecordings = entries
            refreshUnassignedRecordingGroups()
            offlineLifecycleState = .completed
            offlineStatusMessage = entries.isEmpty ? "No recordings found" : "Loaded \(entries.count) recording(s)"
            offlineLastSuccessAction = "Listed offline recordings"
        } catch {
            offlineLifecycleState = .failed
            offlineStatusMessage = "List failed: \(error.localizedDescription)"
            offlineLastErrorMessage = offlineStatusMessage
        }
    }

    func refreshOfflineData() async {
        await refreshOfflineCapabilities()
        await listOfflineRecordings()
        refreshUnassignedRecordingGroups()
    }

    func assignUnassignedAsSingleSession() {
        guard !unassignedOfflineRecordings.isEmpty else { return }
        createExternalManagedSession(from: unassignedOfflineRecordings, note: "manual_merge_single_session")
        refreshUnassignedRecordingGroups()
    }

    func assignUnassignedByClusters() {
        guard !unassignedRecordingGroups.isEmpty else { return }
        for group in unassignedRecordingGroups where !group.entries.isEmpty {
            createExternalManagedSession(from: group.entries, note: "manual_split_by_time_cluster")
        }
        refreshUnassignedRecordingGroups()
    }

    func assignVisibleRecordingsAsSingleSession() {
        let candidates = unassignedRecordings(from: offlineRecordings)
        guard !candidates.isEmpty else {
            offlineLastErrorMessage = "All visible recordings are already assigned to sessions"
            return
        }
        createExternalManagedSession(from: candidates, note: "manual_merge_visible_recordings")
        refreshUnassignedRecordingGroups()
    }

    func assignVisibleRecordingsByClusters() {
        let candidates = unassignedRecordings(from: offlineRecordings)
        let clusters = clusterUnassignedRecordings(candidates)
        guard !clusters.isEmpty else { return }
        for group in clusters where !group.entries.isEmpty {
            createExternalManagedSession(from: group.entries, note: "manual_split_visible_recordings_by_cluster")
        }
        refreshUnassignedRecordingGroups()
    }

    func pendingManifest(for sessionID: UUID) -> PendingSessionManifest? {
        pendingSessionManifests.first(where: { $0.sessionID == sessionID })
    }

    func removePendingManifest(id: String) {
        pendingSessionManifests.removeAll { $0.id == id }
        persistLedger()
    }

    func deleteManagedSession(id: UUID) {
        managedSessions.removeAll { $0.id == id }
        pendingSessionManifests.removeAll { $0.sessionID == id }
        persistLedger()
        refreshUnassignedRecordingGroups()
    }

    func retryPendingManifest(for sessionID: UUID) async {
        guard !isManifestSyncRunning else { return }
        guard transport.isNetworkUploadConfigured else {
            manifestSyncStatusMessage = "Network upload is not configured"
            return
        }
        guard let session = managedSessions.first(where: { $0.id == sessionID }) else { return }
        guard let pending = pendingSessionManifests.first(where: { $0.sessionID == sessionID }) else { return }

        isManifestSyncRunning = true
        manifestSyncStatusMessage = "Syncing manifest for \(session.clientSessionID)..."
        defer {
            isManifestSyncRunning = false
            persistLedger()
        }

        do {
            let payload = buildSessionManifestPayload(from: session)
            _ = try await transport.uploadSessionManifest(payload)
            pendingSessionManifests.removeAll { $0.id == pending.id }
            manifestSyncStatusMessage = "Manifest synced for \(session.clientSessionID)"
        } catch {
            if let index = pendingSessionManifests.firstIndex(where: { $0.id == pending.id }) {
                pendingSessionManifests[index].retryCount += 1
                pendingSessionManifests[index].lastError = error.localizedDescription
                pendingSessionManifests[index].updatedAtUTC = nowProvider()
            }
            manifestSyncStatusMessage = "Manifest sync failed for \(session.clientSessionID)"
        }
    }

    func uploadOfflineRecordings() async {
        guard beginOfflineOperation(.uploading, lifecycle: .uploading, statusMessage: "Uploading offline recordings...") else { return }
        defer { completeOfflineOperation() }
        guard adapter.connectionState == .connected else {
            offlineLifecycleState = .disconnected
            offlineStatusMessage = "Device disconnected"
            offlineLastErrorMessage = "Device disconnected"
            return
        }

        offlineStatusMessage = "Fetching offline recordings..."
        for stream in selectedOfflineStreams {
            offlineStreamRunStates[stream] = .fetching
        }
        let preparation = await adapter.prepareOfflineUploadBatches(allowedPaths: nil)
        offlineStreamRunMessages.merge(
            preparation.messagesByStream,
            uniquingKeysWith: { _, new in new }
        )

        guard !preparation.batches.isEmpty else {
            offlineLifecycleState = .failed
            offlineStatusMessage = "No offline recordings were prepared for upload"
            offlineLastErrorMessage = offlineStatusMessage
            return
        }

        ensureUploadSessionIfNeeded(for: preparation.batches.map(\.stream))
        if let session = activeSession {
            let files = preparation.batches.map {
                ManagedSessionFile(
                    path: $0.sourcePath,
                    stream: $0.stream.transportType,
                    startedAtUTC: $0.timeContext?.recordingStartUTC,
                    sizeBytes: nil
                )
            }
            linkFilesToManagedSession(id: session.sessionID, files: files)
        }

        for batch in preparation.batches {
            var samples = bufferedSamplesByStream[batch.stream] ?? []
            samples.append(contentsOf: batch.samples)
            bufferedSamplesByStream[batch.stream] = samples
            if let context = batch.timeContext {
                pendingTimeContextByStream[batch.stream] = context
            }
        }
        bufferedSamplesCount = bufferedSampleTotalCount()

        offlineStatusMessage = "Uploading chunks..."
        for stream in selectedOfflineStreams {
            offlineStreamRunStates[stream] = .uploading
        }
        await flushAndUploadAllBufferedSamples(trigger: .manual)
        if uploadStatus == .success {
            offlineLifecycleState = .completed
            offlineStatusMessage = "Offline recordings uploaded"
            offlineLastSuccessAction = "Uploaded offline recordings"
            if let session = activeSession {
                updateManagedSessionLifecycle(
                    id: session.sessionID,
                    lifecycle: .uploaded,
                    stoppedAtUTC: session.stoppedAtUTC,
                    notes: "offline_upload_success"
                )
            }
            for stream in selectedOfflineStreams {
                offlineStreamRunStates[stream] = .uploaded
            }
        } else if uploadStatus == .failure {
            offlineLifecycleState = .failed
            offlineStatusMessage = "Offline upload failed"
            offlineLastErrorMessage = offlineStatusMessage
            if let session = activeSession {
                updateManagedSessionLifecycle(
                    id: session.sessionID,
                    lifecycle: .partiallyUploaded,
                    stoppedAtUTC: session.stoppedAtUTC,
                    notes: "offline_upload_failed"
                )
            }
            for stream in selectedOfflineStreams {
                offlineStreamRunStates[stream] = .failed
            }
        } else {
            offlineLifecycleState = .partialSuccess
            offlineStatusMessage = "Offline upload completed with mixed result"
        }
    }

    func uploadManagedSession(_ id: UUID) async {
        guard let session = managedSessions.first(where: { $0.id == id }) else { return }
        let allowedPaths = Set(session.linkedFiles.map(\.path))
        guard !allowedPaths.isEmpty else {
            offlineLastErrorMessage = "Session has no linked files to upload"
            return
        }
        log("Session upload requested: \(session.clientSessionID) files=\(allowedPaths.count)", category: "session")

        guard beginOfflineOperation(.uploading, lifecycle: .uploading, statusMessage: "Uploading session...") else { return }
        defer { completeOfflineOperation() }

        let preparation = await adapter.prepareOfflineUploadBatches(allowedPaths: allowedPaths)
        let streamsPrepared = preparation.batches.map(\.stream.transportType).joined(separator: ",")
        log(
            "Session upload preparation result: batches=\(preparation.batches.count) streams=[\(streamsPrepared)] messages=\(preparation.messagesByStream)",
            category: "session"
        )
        guard !preparation.batches.isEmpty else {
            offlineLifecycleState = .failed
            offlineStatusMessage = "No batches prepared for selected session"
            offlineLastErrorMessage = offlineStatusMessage
            return
        }

        activeSession = CollectionSession(
            sessionID: session.id,
            device: adapter.deviceIdentity,
            collectionMode: session.collectionMode,
            startedAtUTC: session.startedAtUTC,
            stoppedAtUTC: session.stoppedAtUTC,
            supportedStreams: adapter.availableStreams
        )

        for batch in preparation.batches {
            if streamDescriptorsByType[batch.stream] == nil {
                streamDescriptorsByType[batch.stream] = transport.makeStreamDescriptor(
                    for: batch.stream,
                    source: adapter.sourceIdentifier
                )
            }
            if nextChunkSequenceNumberByStream[batch.stream] == nil {
                nextChunkSequenceNumberByStream[batch.stream] = 1
            }
            if lastFlushAtUTCByStream[batch.stream] == nil {
                lastFlushAtUTCByStream[batch.stream] = nowProvider()
            }
            var samples = bufferedSamplesByStream[batch.stream] ?? []
            samples.append(contentsOf: batch.samples)
            bufferedSamplesByStream[batch.stream] = samples
            if let context = batch.timeContext {
                pendingTimeContextByStream[batch.stream] = context
            }
        }
        bufferedSamplesCount = bufferedSampleTotalCount()
        await flushAndUploadAllBufferedSamples(trigger: .manual)
        if uploadStatus == .success {
            updateManagedSessionLifecycle(
                id: session.id,
                lifecycle: .uploaded,
                stoppedAtUTC: session.stoppedAtUTC,
                notes: "session_upload_success"
            )
        } else if uploadStatus == .failure {
            updateManagedSessionLifecycle(
                id: session.id,
                lifecycle: .partiallyUploaded,
                stoppedAtUTC: session.stoppedAtUTC,
                notes: "session_upload_failed"
            )
        }
    }

    func deleteOfflineRecording(_ entry: OfflineRecordingEntry) async {
        guard !isUploadingChunk else {
            offlineLastErrorMessage = "Cannot delete while upload is running"
            return
        }
        guard beginOfflineOperation(.deleting, lifecycle: .deleting, statusMessage: "Deleting offline recording...") else { return }
        deletingOfflineRecordingIDs.insert(entry.id)
        defer {
            deletingOfflineRecordingIDs.remove(entry.id)
            completeOfflineOperation()
        }
        do {
            try await adapter.removeOfflineRecording(path: entry.path)
            offlineRecordings.removeAll { $0.id == entry.id }
            refreshUnassignedRecordingGroups()
            offlineRecordErrorsByID[entry.id] = nil
            offlineLifecycleState = .completed
            offlineStatusMessage = "Deleted recording"
            offlineLastSuccessAction = "Deleted offline recording"
        } catch {
            let message = "Delete failed: \(error.localizedDescription)"
            offlineRecordErrorsByID[entry.id] = message
            offlineLifecycleState = .failed
            offlineStatusMessage = message
            offlineLastErrorMessage = message
        }
    }

    func deleteAllOfflineRecordings(confirmed: Bool) async {
        guard confirmed else {
            offlineLastErrorMessage = "Delete all recordings requires confirmation"
            return
        }
        guard !isUploadingChunk else {
            offlineLastErrorMessage = "Cannot delete while upload is running"
            return
        }
        guard beginOfflineOperation(.deleting, lifecycle: .deleting, statusMessage: "Deleting all offline recordings...") else { return }
        defer { completeOfflineOperation() }
        guard adapter.connectionState == .connected else {
            offlineLifecycleState = .disconnected
            offlineStatusMessage = "Device disconnected"
            offlineLastErrorMessage = "Device disconnected"
            return
        }

        let entries: [OfflineRecordingEntry]
        do {
            entries = try await adapter.listOfflineRecordings()
        } catch {
            offlineLifecycleState = .failed
            offlineStatusMessage = "List failed: \(error.localizedDescription)"
            offlineLastErrorMessage = offlineStatusMessage
            return
        }

        if entries.isEmpty {
            offlineLifecycleState = .completed
            offlineStatusMessage = "No recordings to delete"
            offlineLastSuccessAction = "Deleted all offline recordings"
            offlineRecordings = []
            refreshUnassignedRecordingGroups()
            return
        }

        var deletedIDs = Set<String>()
        var failed: [String] = []

        for (index, entry) in entries.enumerated() {
            deletingOfflineRecordingIDs.insert(entry.id)
            offlineStatusMessage = "Deleting recording \(index + 1)/\(entries.count)..."
            do {
                try await adapter.removeOfflineRecording(path: entry.path)
                deletedIDs.insert(entry.id)
                offlineRecordErrorsByID[entry.id] = nil
            } catch {
                let message = "Delete failed: \(error.localizedDescription)"
                offlineRecordErrorsByID[entry.id] = message
                failed.append(entry.path)
            }
            deletingOfflineRecordingIDs.remove(entry.id)
        }

        offlineRecordings.removeAll { deletedIDs.contains($0.id) }
        refreshUnassignedRecordingGroups()
        if failed.isEmpty {
            offlineLifecycleState = .completed
            offlineStatusMessage = "Deleted \(entries.count) recording(s)"
            offlineLastSuccessAction = "Deleted all offline recordings"
            return
        }

        offlineLifecycleState = .partialSuccess
        let successCount = entries.count - failed.count
        offlineStatusMessage = "Deleted \(successCount)/\(entries.count) recording(s)"
        offlineLastErrorMessage = "Failed to delete \(failed.count) recording(s)"
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
            if let session = activeSession {
                updateManagedSessionLifecycle(
                    id: session.sessionID,
                    lifecycle: .stopped,
                    stoppedAtUTC: session.stoppedAtUTC,
                    notes: "stopped_in_app"
                )
            }
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

        let streamProfile = resolvedStreamProfile(for: stream, session: session)
        let chunkSequenceNumber = nextChunkSequenceNumberByStream[stream] ?? 1

        let chunk = transport.prepareUploadChunk(
            session: session,
            streamDescriptor: streamDescriptor,
            streamProfile: streamProfile,
            chunkSequenceNumber: chunkSequenceNumber,
            samples: streamSamples,
            timeContext: resolveChunkTimeContext(for: stream, session: session)
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
            pendingTimeContextByStream[stream] = nil
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

    private func resolveChunkTimeContext(for stream: CollectorStream, session: CollectionSession) -> UploadChunkTimeContext {
        if let pending = pendingTimeContextByStream[stream] {
            return pending
        }

        let now = nowProvider()
        let timezoneOffsetMinutes = TimeZone.current.secondsFromGMT(for: now) / 60
        let clockSyncState: String
        switch deviceTimeSyncState {
        case .success:
            clockSyncState = "synced"
        case .failed:
            clockSyncState = "unsynced"
        case .idle, .running, .unavailable:
            clockSyncState = "unknown"
        }

        return UploadChunkTimeContext(
            recordingStartUTC: session.startedAtUTC,
            recordingEndUTC: session.stoppedAtUTC,
            fileCreatedAtDevice: nil,
            fileClosedAtDevice: nil,
            deviceLocalTimeAtFetch: now,
            deviceTimezoneOffset: timezoneOffsetMinutes,
            clockSyncState: clockSyncState,
            clockDriftEstimate: nil,
            sourceAppOrigin: session.collectionMode == .offlineRecording ? "unknown" : "our_app",
            sensorRecordingID: nil,
            fetchStartedAtCollector: now,
            fetchCompletedAtCollector: now
        )
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
                consecutiveUploadFailureCount = 0
                nextUploadRetryAtUTC = nil
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
                consecutiveUploadFailureCount += 1
                let retryDelay = uploadConfiguration.retry.nextDelaySeconds(forAttempt: consecutiveUploadFailureCount)
                nextUploadRetryAtUTC = nowProvider().addingTimeInterval(retryDelay)
                let message = error.localizedDescription
                reportFailure(
                    userMessage: "Upload failed: \(message)",
                    activity: "Upload failed after \(uploadedCount) success(es). Pending: \(pendingUploadChunksCount)",
                    technical: "Upload failed session_id=\(chunk.sessionID.uuidString.lowercased()) stream_type=\(chunk.streamType) sequence=\(chunk.chunkSequenceNumber) chunk_id=\(chunk.chunkID.uuidString.lowercased()) error=\(message). Chunk kept in pending queue for retry.",
                    category: "upload"
                )
                if let nextUploadRetryAtUTC {
                    log(
                        "Retry scheduled in \(Int(retryDelay))s at \(Self.iso8601(from: nextUploadRetryAtUTC))",
                        level: .warning,
                        category: "upload"
                    )
                }
                return
            }
        }
    }

    private func handle(sample: HeartRateSample) async {
        if sample.stream == .heartRate {
            latestHeartRateSample = sample
        }
        if let batteryData = sample.batteryData {
            updateBatteryStatus(
                from: batteryData,
                deviceID: selectedDevice?.id ?? activeSession?.deviceID,
                timestamp: sample.collectorReceivedAtUTC
            )
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

        if status == .collecting, let flushCount = uploadConfiguration.sampleFlushCount(for: sample.stream) {
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

                if !self.pendingUploadChunks.isEmpty,
                   !self.isUploadingChunk,
                   self.shouldRetryPendingUploads(now: self.nowProvider()) {
                    self.log("Retrying pending chunks (\(self.pendingUploadChunks.count))", category: "upload")
                    await self.uploadLastPreparedChunk()
                }

                guard self.bufferedSamplesCount > 0 else { continue }

                for stream in self.streamFlushOrder() {
                    guard let streamSamples = self.bufferedSamplesByStream[stream], !streamSamples.isEmpty else {
                        continue
                    }
                    guard let lastFlushAtUTC = self.lastFlushAtUTCByStream[stream] else { continue }

                    let elapsed = self.nowProvider().timeIntervalSince(lastFlushAtUTC)
                    if elapsed >= self.uploadConfiguration.uploadFlushIntervalSeconds {
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
            if enforceThreshold, let threshold, currentBuffered.count < threshold {
                return
            }

            guard prepareUploadChunk(for: stream, trigger: currentTrigger) != nil else { return }
            await uploadLastPreparedChunk()

            if status != .collecting && trigger != .finalOnStop {
                return
            }

            guard let remaining = bufferedSamplesByStream[stream], !remaining.isEmpty else { return }

            if trigger == .sampleCount {
                guard let threshold else { return }
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

    private func refreshCachedStatuses(for devices: [CollectorDevice]) {
        for device in devices {
            refreshCachedStatus(for: device.id)
        }
        discoveredDeviceStatusByID = Dictionary(
            uniqueKeysWithValues: devices.compactMap { device in
                guard let snapshot = latestStatusByDeviceID[device.id] else { return nil }
                return (device.id, snapshot)
            }
        )
    }

    private func refreshCachedStatus(for deviceID: String) {
        guard let adapterSnapshot = adapter.cachedDeviceStatusSnapshot(for: deviceID) else {
            if selectedDevice?.id == deviceID {
                latestDeviceStatusSnapshot = latestStatusByDeviceID[deviceID]
            }
            return
        }

        let existing = latestStatusByDeviceID[deviceID]
        let source = adapterSnapshot.status.battery?.source ?? .cached
        let mergedBattery = BatteryStatus(
            levelPercent: adapterSnapshot.status.battery?.levelPercent ?? existing?.status.battery?.levelPercent,
            chargeState: adapterSnapshot.status.battery?.chargeState ?? existing?.status.battery?.chargeState,
            lastUpdatedAt: adapterSnapshot.status.battery?.lastUpdatedAt ?? adapterSnapshot.updatedAt,
            source: source,
            unavailableReason: adapterSnapshot.status.battery?.unavailableReason
        )
        latestStatusByDeviceID[deviceID] = DeviceStatusSnapshot(
            deviceID: deviceID,
            status: DeviceStatus(battery: mergedBattery),
            updatedAt: adapterSnapshot.updatedAt
        )
        if selectedDevice?.id == deviceID {
            latestDeviceStatusSnapshot = latestStatusByDeviceID[deviceID]
        }
    }

    private func updateBatteryStatus(from batteryData: PolarBatteryData, deviceID: String?, timestamp: Date) {
        guard let deviceID else { return }

        let source: BatteryStatusSource?
        switch batteryData.eventType {
        case .callbackUpdate:
            source = .callback
        case .pollSnapshot:
            source = .poll
        case .batteryUnavailable:
            source = .unavailable
        }

        let battery = BatteryStatus(
            levelPercent: batteryData.levelPercent,
            chargeState: BatteryChargeState(rawOrNil: batteryData.chargeState),
            lastUpdatedAt: timestamp,
            source: source,
            unavailableReason: batteryData.unavailableReason
        )
        let snapshot = DeviceStatusSnapshot(
            deviceID: deviceID,
            status: DeviceStatus(battery: battery),
            updatedAt: timestamp
        )
        latestStatusByDeviceID[deviceID] = snapshot
        latestDeviceStatusSnapshot = snapshot
        if discoveredDevices.contains(where: { $0.id == deviceID }) {
            discoveredDeviceStatusByID[deviceID] = snapshot
        }
    }

    private func formatBattery(_ battery: BatteryStatus?) -> String {
        guard let battery else {
            return "unknown"
        }
        if let levelPercent = battery.levelPercent {
            return "\(levelPercent)%"
        }
        if let chargeState = battery.chargeState {
            return chargeState.rawValue.replacingOccurrences(of: "_", with: " ")
        }
        if battery.source == .unavailable {
            return "unavailable"
        }
        return "unknown"
    }

    private func clearFailureState() {
        lastErrorMessage = nil
        shouldSuggestLogExport = false
    }

    private func ensureUploadSessionIfNeeded(for streams: [CollectorStream]) {
        if activeSession == nil {
            let session = CollectionSession(
                device: adapter.deviceIdentity,
                collectionMode: .offlineRecording,
                startedAtUTC: nowProvider(),
                supportedStreams: adapter.availableStreams
            )
            activeSession = session
            prepareDebugExport(for: session)
            upsertManagedSession(
                id: session.sessionID,
                clientSessionID: session.clientSessionID,
                mode: session.collectionMode,
                origin: .ourApp,
                lifecycle: .started,
                startedAtUTC: session.startedAtUTC,
                stoppedAtUTC: nil,
                linkedFiles: [],
                notes: "offline_upload_session_bootstrap"
            )
        }

        for stream in Set(streams) {
            if streamDescriptorsByType[stream] == nil {
                streamDescriptorsByType[stream] = transport.makeStreamDescriptor(
                    for: stream,
                    source: adapter.sourceIdentifier
                )
            }
            if nextChunkSequenceNumberByStream[stream] == nil {
                nextChunkSequenceNumberByStream[stream] = 1
            }
            if lastFlushAtUTCByStream[stream] == nil {
                lastFlushAtUTCByStream[stream] = nowProvider()
            }
        }
    }

    private func startOffline(streams: [PolarOfflineStream]) async {
        guard beginOfflineOperation(.starting, lifecycle: .starting, statusMessage: "Starting offline recordings...") else { return }
        defer { completeOfflineOperation() }
        guard adapter.connectionState == .connected else {
            offlineLifecycleState = .disconnected
            offlineStatusMessage = "Device disconnected"
            offlineLastErrorMessage = "Device disconnected"
            return
        }
        guard !streams.isEmpty else {
            offlineLifecycleState = .featureUnavailable
            offlineStatusMessage = "No supported offline streams selected"
            offlineLastErrorMessage = offlineStatusMessage
            return
        }

        _ = await runPreOfflineSyncTimeCheck()
        for stream in streams {
            let state = offlineSettingsLoadStateByStream[stream] ?? .notLoaded
            if case .notLoaded = state {
                await loadOfflineSettings(for: stream)
            }
        }
        let alreadyRecordingStreams = streams.filter { offlineStreamRunStates[$0] == .recording }
        let startableStreams = streams.filter { stream in
            guard !alreadyRecordingStreams.contains(stream) else { return false }
            if case .failed = (offlineSettingsLoadStateByStream[stream] ?? .notLoaded) {
                return false
            }
            return true
        }
        for stream in startableStreams {
            offlineStreamRunStates[stream] = .starting
            offlineStreamRunMessages[stream] = "Starting..."
        }
        let requests = startableStreams.map { stream in
            OfflineRecordingStartRequest(stream: stream, selectedSettings: offlineSettingsByStream[stream]?.selected)
        }
        let adapterResults = await adapter.startOfflineRecordings(requests: requests)
        let alreadyRecordingResults = alreadyRecordingStreams.map {
            OfflineStreamOperationResult(stream: $0, success: false, message: "Already recording")
        }
        let failedSettingsResults = streams.filter {
            !startableStreams.contains($0) && !alreadyRecordingStreams.contains($0)
        }.map {
            OfflineStreamOperationResult(stream: $0, success: false, message: "Settings unavailable for stream")
        }
        let results = adapterResults + failedSettingsResults + alreadyRecordingResults
        offlineStreamRunMessages.merge(
            Dictionary(uniqueKeysWithValues: results.map { ($0.stream, $0.message) }),
            uniquingKeysWith: { _, new in new }
        )
        for result in results {
            offlineStreamRunStates[result.stream] = result.success ? .recording : .failed
        }
        let successCount = results.filter(\.success).count
        if successCount == results.count {
            offlineLifecycleState = .recording
            offlineStatusMessage = "Offline recording started (\(successCount)/\(results.count))"
            offlineLastSuccessAction = "Started offline recordings"
        } else if successCount > 0 {
            offlineLifecycleState = .partialSuccess
            offlineStatusMessage = "Partial start success (\(successCount)/\(results.count))"
            offlineLastErrorMessage = results.first(where: { !$0.success })?.message
        } else {
            offlineLifecycleState = .failed
            offlineStatusMessage = "Offline start failed"
            offlineLastErrorMessage = results.first?.message
        }
    }

    private func stopOffline(streams: [PolarOfflineStream]) async {
        guard beginOfflineOperation(.stopping, lifecycle: .stopping, statusMessage: "Stopping offline recordings...") else { return }
        defer { completeOfflineOperation() }
        guard adapter.connectionState == .connected else {
            offlineLifecycleState = .disconnected
            offlineStatusMessage = "Device disconnected"
            offlineLastErrorMessage = "Device disconnected"
            return
        }
        guard !streams.isEmpty else {
            offlineLifecycleState = .featureUnavailable
            offlineStatusMessage = "No supported offline streams selected"
            offlineLastErrorMessage = offlineStatusMessage
            return
        }

        streams.forEach { offlineStreamRunStates[$0] = .stopping }
        let results = await adapter.stopOfflineRecordings(streams: streams)
        offlineStreamRunMessages.merge(
            Dictionary(uniqueKeysWithValues: results.map { ($0.stream, $0.message) }),
            uniquingKeysWith: { _, new in new }
        )
        for result in results {
            offlineStreamRunStates[result.stream] = result.success ? .ready : .failed
        }
        let successCount = results.filter(\.success).count
        if successCount == results.count {
            offlineLifecycleState = .ready
            offlineStatusMessage = "Offline recording stopped (\(successCount)/\(results.count))"
            offlineLastSuccessAction = "Stopped offline recordings"
        } else if successCount > 0 {
            offlineLifecycleState = .partialSuccess
            offlineStatusMessage = "Partial stop success (\(successCount)/\(results.count))"
            offlineLastErrorMessage = results.first(where: { !$0.success })?.message
        } else {
            offlineLifecycleState = .failed
            offlineStatusMessage = "Offline stop failed"
            offlineLastErrorMessage = results.first?.message
        }
    }

    private func beginOfflineOperation(
        _ operation: OfflineOperation,
        lifecycle: OfflineLifecycleState,
        statusMessage: String
    ) -> Bool {
        guard !offlineIsOperationRunning else { return false }
        offlineIsOperationRunning = true
        offlineOperation = operation
        offlineLifecycleState = lifecycle
        offlineStatusMessage = statusMessage
        return true
    }

    private func completeOfflineOperation() {
        offlineIsOperationRunning = false
        offlineOperation = .none
        updateRecoveredStates()
    }

    func hasActiveOfflineRecording() -> Bool {
        offlineRecoveredStateByStream.values.contains(where: { $0.isRecording })
    }

    private func updateRecoveredStates() {
        var next: [PolarOfflineStream: OfflineStreamRecoveredState] = [:]
        let recordingsByStream = Dictionary(grouping: offlineRecordings, by: \.stream)
        for stream in PolarOfflineStream.allCases {
            let capability = capabilityForOfflineStream(stream)
            let runState = offlineStreamRunStates[stream] ?? .unknown
            let status: OfflineStreamStatus
            switch runState {
            case .recording:
                status = .recording
            case .ready, .uploaded:
                status = .ready
            case .unavailable:
                status = .unavailable
            case .failed:
                status = .failed
            case .unknown, .loadingSettings, .starting, .stopping, .fetching, .uploading:
                status = .unknown
            }
            next[stream] = OfflineStreamRecoveredState(
                isSelected: selectedOfflineStreams.contains(stream),
                isSupported: capability.isSupported,
                isRecording: runState == .recording,
                status: status,
                lastError: runState == .failed ? offlineStreamRunMessages[stream] : nil,
                lastKnownRecordInfo: recordingsByStream[stream]?.first ?? nil
            )
        }
        offlineRecoveredStateByStream = next
    }

    private func applyDeviceTimeActionResult(_ result: DeviceTimeActionResult, isSyncAction: Bool) {
        deviceTimeSyncState = result.state
        deviceTimeStatusMessage = result.message
        deviceTimeDebugDetails = result.debugDetails ?? "Stream timestamp verification not performed"
        lastDeviceTimeDeltaSeconds = result.verificationDeltaSeconds
        operationalTimeEvents.append(contentsOf: result.operationalEvents)
        if operationalTimeEvents.count > 100 {
            operationalTimeEvents.removeFirst(operationalTimeEvents.count - 100)
        }

        if let readback = result.readbackDeviceTime {
            lastDeviceTimeReadResult = Self.iso8601(from: readback)
        } else if result.state == .unavailable {
            lastDeviceTimeReadResult = "Read-back unavailable"
        }

        if isSyncAction {
            lastDeviceTimeSyncResult = result.message
        }
        log("Device time action result: state=\(result.state.rawValue) message=\(result.message)", category: "device-time")
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

    private func shouldRetryPendingUploads(now: Date) -> Bool {
        guard let nextUploadRetryAtUTC else { return true }
        return now >= nextUploadRetryAtUTC
    }

    private func streamFlushOrder() -> [CollectorStream] {
        [
            .heartRate,
            .ecg,
            .accelerometer,
            .ppi,
            .ppg,
            .magnetometer,
            .gyroscope,
            .battery,
            .eeg
        ]
    }

    private func firstBufferedStream() -> CollectorStream? {
        streamFlushOrder().first { stream in
            let samples = bufferedSamplesByStream[stream] ?? []
            return !samples.isEmpty
        }
    }

    private func resolvedStreamProfile(for stream: CollectorStream, session: CollectionSession) -> StreamMetadataProfile {
        guard session.collectionMode == .offlineRecording else {
            return uploadConfiguration.streamProfile(for: stream)
        }
        switch stream {
        case .heartRate: return PolarStreamProfile.hrOffline
        case .ppi: return PolarStreamProfile.ppiOffline
        case .accelerometer: return PolarStreamProfile.accOffline
        case .ppg: return PolarStreamProfile.ppgOffline
        case .magnetometer: return PolarStreamProfile.magOffline
        case .gyroscope: return PolarStreamProfile.gyrOffline
        case .ecg, .eeg, .battery:
            return uploadConfiguration.streamProfile(for: stream)
        }
    }

    private func upsertManagedSession(
        id: UUID,
        clientSessionID: String,
        mode: CollectionMode,
        origin: ManagedSessionOrigin,
        lifecycle: ManagedSessionLifecycle,
        startedAtUTC: Date,
        stoppedAtUTC: Date?,
        linkedFiles: [ManagedSessionFile],
        notes: String?
    ) {
        if let index = managedSessions.firstIndex(where: { $0.id == id }) {
            var existing = managedSessions[index]
            existing.lifecycle = lifecycle
            existing.stoppedAtUTC = stoppedAtUTC
            existing.origin = origin
            existing.notes = notes ?? existing.notes
            existing.linkedFiles = Array(Set(existing.linkedFiles + linkedFiles))
            managedSessions[index] = existing
            queueManifestSync(for: managedSessions[index])
        } else {
            managedSessions.append(
                ManagedSessionRecord(
                    id: id,
                    clientSessionID: clientSessionID,
                    deviceID: adapter.deviceIdentity.id,
                    deviceType: "\(adapter.deviceIdentity.vendor) \(adapter.deviceIdentity.model)",
                    collectionMode: mode,
                    origin: origin,
                    lifecycle: lifecycle,
                    startedAtUTC: startedAtUTC,
                    stoppedAtUTC: stoppedAtUTC,
                    linkedFiles: linkedFiles,
                    notes: notes
                )
            )
            if let created = managedSessions.last {
                queueManifestSync(for: created)
            }
        }
        managedSessions.sort { $0.startedAtUTC > $1.startedAtUTC }
        persistLedger()
        refreshUnassignedRecordingGroups()
    }

    private func updateManagedSessionLifecycle(
        id: UUID,
        lifecycle: ManagedSessionLifecycle,
        stoppedAtUTC: Date?,
        notes: String?
    ) {
        guard let index = managedSessions.firstIndex(where: { $0.id == id }) else { return }
        managedSessions[index].lifecycle = lifecycle
        if let stoppedAtUTC {
            managedSessions[index].stoppedAtUTC = stoppedAtUTC
        }
        if let notes, !notes.isEmpty {
            managedSessions[index].notes = notes
        }
        queueManifestSync(for: managedSessions[index])
        persistLedger()
        refreshUnassignedRecordingGroups()
    }

    private func linkFilesToManagedSession(id: UUID, files: [ManagedSessionFile]) {
        guard let index = managedSessions.firstIndex(where: { $0.id == id }) else { return }
        let existing = managedSessions[index].linkedFiles
        let merged = Array(Set(existing + files))
        managedSessions[index].linkedFiles = merged.sorted { $0.path < $1.path }
        persistLedger()
        refreshUnassignedRecordingGroups()
    }

    private func refreshUnassignedRecordingGroups() {
        let assignedPaths = Set(managedSessions.flatMap { $0.linkedFiles.map(\.path) })
        let unassigned = offlineRecordings.filter { !assignedPaths.contains($0.path) }
        unassignedOfflineRecordings = unassigned.sorted {
            ($0.startedAt ?? .distantPast) < ($1.startedAt ?? .distantPast)
        }
        unassignedRecordingGroups = clusterUnassignedRecordings(unassignedOfflineRecordings)
    }

    private func unassignedRecordings(from entries: [OfflineRecordingEntry]) -> [OfflineRecordingEntry] {
        let assignedPaths = Set(managedSessions.flatMap { $0.linkedFiles.map(\.path) })
        return entries.filter { !assignedPaths.contains($0.path) }
    }

    private func clusterUnassignedRecordings(_ entries: [OfflineRecordingEntry]) -> [UnassignedRecordingGroup] {
        guard !entries.isEmpty else { return [] }
        let sorted = entries.sorted { ($0.startedAt ?? .distantPast) < ($1.startedAt ?? .distantPast) }
        var groups: [[OfflineRecordingEntry]] = []
        var current: [OfflineRecordingEntry] = []

        for entry in sorted {
            guard let last = current.last else {
                current = [entry]
                continue
            }
            guard let left = last.startedAt, let right = entry.startedAt else {
                groups.append(current)
                current = [entry]
                continue
            }
            if abs(right.timeIntervalSince(left)) <= unassignedClusterGapSeconds {
                current.append(entry)
            } else {
                groups.append(current)
                current = [entry]
            }
        }
        if !current.isEmpty {
            groups.append(current)
        }

        return groups.enumerated().map { index, items in
            let starts = items.compactMap(\.startedAt)
            return UnassignedRecordingGroup(
                id: "cluster-\(index + 1)",
                entries: items,
                startAtUTC: starts.min(),
                endAtUTC: starts.max()
            )
        }
    }

    private func createExternalManagedSession(from entries: [OfflineRecordingEntry], note: String) {
        let candidates = unassignedRecordings(from: entries)
        guard !candidates.isEmpty else { return }
        let start = candidates.compactMap(\.startedAt).min() ?? nowProvider()
        let stop = candidates.compactMap(\.startedAt).max() ?? start
        let sessionUUID = UUID()
        let linkedFiles = candidates.map {
            ManagedSessionFile(
                path: $0.path,
                stream: $0.stream?.rawValue ?? "unknown",
                startedAtUTC: $0.startedAt,
                sizeBytes: $0.sizeBytes
            )
        }
        upsertManagedSession(
            id: sessionUUID,
            clientSessionID: CollectionSession.makeClientSessionID(startedAtUTC: start, sessionID: sessionUUID),
            mode: .offlineRecording,
            origin: .externalApp,
            lifecycle: .stopped,
            startedAtUTC: start,
            stoppedAtUTC: stop,
            linkedFiles: linkedFiles,
            notes: note
        )
    }

    private func persistLedger() {
        sessionLedgerStore.save(sessions: managedSessions, pendingManifests: pendingSessionManifests)
    }

    private func queueManifestSync(for record: ManagedSessionRecord) {
        let key = record.clientSessionID
        if pendingSessionManifests.contains(where: { $0.id == key }) {
            return
        }
        pendingSessionManifests.append(
            PendingSessionManifest(
                id: key,
                sessionID: record.id,
                clientSessionID: record.clientSessionID,
                lastError: nil,
                retryCount: 0,
                updatedAtUTC: nowProvider()
            )
        )
        persistLedger()
        guard isManifestAutoRetryEnabled else { return }
        Task { @MainActor [weak self] in
            await self?.retryPendingSessionManifestSync()
        }
    }

    func retryPendingSessionManifestSync() async {
        guard transport.isNetworkUploadConfigured else { return }
        guard !isManifestSyncRunning else { return }
        guard !pendingSessionManifests.isEmpty else {
            manifestSyncStatusMessage = "No pending manifests"
            return
        }

        isManifestSyncRunning = true
        defer {
            isManifestSyncRunning = false
            persistLedger()
        }

        let batch = Array(pendingSessionManifests.prefix(manifestRetryBatchSize))
        manifestSyncStatusMessage = "Syncing \(batch.count) manifest(s)..."
        var successCount = 0
        var failureCount = 0

        for item in batch {
            guard let session = managedSessions.first(where: { $0.id == item.sessionID }) else { continue }
            do {
                let payload = buildSessionManifestPayload(from: session)
                _ = try await transport.uploadSessionManifest(payload)
                pendingSessionManifests.removeAll { $0.id == item.id }
                successCount += 1
            } catch {
                if let index = pendingSessionManifests.firstIndex(where: { $0.id == item.id }) {
                    pendingSessionManifests[index].retryCount += 1
                    pendingSessionManifests[index].lastError = error.localizedDescription
                    pendingSessionManifests[index].updatedAtUTC = nowProvider()
                }
                failureCount += 1
            }
        }
        manifestSyncStatusMessage = "Manifest sync done: ok \(successCount), failed \(failureCount), left \(pendingSessionManifests.count)"
    }

    private func buildSessionManifestPayload(from record: ManagedSessionRecord) -> SessionManifestPayload {
        SessionManifestPayload(
            schemaVersion: "1.0",
            sessionID: record.id.uuidString.lowercased(),
            deviceSessionID: record.clientSessionID,
            sessionMode: record.collectionMode.transportValue,
            collector: SessionManifestPayload.Collector(
                collectorID: "ios-collector",
                runtimeType: "ios",
                appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown",
                buildVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
            ),
            device: SessionManifestPayload.Device(
                vendor: "polar",
                model: adapter.deviceIdentity.model.lowercased(),
                deviceID: record.deviceID
            ),
            time: SessionManifestPayload.Time(
                startedAtSource: Self.iso8601(from: record.startedAtUTC),
                startedAtServer: nil
            ),
            metadata: SessionManifestPayload.Metadata(
                notes: record.notes,
                tags: ["origin:\(record.origin.rawValue)", "lifecycle:\(record.lifecycle.rawValue)"]
            )
        )
    }

    private func reconcileOpenSessionsAfterLifecycleEvent() {
        // M1 recovery: if app restarted while we had open sessions and device no longer records,
        // mark those sessions as externally stopped to keep state deterministic for upload flows.
        guard adapter.connectionState == .connected else { return }
        let open = managedSessions.filter { $0.lifecycle == .started }
        guard !open.isEmpty else { return }

        Task { @MainActor [weak self] in
            guard let self else { return }
            let statusByStream = await self.adapter.offlineRecordingStatus()
            let hasActiveRecording = statusByStream.values.contains(.recording)
            guard !hasActiveRecording else { return }
            let now = self.nowProvider()
            for session in open {
                self.updateManagedSessionLifecycle(
                    id: session.id,
                    lifecycle: .stoppedExternal,
                    stoppedAtUTC: session.stoppedAtUTC ?? now,
                    notes: "auto_recovered_stopped_externally"
                )
            }
            if !open.isEmpty {
                self.log("Recovered \(open.count) open session(s) as externally stopped", category: "session")
            }
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
