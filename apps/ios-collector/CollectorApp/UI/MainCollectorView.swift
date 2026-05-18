import SwiftUI

struct MainCollectorView: View {
    @StateObject private var collectorCore: CollectorCore
    @StateObject private var nightSessionViewModel: NightSessionViewModel
    @StateObject private var quickSessionViewModel: NightSessionViewModel

    init(collectorCore: CollectorCore, pipelineEndpoint: URL?, dashboardEndpoint: URL?) {
        _collectorCore = StateObject(wrappedValue: collectorCore)
        let workflow = SessionWorkflowCoordinator(
            core: collectorCore,
            pipelineEndpoint: pipelineEndpoint,
            dashboardEndpoint: dashboardEndpoint
        )
        _nightSessionViewModel = StateObject(wrappedValue: NightSessionViewModel(coordinator: workflow))
        _quickSessionViewModel = StateObject(wrappedValue: NightSessionViewModel(coordinator: workflow))
    }

    var body: some View {
        TabView {
            CollectorView(collectorCore: collectorCore, nightSessionViewModel: nightSessionViewModel)
                .tabItem {
                    Label("Classic", systemImage: "list.bullet.rectangle")
                }

            QuickSessionTestView(collectorCore: collectorCore, viewModel: quickSessionViewModel)
                .tabItem {
                    Label("Quick Session (Test)", systemImage: "bolt.heart")
                }
        }
    }
}

private struct QuickSessionTestView: View {
    @ObservedObject var collectorCore: CollectorCore
    @ObservedObject var viewModel: NightSessionViewModel
    @State private var autoConnectAttempted = false

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                GroupBox("Remembered Device") {
                    VStack(alignment: .leading, spacing: 6) {
                        if let remembered = collectorCore.rememberedDevice {
                            Text(remembered.name)
                                .font(.headline)
                            Text("\(remembered.vendor) • \(remembered.model)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("ID: \(remembered.id)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text("Saved: \(remembered.updatedAtUTC.formatted())")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        } else {
                            Text("No remembered device yet.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                GroupBox("Connection") {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Status: \(collectorCore.status.displayName)")
                            .font(.caption)
                        Text("Device: \(collectorCore.selectedDevice?.name ?? "Not selected")")
                            .font(.caption)
                        Text("Device ID: \(collectorCore.selectedDevice?.id ?? "n/a")")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        if collectorCore.status != .connected {
                            Text("Auto-connect runs when opening this screen.")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                SessionControlCard(viewModel: viewModel)
                SessionStatusCard(viewModel: viewModel)
                PipelineStatusCard(viewModel: viewModel)

                if let dashboardURL = viewModel.dashboardURL, let url = URL(string: dashboardURL) {
                    Link("Open Session URL", destination: url)
                        .font(.headline)
                }

                Spacer()
            }
            .padding()
            .navigationTitle("Quick Session (Test)")
            .task {
                guard !autoConnectAttempted else { return }
                autoConnectAttempted = true
                await collectorCore.autoConnectToRememberedDevice()
            }
        }
    }
}
