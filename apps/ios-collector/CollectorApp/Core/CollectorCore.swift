import Foundation
import UIKit

@MainActor
final class CollectorCore: ObservableObject {
    struct RememberedDevice: Codable, Equatable, Sendable {
        let id: String
        let name: String
        let vendor: String
        let model: String
        let updatedAtUTC: Date
    }

    enum FlushTrigger: Equatable {
        case manual
        case sampleCount
        case timer
        case finalOnStop
    }

    enum CoreLogLevel: String {
        case debug = "DEBUG"
        case info = "INFO"
        case warning = "WARN"
        case error = "ERROR"
    }

    @Published var status: CollectorStatus = .disconnected
    @Published var uploadStatus: UploadStatus = .idle
    @Published var discoveredDevices: [CollectorDevice] = []
    @Published var selectedDevice: CollectorDevice?
    @Published var latestDeviceStatusSnapshot: DeviceStatusSnapshot?
    @Published var discoveredDeviceStatusByID: [String: DeviceStatusSnapshot] = [:]
    @Published var activeSession: CollectionSession?
    @Published var streamDescriptor: StreamDescriptor?
    @Published var latestHeartRateSample: HeartRateSample?
    @Published var totalSamplesReceived: Int = 0
    @Published var bufferedSamplesCount: Int = 0
    @Published var pendingUploadChunksCount: Int = 0
    @Published var lastPreparedChunk: UploadChunk?
    @Published var debugExportFileURL: URL?
    @Published var logExportFileURL: URL?
    @Published var persistentLogFileURL: URL?
    @Published var lastErrorMessage: String?
    @Published var shouldSuggestLogExport: Bool = false
    @Published var isScanningDevices: Bool = false
    @Published var isConnectingDevice: Bool = false
    @Published var isPreparingChunk: Bool = false
    @Published var isUploadingChunk: Bool = false
    @Published var activityMessage: String = "Idle"
    @Published var eventLogs: [String] = []
    @Published var selectedOnlineStreams: Set<CollectorStream> = []
    @Published var selectedOfflineStreams: Set<PolarOfflineStream> = []
    @Published var offlineLifecycleState: OfflineLifecycleState = .notLoaded
    @Published var offlineStatusMessage: String = "Disconnected"
    @Published var offlineFetchProgress: OfflineUploadFetchProgress?
    @Published var offlineStreamCapabilities: [PolarOfflineStream: OfflineStreamCapability] = [:]
    @Published var offlineSettingsByStream: [PolarOfflineStream: OfflineStreamSettings] = [:]
    @Published var offlineSettingsLoadStateByStream: [PolarOfflineStream: OfflineSettingsLoadState] = [:]
    @Published var offlineStreamRunMessages: [PolarOfflineStream: String] = [:]
    @Published var offlineStreamRunStates: [PolarOfflineStream: OfflineStreamRunState] = [:]
    @Published var offlineRecoveredStateByStream: [PolarOfflineStream: OfflineStreamRecoveredState] = [:]
    @Published var offlineRecordings: [OfflineRecordingEntry] = []
    @Published var offlineOperation: OfflineOperation = .none
    @Published var offlineIsOperationRunning: Bool = false
    @Published var offlineLastSuccessAction: String = "None"
    @Published var offlineLastErrorMessage: String?
    @Published var offlineRecordErrorsByID: [String: String] = [:]
    @Published var deletingOfflineRecordingIDs: Set<String> = []
    @Published var unassignedOfflineRecordings: [OfflineRecordingEntry] = []
    @Published var unassignedRecordingGroups: [UnassignedRecordingGroup] = []
    @Published var deviceTimeSyncState: DeviceTimeSyncState = .idle
    @Published var deviceTimeStatusMessage: String = "Not synced"
    @Published var deviceTimeDebugDetails: String = "Stream timestamp verification not performed"
    @Published var lastDeviceTimeReadResult: String = "Not synced"
    @Published var lastDeviceTimeSyncResult: String = "Not synced"
    @Published var lastDeviceTimeDeltaSeconds: TimeInterval?
    @Published var operationalTimeEvents: [DeviceTimeOperationalEvent] = []
    @Published var managedSessions: [ManagedSessionRecord] = []
    @Published var pendingSessionManifests: [PendingSessionManifest] = []
    @Published var isManifestSyncRunning: Bool = false
    @Published var manifestSyncStatusMessage: String = "Idle"
    @Published var isManagedSessionUploadRunning: Bool = false
    @Published var managedSessionUploadStatusMessage: String = "Idle"
    @Published var managedSessionUploadStatusByID: [UUID: String] = [:]
    @Published var rememberedDevice: RememberedDevice?

    let defaultCollectionMode: CollectionMode = .live

    let adapter: CollectorDeviceAdapter
    let transport: CollectorTransporting
    let uploadConfiguration: CollectorUploadConfiguration
    let nowProvider: @Sendable () -> Date
    let sleepProvider: @Sendable (UInt64) async -> Void
    let debugExporter = HrSampleDebugExporter()
    let sessionLedgerStore = SessionLedgerStore()
    let offlineSessionArchiveStore = OfflineSessionArchiveStore()
    let uploadedBatchCheckpointStore = UploadedBatchCheckpointStore()
    let offlineFileTransferStateStore = OfflineFileTransferStateStore()
    let isVerboseLoggingEnabled: Bool
    let configurationRegistry: DeviceConfigurationRegistry
    let unassignedClusterGapSeconds: TimeInterval
    let isManifestAutoRetryEnabled: Bool
    let manifestRetryBatchSize: Int

    var pendingUploadChunks: [UploadChunk] = []
    var bufferedSamplesByStream: [CollectorStream: [HeartRateSample]] = [:]
    var pendingTimeContextByStream: [CollectorStream: UploadChunkTimeContext] = [:]
    var streamDescriptorsByType: [CollectorStream: StreamDescriptor] = [:]
    var nextChunkSequenceNumberByStream: [CollectorStream: Int] = [:]
    var lastFlushAtUTCByStream: [CollectorStream: Date] = [:]
    var activeProviders: [HeartRateStreamProviding] = []
    var latestStatusByDeviceID: [String: DeviceStatusSnapshot] = [:]

    var autoFlushTask: Task<Void, Never>?
    var isAutoFlushing: Bool = false
    var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid
    var persistentLogFileHandle: FileHandle?
    var consecutiveUploadFailureCount: Int = 0
    var nextUploadRetryAtUTC: Date?
    let rememberedDeviceStorageKey = "collector.remembered_device.v1"

    init(
        adapter: CollectorDeviceAdapter,
        transport: CollectorTransporting,
        uploadConfiguration: CollectorUploadConfiguration = .default,
        nowProvider: @escaping @Sendable () -> Date = { Date() },
        sleepProvider: @escaping @Sendable (UInt64) async -> Void = { nanoseconds in
            try? await Task.sleep(nanoseconds: nanoseconds)
        },
        configurationRegistry: DeviceConfigurationRegistry? = nil
    ) {
        self.adapter = adapter
        self.transport = transport
        self.uploadConfiguration = uploadConfiguration
        self.nowProvider = nowProvider
        self.sleepProvider = sleepProvider
        self.configurationRegistry = configurationRegistry ?? DeviceConfigurationRegistry(store: DeviceConfigurationStore())
        let environment = ProcessInfo.processInfo.environment
        self.isVerboseLoggingEnabled = environment["COLLECTOR_VERBOSE_LOGS"] == "1"
            || environment["COLLECTOR_LOG_LEVEL"]?.lowercased() == "debug"
        self.unassignedClusterGapSeconds = TimeInterval(environment["COLLECTOR_UNASSIGNED_CLUSTER_GAP_SECONDS"] ?? "") ?? 180
        self.isManifestAutoRetryEnabled = environment["COLLECTOR_MANIFEST_AUTO_RETRY"] != "0"
        self.manifestRetryBatchSize = max(1, Int(environment["COLLECTOR_MANIFEST_RETRY_BATCH_SIZE"] ?? "") ?? 3)
        self.managedSessions = sessionLedgerStore.loadSessions()
        self.pendingSessionManifests = sessionLedgerStore.loadPendingManifests()
        self.rememberedDevice = Self.loadRememberedDevice(forKey: rememberedDeviceStorageKey)
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

    private static func loadRememberedDevice(forKey key: String) -> RememberedDevice? {
        guard let raw = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(RememberedDevice.self, from: raw)
    }

}
