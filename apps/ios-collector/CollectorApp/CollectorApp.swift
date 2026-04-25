import Foundation
import SwiftUI

@main
struct WearableCollectorApp: App {
    private let collectorCore: CollectorCore

    init() {
        let environment = ProcessInfo.processInfo.environment
        let arguments = ProcessInfo.processInfo.arguments
        let useMock = environment["COLLECTOR_USE_MOCK"] == "1" || arguments.contains("--mock")

        let adapter: CollectorDeviceAdapter = useMock ? MockDeviceAdapter() : PolarDeviceAdapter()

        collectorCore = CollectorCore(
            adapter: adapter,
            transport: MockCollectorTransport()
        )
    }

    var body: some Scene {
        WindowGroup {
            CollectorView(collectorCore: collectorCore)
        }
    }
}
