import SwiftUI

@main
struct WearableCollectorApp: App {
    var body: some Scene {
        WindowGroup {
            CollectorView(
                collectorCore: CollectorCore(
                    adapter: MockDeviceAdapter(),
                    transport: MockCollectorTransport()
                )
            )
        }
    }
}
