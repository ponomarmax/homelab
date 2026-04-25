import Foundation

struct CollectorRuntimeConfiguration {
    let useMockDevice: Bool
    let uploadEndpoint: URL?

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
            uploadEndpoint: uploadEndpoint
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
