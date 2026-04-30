import XCTest
@testable import CollectorApp

final class CollectorRuntimeConfigurationTests: XCTestCase {
    func testConfigurationUsesInfoPlistDefaultsWhenNoOverridesProvided() {
        let configuration = CollectorRuntimeConfiguration.from(
            environment: [:],
            arguments: [],
            bundleInfo: [
                "COLLECTOR_UPLOAD_ENDPOINT": "http://192.168.0.5:18090/"
            ]
        )

        XCTAssertEqual(
            configuration.uploadEndpoint,
            URL(string: "http://192.168.0.5:18090/upload-chunk")
        )
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

    func testUploadFlushIntervalDefaultsToSixtySeconds() {
        let configuration = CollectorRuntimeConfiguration.from(
            environment: [:],
            arguments: [],
            bundleInfo: nil
        )

        XCTAssertEqual(configuration.upload.uploadFlushIntervalSeconds, 60)
    }

    func testUploadFlushIntervalCanBeOverriddenByEnvironment() {
        let configuration = CollectorRuntimeConfiguration.from(
            environment: ["COLLECTOR_UPLOAD_FLUSH_INTERVAL_SECONDS": "15"],
            arguments: [],
            bundleInfo: nil
        )

        XCTAssertEqual(configuration.upload.uploadFlushIntervalSeconds, 15)
    }
}
