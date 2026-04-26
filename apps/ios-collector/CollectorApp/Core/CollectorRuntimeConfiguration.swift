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
    let source: Source
    let collection: Collection
    let deviceTimeReference: String
    let transport: Transport

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case streamType = "stream_type"
        case source
        case collection
        case deviceTimeReference = "device_time_reference"
        case transport
    }

    func streamID(for sessionID: UUID) -> String {
        "stream-\(streamType)-\(sessionID.uuidString.lowercased())"
    }
}

enum PolarHrStreamProfile {
    static let live = StreamMetadataProfile(
        schemaVersion: "1.0",
        streamType: "hr",
        source: StreamMetadataProfile.Source(
            vendor: "polar",
            deviceModel: "verity_sense",
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
}

struct CollectorUploadConfiguration: Equatable, Sendable {
    let autoFlushSampleCount: Int
    let autoFlushIntervalSeconds: TimeInterval
    let userIDHeaderValue: String
    let streamProfile: StreamMetadataProfile

    static let `default` = CollectorUploadConfiguration(
        autoFlushSampleCount: 20,
        autoFlushIntervalSeconds: 30,
        userIDHeaderValue: "2",
        streamProfile: PolarHrStreamProfile.live
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
