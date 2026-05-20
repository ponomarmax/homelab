import Foundation

struct StreamMetadataProfile: Equatable, Codable, Sendable {
    struct Source: Equatable, Codable, Sendable {
        let vendor: String
        let deviceModel: String
        let deviceID: String?

        enum CodingKeys: String, CodingKey {
            case vendor
            case deviceModel = "device_model"
            case deviceID = "device_id"
        }
    }

    struct Collection: Equatable, Codable, Sendable {
        let mode: String
    }

    struct Transport: Equatable, Codable, Sendable {
        let encoding: String
        let compression: String
        let payloadSchema: String
        let payloadVersion: String

        enum CodingKeys: String, CodingKey {
            case encoding
            case compression
            case payloadSchema = "payload_schema"
            case payloadVersion = "payload_version"
        }
    }

    let schemaVersion: String
    let streamType: String
    let streamIDPrefix: String?
    let source: Source
    let collection: Collection
    let deviceTimeReference: String
    let transport: Transport

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case streamType = "stream_type"
        case streamIDPrefix = "stream_id_prefix"
        case source
        case collection
        case deviceTimeReference = "device_time_reference"
        case transport
    }

    func streamID(for sessionID: UUID) -> String {
        let prefix = streamIDPrefix ?? streamType
        return "stream-\(prefix)-\(sessionID.uuidString.lowercased())"
    }
}

struct CollectorUploadConfiguration: Equatable, Sendable {
    struct RetryConfiguration: Equatable, Sendable {
        let initialDelaySeconds: TimeInterval
        let maxDelaySeconds: TimeInterval
        let backoffMultiplier: Double

        func nextDelaySeconds(forAttempt attempt: Int) -> TimeInterval {
            guard attempt > 0 else { return initialDelaySeconds }
            let exponent = max(0, attempt - 1)
            let delay = initialDelaySeconds * pow(backoffMultiplier, Double(exponent))
            return min(maxDelaySeconds, delay)
        }
    }

    struct StreamUploadConfiguration: Equatable, Sendable {
        let sampleCountThreshold: Int?

        static let `default` = StreamUploadConfiguration(sampleCountThreshold: nil)
    }

    let uploadFlushIntervalSeconds: TimeInterval
    let defaultSampleCountThreshold: Int?
    let retry: RetryConfiguration
    let streamConfigurations: [CollectorStream: StreamUploadConfiguration]
    let userIDHeaderValue: String
    let streamProfiles: [CollectorStream: StreamMetadataProfile]
    let requestTimeoutSeconds: TimeInterval

    var streamProfile: StreamMetadataProfile {
        streamProfile(for: .heartRate)
    }

    func streamProfile(for stream: CollectorStream) -> StreamMetadataProfile {
        streamProfiles[stream] ?? PolarStreamProfile.hrLive
    }

    func sampleFlushCount(for stream: CollectorStream) -> Int? {
        streamConfigurations[stream]?.sampleCountThreshold ?? defaultSampleCountThreshold
    }

    static let `default` = CollectorUploadConfiguration(
        uploadFlushIntervalSeconds: 60,
        defaultSampleCountThreshold: nil,
        retry: RetryConfiguration(
            initialDelaySeconds: 2,
            maxDelaySeconds: 60,
            backoffMultiplier: 2
        ),
        streamConfigurations: [
            .heartRate: .default,
            .ecg: .default,
            .accelerometer: .default,
            .ppi: .default,
            .ppg: .default,
            .magnetometer: .default,
            .gyroscope: .default,
            .battery: .default
        ],
        userIDHeaderValue: "2",
        streamProfiles: [
            .heartRate: PolarStreamProfile.hrLive,
            .ecg: PolarStreamProfile.ecgLive,
            .accelerometer: PolarStreamProfile.accLive,
            .ppi: PolarStreamProfile.ppiOffline,
            .ppg: PolarStreamProfile.ppgOffline,
            .magnetometer: PolarStreamProfile.magOffline,
            .gyroscope: PolarStreamProfile.gyrOffline,
            .battery: PolarStreamProfile.batteryLive
        ],
        requestTimeoutSeconds: 8
    )

    init(
        uploadFlushIntervalSeconds: TimeInterval,
        defaultSampleCountThreshold: Int?,
        retry: RetryConfiguration,
        streamConfigurations: [CollectorStream: StreamUploadConfiguration],
        userIDHeaderValue: String,
        streamProfiles: [CollectorStream: StreamMetadataProfile],
        requestTimeoutSeconds: TimeInterval
    ) {
        self.uploadFlushIntervalSeconds = uploadFlushIntervalSeconds
        self.defaultSampleCountThreshold = defaultSampleCountThreshold
        self.retry = retry
        self.streamConfigurations = streamConfigurations
        self.userIDHeaderValue = userIDHeaderValue
        self.streamProfiles = streamProfiles
        self.requestTimeoutSeconds = requestTimeoutSeconds
    }

    init(
        autoFlushSampleCount: Int,
        autoFlushIntervalSeconds: TimeInterval,
        userIDHeaderValue: String,
        streamProfiles: [CollectorStream: StreamMetadataProfile]
    ) {
        self.init(
            uploadFlushIntervalSeconds: autoFlushIntervalSeconds,
            defaultSampleCountThreshold: autoFlushSampleCount,
            retry: .init(initialDelaySeconds: 2, maxDelaySeconds: 60, backoffMultiplier: 2),
            streamConfigurations: [:],
            userIDHeaderValue: userIDHeaderValue,
            streamProfiles: streamProfiles,
            requestTimeoutSeconds: 8
        )
    }
}

struct CollectorRuntimeConfiguration {
    let uploadEndpoint: URL?
    let pipelineEndpoint: URL?
    let dashboardEndpoint: URL?
    let upload: CollectorUploadConfiguration

    static func from(
        environment: [String: String],
        arguments: [String],
        bundleInfo: [String: Any]? = nil
    ) -> CollectorRuntimeConfiguration {
        let uploadEndpointRawValue = environment["COLLECTOR_UPLOAD_ENDPOINT"]
            ?? (bundleInfo?["COLLECTOR_UPLOAD_ENDPOINT"] as? String)
        let uploadEndpoint = uploadEndpointRawValue.flatMap(parseUploadEndpoint)
        let pipelineEndpointRawValue = environment["COLLECTOR_PIPELINE_ENDPOINT"]
            ?? (bundleInfo?["COLLECTOR_PIPELINE_ENDPOINT"] as? String)
        let pipelineEndpoint = pipelineEndpointRawValue.flatMap(parseServiceEndpoint)
        let dashboardEndpointRawValue = environment["COLLECTOR_DASHBOARD_ENDPOINT"]
            ?? (bundleInfo?["COLLECTOR_DASHBOARD_ENDPOINT"] as? String)
        let dashboardEndpoint = dashboardEndpointRawValue.flatMap(parseServiceEndpoint)

        var uploadConfiguration = CollectorUploadConfiguration.default
        if let rawFlushInterval = environment["COLLECTOR_UPLOAD_FLUSH_INTERVAL_SECONDS"],
           let flushInterval = TimeInterval(rawFlushInterval),
           flushInterval > 0 {
            uploadConfiguration = CollectorUploadConfiguration(
                uploadFlushIntervalSeconds: flushInterval,
                defaultSampleCountThreshold: uploadConfiguration.defaultSampleCountThreshold,
                retry: uploadConfiguration.retry,
                streamConfigurations: uploadConfiguration.streamConfigurations,
                userIDHeaderValue: uploadConfiguration.userIDHeaderValue,
                streamProfiles: uploadConfiguration.streamProfiles,
                requestTimeoutSeconds: uploadConfiguration.requestTimeoutSeconds
            )
        }

        if let rawTimeout = environment["COLLECTOR_UPLOAD_REQUEST_TIMEOUT_SECONDS"],
           let timeout = TimeInterval(rawTimeout),
           timeout > 0 {
            uploadConfiguration = CollectorUploadConfiguration(
                uploadFlushIntervalSeconds: uploadConfiguration.uploadFlushIntervalSeconds,
                defaultSampleCountThreshold: uploadConfiguration.defaultSampleCountThreshold,
                retry: uploadConfiguration.retry,
                streamConfigurations: uploadConfiguration.streamConfigurations,
                userIDHeaderValue: uploadConfiguration.userIDHeaderValue,
                streamProfiles: uploadConfiguration.streamProfiles,
                requestTimeoutSeconds: timeout
            )
        }

        return CollectorRuntimeConfiguration(
            uploadEndpoint: uploadEndpoint,
            pipelineEndpoint: pipelineEndpoint,
            dashboardEndpoint: dashboardEndpoint,
            upload: uploadConfiguration
        )
    }

    private static func parseUploadEndpoint(_ rawValue: String) -> URL? {
        guard var components = URLComponents(string: rawValue) else { return nil }
        guard let scheme = components.scheme?.lowercased(), ["http", "https"].contains(scheme) else {
            return nil
        }
        guard let host = components.host, !host.isEmpty else { return nil }

        if components.path.isEmpty || components.path == "/" {
            components.path = "/upload-chunk"
        }

        return components.url
    }

    private static func parseServiceEndpoint(_ rawValue: String) -> URL? {
        guard let components = URLComponents(string: rawValue) else { return nil }
        guard let scheme = components.scheme?.lowercased(), ["http", "https"].contains(scheme) else {
            return nil
        }
        guard let host = components.host, !host.isEmpty else { return nil }
        return components.url
    }
}


// MARK: - Device Configuration Registry

struct StreamSettingDefinition: Equatable, Sendable {
    let key: String
    let displayName: String
    let defaultValue: StreamSettingValue
    let allowedValues: [StreamSettingValue]
}

struct StreamConfiguration: Equatable, Sendable {
    let id: String
    let displayName: String
    let collectorStream: CollectorStream?
    let offlineStream: PolarOfflineStream?
    let settings: [StreamSettingDefinition]
}

struct DeviceModeDescriptor: Equatable, Sendable {
    let id: String
    let displayName: String
    let streams: [StreamConfiguration]
}

struct DeviceCapabilityDescriptor: Equatable, Sendable, Identifiable {
    let id: String
    let displayName: String
    let subtitle: String
    let modes: [DeviceModeDescriptor]
}

struct UserStreamConfigurationOverride: Equatable, Codable, Sendable, Hashable {
    let deviceID: String
    let modeID: String
    let streamID: String
    let settingKey: String
    let value: StreamSettingValue
}

struct DeviceConfigurationSnapshot: Codable, Sendable {
    let schemaVersion: Int
    let overrides: [UserStreamConfigurationOverride]

    init(schemaVersion: Int = 1, overrides: [UserStreamConfigurationOverride]) {
        self.schemaVersion = schemaVersion
        self.overrides = overrides
    }
}

@MainActor
final class DeviceConfigurationStore {
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
        storageURL = dir.appendingPathComponent("device-configuration-v1.json")
        encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        decoder = JSONDecoder()
    }

    func load() -> DeviceConfigurationSnapshot {
        guard let data = try? Data(contentsOf: storageURL),
              let snapshot = try? decoder.decode(DeviceConfigurationSnapshot.self, from: data) else {
            return DeviceConfigurationSnapshot(overrides: [])
        }
        return snapshot
    }

    func save(_ snapshot: DeviceConfigurationSnapshot) {
        guard let data = try? encoder.encode(snapshot) else { return }
        try? data.write(to: storageURL, options: .atomic)
    }
}

@MainActor
final class DeviceConfigurationRegistry: ObservableObject {
    @Published private(set) var supportedDevices: [DeviceCapabilityDescriptor]
    @Published private(set) var overrides: [UserStreamConfigurationOverride]
    private(set) var fallbackNotesByPath: [String: String] = [:]

    private let store: DeviceConfigurationStore

    init(store: DeviceConfigurationStore) {
        self.store = store
        self.supportedDevices = Self.makeDefaultDescriptors()
        self.overrides = store.load().overrides
    }

    var quickSessionOfflineStreams: Set<PolarOfflineStream> {
        Set([.ppi, .acc])
    }

    func effectiveSettings(deviceID: String, modeID: String, streamID: String) -> [String: StreamSettingValue] {
        guard let stream = supportedDevices
            .first(where: { $0.id == deviceID })?
            .modes.first(where: { $0.id == modeID })?
            .streams.first(where: { $0.id == streamID }) else {
            return [:]
        }

        var values = Dictionary(uniqueKeysWithValues: stream.settings.map { ($0.key, $0.defaultValue) })
        for override in overrides where override.deviceID == deviceID && override.modeID == modeID && override.streamID == streamID {
            if let definition = stream.settings.first(where: { $0.key == override.settingKey }),
               definition.allowedValues.contains(override.value) {
                values[override.settingKey] = override.value
            }
        }
        return values
    }

    func setOverride(_ value: UserStreamConfigurationOverride) {
        guard let definition = settingDefinition(
            deviceID: value.deviceID,
            modeID: value.modeID,
            streamID: value.streamID,
            settingKey: value.settingKey
        ),
        definition.allowedValues.contains(value.value) else {
            return
        }
        overrides.removeAll {
            $0.deviceID == value.deviceID &&
            $0.modeID == value.modeID &&
            $0.streamID == value.streamID &&
            $0.settingKey == value.settingKey
        }
        overrides.append(value)
        persist()
    }

    func resetDeviceToDefaults(deviceID: String) {
        overrides.removeAll { $0.deviceID == deviceID }
        persist()
    }

    func resetStreamToDefaults(deviceID: String, modeID: String, streamID: String) {
        overrides.removeAll { $0.deviceID == deviceID && $0.modeID == modeID && $0.streamID == streamID }
        persist()
    }

    func fallbackMessage(deviceID: String, modeID: String, streamID: String) -> String? {
        fallbackNotesByPath["\(deviceID).\(modeID).\(streamID)"]
    }

    func updateAccFallbackFromSDKOptions(deviceID: String, modeID: String, sampleRates: [UInt32]) {
        let path = "\(deviceID).\(modeID).acc"
        guard !sampleRates.isEmpty else { return }
        let desired: UInt32 = 26
        if sampleRates.contains(desired) {
            fallbackNotesByPath.removeValue(forKey: path)
            return
        }
        let lowerOrEqual = sampleRates.filter { $0 <= desired }.sorted()
        if let selected = lowerOrEqual.last ?? sampleRates.sorted().first {
            setOverride(
                UserStreamConfigurationOverride(
                    deviceID: deviceID,
                    modeID: modeID,
                    streamID: "acc",
                    settingKey: "sample_rate_hz",
                    value: .number(Double(selected))
                )
            )
            fallbackNotesByPath[path] = "ACC sample rate fallback applied: 26 Hz not supported by SDK for this mode; using \(selected) Hz."
        }
    }

    private func persist() {
        store.save(DeviceConfigurationSnapshot(overrides: overrides))
    }

    private static func makeDefaultDescriptors() -> [DeviceCapabilityDescriptor] {
        let accOfflineSettings = [
            StreamSettingDefinition(key: "sample_rate_hz", displayName: "Sample Rate (Hz)", defaultValue: .number(26), allowedValues: [.number(13), .number(26), .number(52)]),
            StreamSettingDefinition(key: "resolution_bit", displayName: "Resolution (bit)", defaultValue: .number(16), allowedValues: [.number(16)]),
            StreamSettingDefinition(key: "range_g", displayName: "Range (g)", defaultValue: .number(4), allowedValues: [.number(2), .number(4), .number(8), .number(16)]),
            StreamSettingDefinition(key: "channels", displayName: "Channels", defaultValue: .number(3), allowedValues: [.number(3)])
        ]
        let accOnlineSettings = [
            StreamSettingDefinition(key: "sample_rate_hz", displayName: "Sample Rate (Hz)", defaultValue: .number(52), allowedValues: [.number(26), .number(52), .number(104), .number(208), .number(416)]),
            StreamSettingDefinition(key: "resolution_bit", displayName: "Resolution (bit)", defaultValue: .number(16), allowedValues: [.number(16)]),
            StreamSettingDefinition(key: "range_g", displayName: "Range (g)", defaultValue: .number(4), allowedValues: [.number(2), .number(4), .number(8), .number(16)]),
            StreamSettingDefinition(key: "channels", displayName: "Channels", defaultValue: .number(3), allowedValues: [.number(3)])
        ]
        let ppiSettings = [
            StreamSettingDefinition(key: "enabled", displayName: "Enabled", defaultValue: .bool(true), allowedValues: [.bool(true), .bool(false)]),
            StreamSettingDefinition(key: "pp_error_threshold_ms", displayName: "PP Error Threshold (ms)", defaultValue: .number(25), allowedValues: [.number(10), .number(25), .number(50)]),
            StreamSettingDefinition(key: "blocker_handling", displayName: "Blocker Handling", defaultValue: .string("strict"), allowedValues: [.string("strict"), .string("relaxed")]),
            StreamSettingDefinition(key: "contact_handling", displayName: "Contact Handling", defaultValue: .string("on"), allowedValues: [.string("on"), .string("off")]),
            StreamSettingDefinition(key: "preserve_raw_timestamp", displayName: "Raw Timestamp", defaultValue: .bool(true), allowedValues: [.bool(true), .bool(false)]),
            StreamSettingDefinition(key: "reconstruction_mode", displayName: "Reconstruction Mode", defaultValue: .string("none"), allowedValues: [.string("none"), .string("pipeline")])
        ]
        let hrSettings = [
            StreamSettingDefinition(key: "enabled", displayName: "Enabled", defaultValue: .bool(true), allowedValues: [.bool(true), .bool(false)]),
            StreamSettingDefinition(key: "rr_interval", displayName: "R-R Interval", defaultValue: .bool(true), allowedValues: [.bool(true), .bool(false)])
        ]

        let verity = DeviceCapabilityDescriptor(
            id: "polar_verity_sense",
            displayName: "Polar Verity Sense",
            subtitle: "Offline / Online mode",
            modes: [
                DeviceModeDescriptor(
                    id: "offline",
                    displayName: "Offline Mode",
                    streams: [
                        StreamConfiguration(id: "acc", displayName: "ACC (Accelerometer)", collectorStream: .accelerometer, offlineStream: .acc, settings: accOfflineSettings),
                        StreamConfiguration(id: "ppi", displayName: "PPI (Pulse-to-Pulse Interval)", collectorStream: .ppi, offlineStream: .ppi, settings: ppiSettings)
                    ]
                ),
                DeviceModeDescriptor(
                    id: "online",
                    displayName: "Online Mode",
                    streams: [
                        StreamConfiguration(id: "hr", displayName: "HR (Heart Rate)", collectorStream: .heartRate, offlineStream: nil, settings: hrSettings),
                        StreamConfiguration(id: "acc", displayName: "ACC (Accelerometer)", collectorStream: .accelerometer, offlineStream: nil, settings: accOnlineSettings),
                        StreamConfiguration(id: "ppi", displayName: "PPI", collectorStream: .ppi, offlineStream: nil, settings: ppiSettings)
                    ]
                )
            ]
        )
        let h10 = DeviceCapabilityDescriptor(
            id: "polar_h10",
            displayName: "Polar H10",
            subtitle: "Heart Rate Monitor",
            modes: [
                DeviceModeDescriptor(
                    id: "online",
                    displayName: "Online Mode",
                    streams: [
                        StreamConfiguration(id: "hr", displayName: "HR (Heart Rate)", collectorStream: .heartRate, offlineStream: nil, settings: hrSettings),
                        StreamConfiguration(id: "acc", displayName: "ACC", collectorStream: .accelerometer, offlineStream: nil, settings: accOnlineSettings),
                        StreamConfiguration(id: "ecg", displayName: "ECG", collectorStream: .ecg, offlineStream: nil, settings: [StreamSettingDefinition(key: "enabled", displayName: "Enabled", defaultValue: .bool(true), allowedValues: [.bool(true), .bool(false)])]),
                        StreamConfiguration(id: "battery", displayName: "Battery", collectorStream: .battery, offlineStream: nil, settings: [StreamSettingDefinition(key: "enabled", displayName: "Enabled", defaultValue: .bool(true), allowedValues: [.bool(true), .bool(false)])])
                    ]
                )
            ]
        )
        return [verity, h10]
    }

    private func settingDefinition(
        deviceID: String,
        modeID: String,
        streamID: String,
        settingKey: String
    ) -> StreamSettingDefinition? {
        supportedDevices
            .first(where: { $0.id == deviceID })?
            .modes.first(where: { $0.id == modeID })?
            .streams.first(where: { $0.id == streamID })?
            .settings.first(where: { $0.key == settingKey })
    }
}

extension StreamSettingValue {
    var displayText: String {
        switch self {
        case .string(let value): return value
        case .number(let value):
            if value.rounded() == value {
                return String(Int(value))
            }
            return String(value)
        case .bool(let value): return value ? "On" : "Off"
        case .object, .array, .null: return "n/a"
        }
    }
}
