import XCTest
@testable import CollectorApp

final class CollectorRuntimeConfigurationTests: XCTestCase {
    func testConfigurationUsesInfoPlistDefaultsWhenNoOverridesProvided() {
        let configuration = CollectorRuntimeConfiguration.from(
            environment: [:],
            arguments: [],
            bundleInfo: [
                "COLLECTOR_USE_MOCK_DEFAULT": false,
                "COLLECTOR_UPLOAD_ENDPOINT": "http://192.168.0.5:18090/"
            ]
        )

        XCTAssertFalse(configuration.useMockDevice)
        XCTAssertEqual(
            configuration.uploadEndpoint,
            URL(string: "http://192.168.0.5:18090/upload-chunk")
        )
    }

    func testConfigurationUsesMockWhenEnvironmentFlagIsSet() {
        let configuration = CollectorRuntimeConfiguration.from(
            environment: ["COLLECTOR_USE_MOCK": "1"],
            arguments: [],
            bundleInfo: ["COLLECTOR_USE_MOCK_DEFAULT": false]
        )

        XCTAssertTrue(configuration.useMockDevice)
    }

    func testConfigurationUsesMockWhenArgumentFlagIsPresent() {
        let configuration = CollectorRuntimeConfiguration.from(
            environment: [:],
            arguments: ["CollectorApp", "--mock"],
            bundleInfo: ["COLLECTOR_USE_MOCK_DEFAULT": false]
        )

        XCTAssertTrue(configuration.useMockDevice)
    }

    func testConfigurationUsesRealWhenRealArgumentFlagIsPresent() {
        let configuration = CollectorRuntimeConfiguration.from(
            environment: ["COLLECTOR_USE_MOCK": "1"],
            arguments: ["CollectorApp", "--real"],
            bundleInfo: ["COLLECTOR_USE_MOCK_DEFAULT": true]
        )

        XCTAssertFalse(configuration.useMockDevice)
    }

    func testConfigurationParsesUploadEndpointURL() {
        let configuration = CollectorRuntimeConfiguration.from(
            environment: ["COLLECTOR_UPLOAD_ENDPOINT": "http://localhost:8080/ingest/wearable/chunk"],
            arguments: [],
            bundleInfo: nil
        )

        XCTAssertEqual(
            configuration.uploadEndpoint,
            URL(string: "http://localhost:8080/ingest/wearable/chunk")
        )
    }

    func testConfigurationIgnoresInvalidUploadEndpoint() {
        let configuration = CollectorRuntimeConfiguration.from(
            environment: ["COLLECTOR_UPLOAD_ENDPOINT": "not a url"],
            arguments: [],
            bundleInfo: nil
        )

        XCTAssertNil(configuration.uploadEndpoint)
    }
}
