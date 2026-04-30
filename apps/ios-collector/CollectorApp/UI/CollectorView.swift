import SwiftUI

struct CollectorView: View {
    @StateObject private var collectorCore: CollectorCore
    @State private var selectedTab: PolarScreenTab = .online

    init(collectorCore: CollectorCore) {
        _collectorCore = StateObject(wrappedValue: collectorCore)
    }

    var body: some View {
        NavigationStack {
            Group {
                if collectorCore.status == .collecting || collectorCore.status == .stopped {
                    polarDeviceScreen
                } else {
                    scanScreen
                }
            }
            .navigationTitle("Wearable Polar Collector")
            .background(Color(.systemGroupedBackground))
        }
    }

    private var scanScreen: some View {
        VStack(alignment: .leading, spacing: 16) {
            activityCard
            Button(collectorCore.isScanningDevices ? "Scanning..." : "Scan devices") {
                Task { await collectorCore.scanAndSelectDevice() }
            }
            .buttonStyle(.borderedProminent)
            .disabled(collectorCore.isScanningDevices || collectorCore.isConnectingDevice)

            Text("Discovered Devices")
                .font(.headline)

            if collectorCore.discoveredDevices.isEmpty {
                Text("Start scan to discover Polar devices.")
                    .foregroundStyle(.secondary)
            } else {
                List(collectorCore.discoveredDevices) { device in
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(device.name).fontWeight(.medium)
                            Text("\(device.vendor) • \(device.model)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(device.id)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Connect") {
                            collectorCore.selectScannedDevice(device)
                            Task {
                                await collectorCore.startCollection()
                            }
                        }
                        .buttonStyle(.bordered)
                        .disabled(collectorCore.isScanningDevices || collectorCore.isConnectingDevice)
                    }
                }
                .listStyle(.plain)
            }

            Spacer()
        }
        .padding()
    }

    private var polarDeviceScreen: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(collectorCore.selectedDevice?.name ?? "Polar Device")
                        .font(.title3.weight(.semibold))
                    Text(collectorCore.polarCapabilities.family.rawValue)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Disconnect") {
                    collectorCore.stopCollection()
                }
                .buttonStyle(.bordered)
            }

            Picker("Section", selection: $selectedTab) {
                ForEach(PolarScreenTab.allCases) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)

            switch selectedTab {
            case .online:
                onlineTab
            case .offline:
                offlineTab
            case .device:
                deviceTab
            }

            Spacer()
        }
        .padding()
    }

    private var onlineTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Online Streams")
                    .font(.headline)

                ForEach(CollectorStream.allCases.filter { $0 != .eeg }, id: \.id) { stream in
                    let available = collectorCore.polarCapabilities.availableOnlineStreams.contains(stream)
                    HStack {
                        Text(stream.displayName)
                        Spacer()
                        Button(collectorCore.selectedOnlineStreams.contains(stream) ? "Enabled" : "Disabled") {
                            collectorCore.toggleOnlineStream(stream)
                        }
                        .buttonStyle(.bordered)
                        .disabled(!available || collectorCore.status == .collecting)
                    }
                    .opacity(available ? 1.0 : 0.45)
                }

                HStack(spacing: 12) {
                    Button(collectorCore.isConnectingDevice ? "Connecting..." : "Start") {
                        Task { await collectorCore.startCollection() }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(collectorCore.isConnectingDevice || collectorCore.isScanningDevices || collectorCore.status == .collecting)

                    Button("Stop") {
                        collectorCore.stopCollection()
                    }
                    .buttonStyle(.bordered)
                    .disabled(collectorCore.status != .collecting)
                }

                diagnosticsCard
                logsCard
            }
        }
    }

    private var offlineTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Offline Recording (foundation only)")
                .font(.headline)
            Text("Offline fetch/upload/delete is intentionally not implemented in this task.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            ForEach(PolarOfflineStream.allCases) { stream in
                let supported = collectorCore.polarCapabilities.availableOfflineStreams.contains(stream)
                HStack {
                    Text(stream.rawValue)
                    Spacer()
                    Text(supported ? "Supported" : "Unavailable")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .opacity(supported ? 1 : 0.45)
            }

            HStack(spacing: 8) {
                offlineButton("Start selected")
                offlineButton("Start all")
            }
            HStack(spacing: 8) {
                offlineButton("Stop selected")
                offlineButton("Stop all")
            }
            HStack(spacing: 8) {
                offlineButton("List recordings")
                offlineButton("Sync recordings")
            }
        }
    }

    private var deviceTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            statusRow(title: "State", value: collectorCore.status.displayName)
            statusRow(title: "Battery", value: collectorCore.selectedDeviceBatteryDisplayText())
            statusRow(title: "Upload", value: collectorCore.uploadStatus.displayName)

            Button("Sync Time (placeholder)") {}
                .buttonStyle(.bordered)
                .disabled(!collectorCore.polarCapabilities.supportsManualTimeSync)
        }
    }

    private func offlineButton(_ title: String) -> some View {
        Button(title) {}
            .buttonStyle(.bordered)
            .disabled(true)
    }

    private var activityCard: some View {
        HStack(spacing: 12) {
            if collectorCore.isScanningDevices || collectorCore.isConnectingDevice || collectorCore.isPreparingChunk || collectorCore.isUploadingChunk {
                ProgressView().controlSize(.small)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Activity").font(.caption).foregroundStyle(.secondary)
                Text(collectorCore.activityMessage).font(.subheadline.weight(.medium))
            }
            Spacer()
        }
        .padding()
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func statusRow(title: String, value: String) -> some View {
        HStack {
            Text(title).foregroundStyle(.secondary)
            Spacer()
            Text(value)
        }
        .font(.footnote)
    }

    private var diagnosticsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Diagnostics").font(.headline)
            statusRow(title: "Buffered Samples", value: "\(collectorCore.bufferedSamplesCount)")
            statusRow(title: "Pending Chunks", value: "\(collectorCore.pendingUploadChunksCount)")
            statusRow(title: "Total Samples", value: "\(collectorCore.totalSamplesReceived)")
            if let lastErrorMessage = collectorCore.lastErrorMessage {
                Text(lastErrorMessage).font(.footnote).foregroundStyle(.red)
            }
        }
        .padding()
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var logsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Logs").font(.headline)
            if collectorCore.eventLogs.isEmpty {
                Text("No logs yet").font(.footnote).foregroundStyle(.secondary)
            } else {
                ForEach(Array(collectorCore.eventLogs.suffix(8).enumerated()), id: \.offset) { _, line in
                    Text(line)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .padding()
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private enum PolarScreenTab: String, CaseIterable, Identifiable {
    case online = "Online"
    case offline = "Offline"
    case device = "Device"

    var id: String { rawValue }
}
