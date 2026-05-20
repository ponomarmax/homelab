import SwiftUI

struct MainCollectorView: View {
    @StateObject private var collectorCore: CollectorCore
    @StateObject private var quickSessionViewModel: NightSessionViewModel

    init(collectorCore: CollectorCore, pipelineEndpoint: URL?, dashboardEndpoint: URL?) {
        _collectorCore = StateObject(wrappedValue: collectorCore)
        let workflow = SessionWorkflowCoordinator(
            core: collectorCore,
            pipelineEndpoint: pipelineEndpoint,
            dashboardEndpoint: dashboardEndpoint
        )
        _quickSessionViewModel = StateObject(wrappedValue: NightSessionViewModel(coordinator: workflow))
    }

    var body: some View {
        TabView {
            ClassicCollectorTab(
                collectorCore: collectorCore,
                quickSessionViewModel: quickSessionViewModel,
                configurationRegistry: collectorCore.configurationRegistry
            )
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

private struct ClassicCollectorTab: View {
    @ObservedObject var collectorCore: CollectorCore
    @ObservedObject var quickSessionViewModel: NightSessionViewModel
    @ObservedObject var configurationRegistry: DeviceConfigurationRegistry
    @State private var expandedDevices: Set<String> = []
    @State private var expandedModes: Set<String> = []
    @State private var expandedStreams: Set<String> = []
    @State private var showDeviceManagement: Bool = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    topControlCard
                    supportedDevicesCard
                    configurationCard
                    Text("Configuration is stored locally and synced across the app.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding()
            }
            .navigationTitle("Wearable Polar Collector")
            .background(Color(.systemGroupedBackground))
            .sheet(isPresented: $showDeviceManagement) {
                CollectorView(
                    collectorCore: collectorCore,
                    nightSessionViewModel: quickSessionViewModel
                )
            }
        }
    }

    private var topControlCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Activity")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(collectorCore.activityMessage)
                            .font(.subheadline.weight(.semibold))
                    }
                    Spacer()
                    Text(statusChip)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.green)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color.green.opacity(0.15))
                        .clipShape(Capsule())
                }
                HStack(spacing: 8) {
                    Button(collectorCore.isScanningDevices ? "Scanning..." : "Scan") {
                        Task { await collectorCore.scanAndSelectDevice() }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(collectorCore.isScanningDevices || collectorCore.isConnectingDevice)

                    Button("Management") {
                        showDeviceManagement = true
                    }
                    .buttonStyle(.bordered)
                    .disabled(collectorCore.selectedDevice == nil)
                }
                if !collectorCore.discoveredDevices.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(collectorCore.discoveredDevices) { device in
                                let connectability = collectorCore.connectability(for: device)
                                Button {
                                    collectorCore.selectScannedDevice(device)
                                    Task { await collectorCore.connectSelectedDevice() }
                                } label: {
                                    Text(device.name)
                                        .font(.caption)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 6)
                                }
                                .buttonStyle(.bordered)
                                .disabled(!connectability.isConnectable || collectorCore.isConnectingDevice)
                            }
                        }
                    }
                }
            }
        }
    }

    private var supportedDevicesCard: some View {
        GroupBox("Supported Devices") {
            VStack(spacing: 10) {
                supportedDeviceRow(
                    title: "Polar Verity Sense",
                    subtitle: "Offline / Online mode",
                    key: "polar_verity_sense"
                )
                Divider()
                supportedDeviceRow(
                    title: "Polar H10",
                    subtitle: "Heart Rate Monitor",
                    key: "polar_h10"
                )
            }
            .padding(.top, 4)
        }
    }

    private func supportedDeviceRow(title: String, subtitle: String, key: String) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Configure") {
                expandedDevices.insert(key)
            }
            .buttonStyle(.bordered)
        }
    }

    private var configurationCard: some View {
        GroupBox("Default Stream Configuration") {
            VStack(alignment: .leading, spacing: 12) {
                Text("Set default parameters for streams. These values are used for all sessions unless overridden.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                ForEach(configurationRegistry.supportedDevices, id: \.id) { device in
                    deviceSection(device)
                }
            }
            .padding(.top, 4)
        }
    }

    private func deviceSection(_ device: DeviceCapabilityDescriptor) -> some View {
        let deviceExpanded = expandedDevices.contains(device.id)
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Button {
                    toggle(expanded: &expandedDevices, key: device.id)
                } label: {
                    Image(systemName: deviceExpanded ? "chevron.down" : "chevron.right")
                }
                .buttonStyle(.plain)
                VStack(alignment: .leading, spacing: 2) {
                    Text(device.displayName).font(.headline)
                    Text(device.subtitle).font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Reset to Defaults") {
                    configurationRegistry.resetDeviceToDefaults(deviceID: device.id)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.blue)
            }

            if deviceExpanded {
                ForEach(device.modes, id: \.id) { mode in
                    modeSection(device: device, mode: mode)
                }
            }
        }
        .padding(10)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func modeSection(device: DeviceCapabilityDescriptor, mode: DeviceModeDescriptor) -> some View {
        let key = "\(device.id).\(mode.id)"
        let modeExpanded = expandedModes.contains(key)
        return VStack(alignment: .leading, spacing: 8) {
            Button {
                toggle(expanded: &expandedModes, key: key)
            } label: {
                HStack {
                    Image(systemName: modeExpanded ? "chevron.down" : "chevron.right")
                    Text(mode.displayName).font(.headline)
                    Spacer()
                }
            }
            .buttonStyle(.plain)

            if modeExpanded {
                ForEach(mode.streams, id: \.id) { stream in
                    streamSection(device: device, mode: mode, stream: stream)
                }
            }
        }
    }

    private func streamSection(device: DeviceCapabilityDescriptor, mode: DeviceModeDescriptor, stream: StreamConfiguration) -> some View {
        let key = "\(device.id).\(mode.id).\(stream.id)"
        let streamExpanded = expandedStreams.contains(key)
        return VStack(alignment: .leading, spacing: 8) {
            Button {
                toggle(expanded: &expandedStreams, key: key)
            } label: {
                HStack {
                    Image(systemName: streamExpanded ? "chevron.down" : "chevron.right")
                    Text(stream.displayName).font(.headline)
                    Spacer()
                }
            }
            .buttonStyle(.plain)

            if streamExpanded {
                let effective = configurationRegistry.effectiveSettings(
                    deviceID: device.id,
                    modeID: mode.id,
                    streamID: stream.id
                )
                ForEach(stream.settings, id: \.key) { definition in
                    settingRow(
                        definition: definition,
                        value: effective[definition.key] ?? definition.defaultValue,
                        onSelect: { newValue in
                            configurationRegistry.setOverride(
                                UserStreamConfigurationOverride(
                                    deviceID: device.id,
                                    modeID: mode.id,
                                    streamID: stream.id,
                                    settingKey: definition.key,
                                    value: newValue
                                )
                            )
                        }
                    )
                }

                HStack {
                    Button("Reset Stream") {
                        configurationRegistry.resetStreamToDefaults(deviceID: device.id, modeID: mode.id, streamID: stream.id)
                    }
                    .font(.caption)
                    .buttonStyle(.borderless)
                    Spacer()
                }

                if let fallback = configurationRegistry.fallbackMessage(deviceID: device.id, modeID: mode.id, streamID: stream.id) {
                    Text(fallback)
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
        }
        .padding(10)
        .background(Color(.tertiarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func settingRow(definition: StreamSettingDefinition, value: StreamSettingValue, onSelect: @escaping (StreamSettingValue) -> Void) -> some View {
        HStack {
            Text(definition.displayName)
                .font(.subheadline)
            Spacer()
            Menu(value.displayText) {
                ForEach(definition.allowedValues, id: \.self) { option in
                    Button(option.displayText) {
                        onSelect(option)
                    }
                }
            }
        }
    }

    private func toggle(expanded: inout Set<String>, key: String) {
        if expanded.contains(key) {
            expanded.remove(key)
        } else {
            expanded.insert(key)
        }
    }

    private var statusChip: String {
        switch collectorCore.status {
        case .connected, .collecting, .stopped: return "Ready"
        default: return "Idle"
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
                GroupBox("Quick Session Status") {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Connection: \(connectionStatusLine)")
                            .font(.caption)
                        Text("Active streams: \(quickStreamsLabel)")
                            .font(.caption)
                        Text("Packets/Samples: \(collectorCore.totalSamplesReceived)")
                            .font(.caption)
                        Text("Errors: \(collectorCore.lastErrorMessage ?? "none")")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                SessionControlCard(viewModel: viewModel)
                SessionStatusCard(viewModel: viewModel)
                UploadStatusCard(collectorCore: collectorCore)
                PipelineStatusCard(viewModel: viewModel)

                Button("Stop Quick Session") {
                    collectorCore.stopCollection()
                    Task { await collectorCore.stopOfflineSelected() }
                }
                .buttonStyle(.bordered)
                .disabled(viewModel.state == .idle)

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

    private var quickStreamsLabel: String {
        let configured = collectorCore.configurationRegistry.quickSessionOfflineStreams
            .map { $0.rawValue }
            .sorted()
            .joined(separator: ", ")
        return configured.isEmpty ? "none" : configured
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
