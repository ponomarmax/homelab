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

struct OfflineRecordingSafetySummary: Equatable, Sendable {
    let isRecordingNow: Bool
    let isAssignedToSession: Bool
    let assignedSessionID: String?
    let hasLocalArchiveCopy: Bool
    let safeToDeleteFromSensor: Bool
}

struct UploadedBatchCheckpoint: Codable, Equatable, Hashable, Sendable {
    let sessionID: UUID
    let sourcePath: String
    let streamType: String
    let samplesCount: Int
    let component: String
    let recordedAtUTC: Date

    enum CodingKeys: String, CodingKey {
        case sessionID
        case sourcePath
        case streamType
        case samplesCount
        case component
        case recordedAtUTC
    }

    init(
        sessionID: UUID,
        sourcePath: String,
        streamType: String,
        samplesCount: Int,
        component: String,
        recordedAtUTC: Date
    ) {
        self.sessionID = sessionID
        self.sourcePath = sourcePath
        self.streamType = streamType
        self.samplesCount = samplesCount
        self.component = component
        self.recordedAtUTC = recordedAtUTC
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sessionID = try container.decode(UUID.self, forKey: .sessionID)
        sourcePath = try container.decode(String.self, forKey: .sourcePath)
        streamType = try container.decode(String.self, forKey: .streamType)
        samplesCount = try container.decode(Int.self, forKey: .samplesCount)
        component = try container.decodeIfPresent(String.self, forKey: .component) ?? "full"
        recordedAtUTC = try container.decode(Date.self, forKey: .recordedAtUTC)
    }
}

struct OfflineFileTransferState: Codable, Equatable, Sendable {
    let sourcePath: String
    var firstFetchedAtUTC: Date
    var lastFetchedAtUTC: Date
    var lastUploadedAtUTC: Date?
    var isUploadedComplete: Bool
    var lastSessionID: UUID?
}

private struct UploadedBatchCheckpointSnapshot: Codable, Sendable {
    let schemaVersion: Int
    let items: [UploadedBatchCheckpoint]
}

@MainActor
final class UploadedBatchCheckpointStore {
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
        self.storageURL = dir.appendingPathComponent("uploaded-batch-checkpoints-v1.json")
        self.encoder = JSONEncoder()
        self.encoder.dateEncodingStrategy = .iso8601
        self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.decoder = JSONDecoder()
        self.decoder.dateDecodingStrategy = .iso8601
    }

    func load() -> [UploadedBatchCheckpoint] {
        guard let data = try? Data(contentsOf: storageURL),
              let snapshot = try? decoder.decode(UploadedBatchCheckpointSnapshot.self, from: data) else {
            return []
        }
        return snapshot.items
    }

    func save(_ items: [UploadedBatchCheckpoint]) {
        let snapshot = UploadedBatchCheckpointSnapshot(schemaVersion: 1, items: items)
        guard let data = try? encoder.encode(snapshot) else { return }
        try? data.write(to: storageURL, options: .atomic)
    }
}

private struct OfflineFileTransferStateSnapshot: Codable, Sendable {
    let schemaVersion: Int
    let items: [OfflineFileTransferState]
}

@MainActor
final class OfflineFileTransferStateStore {
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
        self.storageURL = dir.appendingPathComponent("offline-file-transfer-state-v1.json")
        self.encoder = JSONEncoder()
        self.encoder.dateEncodingStrategy = .iso8601
        self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.decoder = JSONDecoder()
        self.decoder.dateDecodingStrategy = .iso8601
    }

    func load() -> [OfflineFileTransferState] {
        guard let data = try? Data(contentsOf: storageURL),
              let snapshot = try? decoder.decode(OfflineFileTransferStateSnapshot.self, from: data) else {
            return []
        }
        return snapshot.items
    }

    func save(_ items: [OfflineFileTransferState]) {
        let snapshot = OfflineFileTransferStateSnapshot(schemaVersion: 1, items: items)
        guard let data = try? encoder.encode(snapshot) else { return }
        try? data.write(to: storageURL, options: .atomic)
    }
}

private struct ArchivedOfflineUploadBatch: Codable {
    let streamRawValue: String
    let sourcePath: String
    let samples: [HeartRateSample]
    let timeContext: UploadChunkTimeContext?
}

private struct OfflineSessionArchivePayload: Codable {
    let sessionID: UUID
    let clientSessionID: String
    let startedAtUTC: Date
    let updatedAtUTC: Date
    let batches: [ArchivedOfflineUploadBatch]
}

@MainActor
final class OfflineSessionArchiveStore {
    private let archiveDirectoryURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let dir = appSupport
            .appendingPathComponent("CollectorApp", isDirectory: true)
            .appendingPathComponent("offline-session-archive", isDirectory: true)
        if !fileManager.fileExists(atPath: dir.path) {
            try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        self.archiveDirectoryURL = dir

        self.encoder = JSONEncoder()
        self.encoder.dateEncodingStrategy = .iso8601
        self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        self.decoder = JSONDecoder()
        self.decoder.dateDecodingStrategy = .iso8601
    }

    func loadBatches(sessionID: UUID) -> [OfflineUploadBatch] {
        let fileURL = archiveDirectoryURL.appendingPathComponent("\(sessionID.uuidString.lowercased()).json")
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        guard let payload = try? decoder.decode(OfflineSessionArchivePayload.self, from: data) else { return [] }
        return payload.batches.compactMap { item in
            guard let stream = CollectorStream(rawValue: item.streamRawValue) else { return nil }
            return OfflineUploadBatch(
                stream: stream,
                sourcePath: item.sourcePath,
                samples: item.samples,
                timeContext: item.timeContext
            )
        }
    }

    func saveBatches(
        sessionID: UUID,
        clientSessionID: String,
        startedAtUTC: Date,
        batches: [OfflineUploadBatch]
    ) {
        guard !batches.isEmpty else { return }
        let existing = loadBatches(sessionID: sessionID)
        let merged = deduplicate(existing + batches)
        let payload = OfflineSessionArchivePayload(
            sessionID: sessionID,
            clientSessionID: clientSessionID,
            startedAtUTC: startedAtUTC,
            updatedAtUTC: Date(),
            batches: merged.map {
                ArchivedOfflineUploadBatch(
                    streamRawValue: $0.stream.rawValue,
                    sourcePath: $0.sourcePath,
                    samples: $0.samples,
                    timeContext: $0.timeContext
                )
            }
        )
        guard let data = try? encoder.encode(payload) else { return }
        let fileURL = archiveDirectoryURL.appendingPathComponent("\(sessionID.uuidString.lowercased()).json")
        try? data.write(to: fileURL, options: .atomic)
    }

    func deleteSessionArchive(sessionID: UUID) {
        let fileURL = archiveDirectoryURL.appendingPathComponent("\(sessionID.uuidString.lowercased()).json")
        try? fileManager.removeItem(at: fileURL)
    }

    func archiveFileURL(sessionID: UUID) -> URL {
        archiveDirectoryURL.appendingPathComponent("\(sessionID.uuidString.lowercased()).json")
    }

    func containsSourcePath(sessionID: UUID, sourcePath: String) -> Bool {
        loadBatches(sessionID: sessionID).contains(where: { $0.sourcePath == sourcePath })
    }

    private func deduplicate(_ batches: [OfflineUploadBatch]) -> [OfflineUploadBatch] {
        var seen = Set<String>()
        var ordered: [OfflineUploadBatch] = []
        for batch in batches {
            let key = "\(batch.stream.rawValue)|\(batch.sourcePath)|\(batch.samples.count)|\(batch.timeContext?.recordingStartUTC?.timeIntervalSince1970 ?? -1)"
            if seen.contains(key) {
                continue
            }
            seen.insert(key)
            ordered.append(batch)
        }
        return ordered
    }
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
