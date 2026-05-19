import Foundation
import SwiftUI
import UIKit

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
        let resolvedUserID = Self.resolveCollectorUserID()
        let uploadConfiguration = CollectorUploadConfiguration(
            uploadFlushIntervalSeconds: configuration.upload.uploadFlushIntervalSeconds,
            defaultSampleCountThreshold: configuration.upload.defaultSampleCountThreshold,
            retry: configuration.upload.retry,
            streamConfigurations: configuration.upload.streamConfigurations,
            userIDHeaderValue: resolvedUserID,
            streamProfiles: configuration.upload.streamProfiles,
            requestTimeoutSeconds: configuration.upload.requestTimeoutSeconds
        )
        let adapter: CollectorDeviceAdapter = PolarDeviceAdapter()

        let transport = CollectorHTTPTransport(
            uploadEndpoint: configuration.uploadEndpoint,
            uploadConfiguration: uploadConfiguration
        )

        collectorCore = CollectorCore(
            adapter: adapter,
            transport: transport,
            uploadConfiguration: uploadConfiguration
        )
        runtimeConfiguration = configuration
    }

    private static func resolveCollectorUserID() -> String {
        if let explicit = ProcessInfo.processInfo.environment["COLLECTOR_USER_ID"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !explicit.isEmpty {
            return explicit
        }
        if let byVendor = UIDevice.current.identifierForVendor?.uuidString.lowercased(),
           !byVendor.isEmpty {
            return byVendor
        }
        return "ios-unknown-device"
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
