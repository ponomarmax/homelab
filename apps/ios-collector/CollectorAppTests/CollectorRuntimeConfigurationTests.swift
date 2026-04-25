import XCTest
@testable import CollectorApp

final class CollectorRuntimeConfigurationTests: XCTestCase {
    func testConfigurationUsesMockWhenEnvironmentFlagIsSet() {
        let configuration = CollectorRuntimeConfiguration.from(
            environment: ["COLLECTOR_USE_MOCK": "1"],
            arguments: []
        )

        XCTAssertTrue(configuration.useMockDevice)
    }

    func testConfigurationUsesMockWhenArgumentFlagIsPresent() {
        let configuration = CollectorRuntimeConfiguration.from(
            environment: [:],
            arguments: ["CollectorApp", "--mock"]
        )

        XCTAssertTrue(configuration.useMockDevice)
    }

    func testConfigurationParsesUploadEndpointURL() {
        let configuration = CollectorRuntimeConfiguration.from(
            environment: ["COLLECTOR_UPLOAD_ENDPOINT": "http://localhost:8080/ingest/wearable/chunk"],
            arguments: []
        )

        XCTAssertEqual(
            configuration.uploadEndpoint,
            URL(string: "http://localhost:8080/ingest/wearable/chunk")
        )
    }

    func testConfigurationIgnoresInvalidUploadEndpoint() {
        let configuration = CollectorRuntimeConfiguration.from(
            environment: ["COLLECTOR_UPLOAD_ENDPOINT": "not a url"],
            arguments: []
        )

        XCTAssertNil(configuration.uploadEndpoint)
    }
}
