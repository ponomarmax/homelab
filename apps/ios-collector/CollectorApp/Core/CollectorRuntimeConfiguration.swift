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

enum PolarStreamProfile {
    static let hrLive = StreamMetadataProfile(
        schemaVersion: "1.0",
        streamType: "hr",
        streamIDPrefix: "hr",
        source: StreamMetadataProfile.Source(
            vendor: "polar",
            deviceModel: "Polar H10",
            deviceID: nil
        ),
        collection: StreamMetadataProfile.Collection(mode: "online_live"),
        deviceTimeReference: "collector:collectorObserved",
        transport: StreamMetadataProfile.Transport(
            encoding: "json",
            compression: "none",
            payloadSchema: "polar.hr",
            payloadVersion: "1.0"
        )
    )

    static let ecgLive = StreamMetadataProfile(
        schemaVersion: "1.0",
        streamType: "ecg",
        streamIDPrefix: "ecg",
        source: StreamMetadataProfile.Source(
            vendor: "polar",
            deviceModel: "Polar H10",
            deviceID: nil
        ),
        collection: StreamMetadataProfile.Collection(mode: "online_live"),
        deviceTimeReference: "polar:ns_since_2000_epoch",
        transport: StreamMetadataProfile.Transport(
            encoding: "json",
            compression: "none",
            payloadSchema: "polar.ecg",
            payloadVersion: "1.0"
        )
    )

    static let accLive = StreamMetadataProfile(
        schemaVersion: "1.0",
        streamType: "acc",
        streamIDPrefix: "acc",
        source: StreamMetadataProfile.Source(
            vendor: "polar",
            deviceModel: "Polar H10",
            deviceID: nil
        ),
        collection: StreamMetadataProfile.Collection(mode: "online_live"),
        deviceTimeReference: "polar:ns_since_2000_epoch",
        transport: StreamMetadataProfile.Transport(
            encoding: "json",
            compression: "none",
            payloadSchema: "polar.acc",
            payloadVersion: "1.0"
        )
    )

    static let batteryLive = StreamMetadataProfile(
        schemaVersion: "1.0",
        streamType: "unknown",
        streamIDPrefix: "battery",
        source: StreamMetadataProfile.Source(
            vendor: "polar",
            deviceModel: "Polar H10",
            deviceID: nil
        ),
        collection: StreamMetadataProfile.Collection(mode: "online_live"),
        deviceTimeReference: "collector:collectorObserved",
        transport: StreamMetadataProfile.Transport(
            encoding: "json",
            compression: "none",
            payloadSchema: "polar.device_battery",
            payloadVersion: "1.0"
        )
    )
}

struct CollectorUploadConfiguration: Equatable, Sendable {
    let autoFlushSampleCount: Int
    let autoFlushIntervalSeconds: TimeInterval
    let userIDHeaderValue: String
    let streamProfiles: [CollectorStream: StreamMetadataProfile]

    var streamProfile: StreamMetadataProfile {
        streamProfile(for: .heartRate)
    }

    func streamProfile(for stream: CollectorStream) -> StreamMetadataProfile {
        streamProfiles[stream] ?? PolarStreamProfile.hrLive
    }

    func sampleFlushCount(for stream: CollectorStream) -> Int {
        switch stream {
        case .heartRate:
            return autoFlushSampleCount
        case .ecg:
            return 260
        case .accelerometer:
            return 200
        case .battery:
            return 1
        default:
            return autoFlushSampleCount
        }
    }

    static let `default` = CollectorUploadConfiguration(
        autoFlushSampleCount: 20,
        autoFlushIntervalSeconds: 30,
        userIDHeaderValue: "2",
        streamProfiles: [
            .heartRate: PolarStreamProfile.hrLive,
            .ecg: PolarStreamProfile.ecgLive,
            .accelerometer: PolarStreamProfile.accLive,
            .battery: PolarStreamProfile.batteryLive
        ]
    )
}

struct CollectorRuntimeConfiguration {
    let useMockDevice: Bool
    let uploadEndpoint: URL?
    let upload: CollectorUploadConfiguration

    static func from(
        environment: [String: String],
        arguments: [String],
        bundleInfo: [String: Any]? = nil
    ) -> CollectorRuntimeConfiguration {
        let defaultUseMockDevice = (bundleInfo?["COLLECTOR_USE_MOCK_DEFAULT"] as? Bool) ?? false
        let useMockDeviceFromEnvironment = environment["COLLECTOR_USE_MOCK"].flatMap(parseBoolean)

        let useMockDevice: Bool
        if arguments.contains("--mock") {
            useMockDevice = true
        } else if arguments.contains("--real") {
            useMockDevice = false
        } else if let useMockDeviceFromEnvironment {
            useMockDevice = useMockDeviceFromEnvironment
        } else {
            useMockDevice = defaultUseMockDevice
        }

        let uploadEndpointRawValue = environment["COLLECTOR_UPLOAD_ENDPOINT"]
            ?? (bundleInfo?["COLLECTOR_UPLOAD_ENDPOINT"] as? String)
        let uploadEndpoint = uploadEndpointRawValue.flatMap(parseUploadEndpoint)

        return CollectorRuntimeConfiguration(
            useMockDevice: useMockDevice,
            uploadEndpoint: uploadEndpoint,
            upload: .default
        )
    }

    private static func parseBoolean(_ rawValue: String) -> Bool? {
        switch rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "1", "true", "yes", "on":
            return true
        case "0", "false", "no", "off":
            return false
        default:
            return nil
        }
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
