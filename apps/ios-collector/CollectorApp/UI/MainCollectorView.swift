import SwiftUI

struct MainCollectorView: View {
    @StateObject private var collectorCore: CollectorCore
    @StateObject private var nightSessionViewModel: NightSessionViewModel

    init(collectorCore: CollectorCore, pipelineEndpoint: URL?, dashboardEndpoint: URL?) {
        _collectorCore = StateObject(wrappedValue: collectorCore)
        let workflow = SessionWorkflowCoordinator(
            core: collectorCore,
            pipelineEndpoint: pipelineEndpoint,
            dashboardEndpoint: dashboardEndpoint
        )
        _nightSessionViewModel = StateObject(wrappedValue: NightSessionViewModel(coordinator: workflow))
    }

    var body: some View {
        TabView {
            CollectorView(collectorCore: collectorCore, nightSessionViewModel: nightSessionViewModel)
                .tabItem {
                    Label("Classic", systemImage: "list.bullet.rectangle")
                }

            QuickSessionTestView(collectorCore: collectorCore, viewModel: nightSessionViewModel)
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
                        HStack(spacing: 8) {
                            if collectorCore.isScanningDevices || collectorCore.isConnectingDevice {
                                ProgressView().controlSize(.small)
                            }
                            Text(connectionStatusLine)
                                .font(.caption)
                        }
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
                        if let error = collectorCore.lastErrorMessage, !error.isEmpty {
                            Text("Last error: \(error)")
                                .font(.caption2)
                                .foregroundStyle(.red)
                        }
                        Button("Retry auto-connect") {
                            Task { await collectorCore.autoConnectToRememberedDevice() }
                        }
                        .buttonStyle(.bordered)
                        .disabled(collectorCore.isScanningDevices || collectorCore.isConnectingDevice)
                    }
                }

                SessionControlCard(viewModel: viewModel)
                SessionStatusCard(viewModel: viewModel)
                UploadStatusCard(collectorCore: collectorCore)
                PipelineStatusCard(viewModel: viewModel)
                GroupBox("Logs") {
                    VStack(alignment: .leading, spacing: 8) {
                        Button("Prepare log export") {
                            collectorCore.prepareLogExportFile()
                        }
                        .buttonStyle(.bordered)
                        if let exportURL = collectorCore.logExportFileURL {
                            ShareLink(item: exportURL) {
                                Text("Share snapshot log")
                            }
                        }
                        if let persistentURL = collectorCore.persistentLogFileURL {
                            ShareLink(item: persistentURL) {
                                Text("Share full app log")
                            }
                        }
                    }
                }

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

    private var connectionStatusLine: String {
        if collectorCore.isScanningDevices {
            return "Scanning for remembered device..."
        }
        if collectorCore.isConnectingDevice {
            return "Connecting to device..."
        }
        if collectorCore.status == .connected {
            return "Connected"
        }
        if collectorCore.selectedDevice != nil {
            return "Device selected, ready to connect"
        }
        if collectorCore.rememberedDevice != nil {
            return "Waiting for remembered device advertisement"
        }
        return "No remembered device configured"
    }
}
