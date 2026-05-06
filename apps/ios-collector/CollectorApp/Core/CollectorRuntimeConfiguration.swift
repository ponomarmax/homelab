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
    let upload: CollectorUploadConfiguration

    static func from(
        environment: [String: String],
        arguments: [String],
        bundleInfo: [String: Any]? = nil
    ) -> CollectorRuntimeConfiguration {
        let uploadEndpointRawValue = environment["COLLECTOR_UPLOAD_ENDPOINT"]
            ?? (bundleInfo?["COLLECTOR_UPLOAD_ENDPOINT"] as? String)
        let uploadEndpoint = uploadEndpointRawValue.flatMap(parseUploadEndpoint)

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
}
