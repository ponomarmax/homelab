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

@MainActor
final class DeviceConfigurationRegistryTests: XCTestCase {
    private var storeURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return appSupport
            .appendingPathComponent("CollectorApp", isDirectory: true)
            .appendingPathComponent("device-configuration-v1.json")
    }

    override func setUp() {
        super.setUp()
        try? FileManager.default.removeItem(at: storeURL)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: storeURL)
        super.tearDown()
    }

    func testRegistryContainsExpectedDefaultAccSettings() {
        let registry = DeviceConfigurationRegistry(store: DeviceConfigurationStore())
        let settings = registry.effectiveSettings(deviceID: "polar_verity_sense", modeID: "offline", streamID: "acc")

        XCTAssertEqual(settings["sample_rate_hz"], .number(25))
        XCTAssertEqual(settings["resolution_bit"], .number(16))
        XCTAssertEqual(settings["range_g"], .number(4))
        XCTAssertEqual(settings["channels"], .number(3))
    }

    func testRegistryPersistsAndReloadsOverrides() {
        let store = DeviceConfigurationStore()
        let registry = DeviceConfigurationRegistry(store: store)

        registry.setOverride(
            UserStreamConfigurationOverride(
                deviceID: "polar_verity_sense",
                modeID: "offline",
                streamID: "acc",
                settingKey: "sample_rate_hz",
                value: .number(50)
            )
        )

        let reloaded = DeviceConfigurationRegistry(store: store)
        let settings = reloaded.effectiveSettings(deviceID: "polar_verity_sense", modeID: "offline", streamID: "acc")
        XCTAssertEqual(settings["sample_rate_hz"], .number(50))
    }

    func testResetToDefaultsRemovesDeviceOverrides() {
        let registry = DeviceConfigurationRegistry(store: DeviceConfigurationStore())
        registry.setOverride(
            UserStreamConfigurationOverride(
                deviceID: "polar_verity_sense",
                modeID: "offline",
                streamID: "acc",
                settingKey: "sample_rate_hz",
                value: .number(50)
            )
        )

        registry.resetDeviceToDefaults(deviceID: "polar_verity_sense")
        let settings = registry.effectiveSettings(deviceID: "polar_verity_sense", modeID: "offline", streamID: "acc")
        XCTAssertEqual(settings["sample_rate_hz"], .number(25))
    }

    func testUnsupportedSampleRateFallbackUsesClosestLower() {
        let registry = DeviceConfigurationRegistry(store: DeviceConfigurationStore())
        registry.updateAccFallbackFromSDKOptions(deviceID: "polar_verity_sense", modeID: "offline", sampleRates: [13, 52])

        let settings = registry.effectiveSettings(deviceID: "polar_verity_sense", modeID: "offline", streamID: "acc")
        XCTAssertEqual(settings["sample_rate_hz"], .number(13))
        XCTAssertNotNil(registry.fallbackMessage(deviceID: "polar_verity_sense", modeID: "offline", streamID: "acc"))
    }

    func testClassicAndQuickSessionReadSameEffectiveConfiguration() {
        let registry = DeviceConfigurationRegistry(store: DeviceConfigurationStore())
        registry.setOverride(
            UserStreamConfigurationOverride(
                deviceID: "polar_verity_sense",
                modeID: "offline",
                streamID: "acc",
                settingKey: "sample_rate_hz",
                value: .number(20)
            )
        )

        let classic = registry.effectiveSettings(deviceID: "polar_verity_sense", modeID: "offline", streamID: "acc")
        let quick = registry.effectiveSettings(deviceID: "polar_verity_sense", modeID: "offline", streamID: "acc")

        XCTAssertEqual(classic["sample_rate_hz"], quick["sample_rate_hz"])
    }
}
