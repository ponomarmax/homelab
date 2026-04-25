import Foundation

struct CollectorRuntimeConfiguration {
    let useMockDevice: Bool
    let uploadEndpoint: URL?

    static func from(
        environment: [String: String],
        arguments: [String]
    ) -> CollectorRuntimeConfiguration {
        let useMockDevice = environment["COLLECTOR_USE_MOCK"] == "1" || arguments.contains("--mock")
        let uploadEndpoint = environment["COLLECTOR_UPLOAD_ENDPOINT"].flatMap(parseUploadEndpoint)

        return CollectorRuntimeConfiguration(
            useMockDevice: useMockDevice,
            uploadEndpoint: uploadEndpoint
        )
    }

    private static func parseUploadEndpoint(_ rawValue: String) -> URL? {
        guard let components = URLComponents(string: rawValue) else { return nil }
        guard let scheme = components.scheme?.lowercased(), ["http", "https"].contains(scheme) else {
            return nil
        }
        guard let host = components.host, !host.isEmpty else { return nil }
        return components.url
    }
}
