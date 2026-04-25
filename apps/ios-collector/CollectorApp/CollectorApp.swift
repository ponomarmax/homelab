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

        let uploadEndpoint = environment["COLLECTOR_UPLOAD_ENDPOINT"].flatMap { URL(string: $0) }
        let transport = MockCollectorTransport(uploadEndpoint: uploadEndpoint)

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
