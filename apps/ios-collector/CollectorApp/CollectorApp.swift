import Foundation
import SwiftUI

@main
struct WearableCollectorApp: App {
    private let collectorCore: CollectorCore
    private let runtimeConfiguration: CollectorRuntimeConfiguration
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let configuration = CollectorRuntimeConfiguration.from(
            environment: ProcessInfo.processInfo.environment,
            arguments: ProcessInfo.processInfo.arguments,
            bundleInfo: Bundle.main.infoDictionary
        )
        let adapter: CollectorDeviceAdapter = PolarDeviceAdapter()

        let transport = CollectorHTTPTransport(
            uploadEndpoint: configuration.uploadEndpoint,
            uploadConfiguration: configuration.upload
        )

        collectorCore = CollectorCore(
            adapter: adapter,
            transport: transport,
            uploadConfiguration: configuration.upload
        )
        runtimeConfiguration = configuration
    }

    var body: some Scene {
        WindowGroup {
            MainCollectorView(
                collectorCore: collectorCore,
                pipelineEndpoint: runtimeConfiguration.pipelineEndpoint,
                dashboardEndpoint: runtimeConfiguration.dashboardEndpoint
            )
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
