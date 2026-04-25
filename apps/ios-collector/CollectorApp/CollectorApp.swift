import Foundation
import SwiftUI

@main
struct WearableCollectorApp: App {
    private let collectorCore: CollectorCore

    init() {
        let configuration = CollectorRuntimeConfiguration.from(
            environment: ProcessInfo.processInfo.environment,
            arguments: ProcessInfo.processInfo.arguments,
            bundleInfo: Bundle.main.infoDictionary
        )
        let adapter: CollectorDeviceAdapter = configuration.useMockDevice
            ? MockDeviceAdapter()
            : PolarDeviceAdapter()

        let transport = MockCollectorTransport(uploadEndpoint: configuration.uploadEndpoint)

        collectorCore = CollectorCore(
            adapter: adapter,
            transport: transport
        )
    }

    var body: some Scene {
        WindowGroup {
            CollectorView(collectorCore: collectorCore)
        }
    }
}
