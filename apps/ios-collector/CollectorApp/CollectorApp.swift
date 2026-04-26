import Foundation
import SwiftUI

@main
struct WearableCollectorApp: App {
    private let collectorCore: CollectorCore
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let configuration = CollectorRuntimeConfiguration.from(
            environment: ProcessInfo.processInfo.environment,
            arguments: ProcessInfo.processInfo.arguments,
            bundleInfo: Bundle.main.infoDictionary
        )
        let adapter: CollectorDeviceAdapter = configuration.useMockDevice
            ? MockDeviceAdapter()
            : PolarDeviceAdapter()

        let transport = MockCollectorTransport(
            uploadEndpoint: configuration.uploadEndpoint,
            uploadConfiguration: configuration.upload
        )

        collectorCore = CollectorCore(
            adapter: adapter,
            transport: transport,
            uploadConfiguration: configuration.upload
        )
    }

    var body: some Scene {
        WindowGroup {
            CollectorView(collectorCore: collectorCore)
                .onChange(of: scenePhase) { newPhase in
                    switch newPhase {
                    case .active:
                        collectorCore.appDidBecomeActive()
                    case .background:
                        collectorCore.appDidEnterBackground()
                    default:
                        break
                    }
                }
        }
    }
}
