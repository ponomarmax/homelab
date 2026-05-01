import SwiftUI

struct CollectorView: View {
    @StateObject private var collectorCore: CollectorCore
    @State private var selectedTab: PolarScreenTab = .online
    @State private var pendingDeleteEntry: OfflineRecordingEntry?
    @State private var showDeleteAllConfirmation: Bool = false
    @State private var settingsStream: PolarOfflineStream?

    init(collectorCore: CollectorCore) {
        _collectorCore = StateObject(wrappedValue: collectorCore)
    }

    var body: some View {
        NavigationStack {
            Group {
                if collectorCore.status == .connected || collectorCore.status == .collecting || collectorCore.status == .stopped {
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
                    let connectability = collectorCore.connectability(for: device)
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(device.name).fontWeight(.medium)
                            Text("\(device.vendor) • \(device.model)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(device.id)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            if let reason = connectability.reason, !connectability.isConnectable {
                                Text(reason)
                                    .font(.caption2)
                                    .foregroundStyle(.red)
                            }
                        }
                        Spacer()
                        Button("Connect") {
                            collectorCore.selectScannedDevice(device)
                            Task {
                                await collectorCore.connectSelectedDevice()
                            }
                        }
                        .buttonStyle(.bordered)
                        .disabled(!connectability.isConnectable || collectorCore.isConnectingDevice)
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
                    .disabled(collectorCore.isConnectingDevice || collectorCore.status == .collecting)

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
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Offline Recording")
                    .font(.headline)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Status")
                        .font(.subheadline.weight(.semibold))
                    offlineStatusCard
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Streams")
                        .font(.subheadline.weight(.semibold))
                    ForEach(PolarOfflineStream.allCases, id: \.self) { stream in
                        OfflineStreamRow(
                            stream: stream,
                            capability: collectorCore.capabilityForOfflineStream(stream),
                            selected: collectorCore.selectedOfflineStreams.contains(stream),
                            runState: collectorCore.offlineStreamRunStates[stream] ?? .ready,
                            runMessage: collectorCore.offlineStreamRunMessages[stream],
                            settingsSummary: collectorCore.offlineSettingsSummary(for: stream),
                            canConfigure: collectorCore.canConfigureOfflineStream(stream),
                            onToggle: { collectorCore.toggleOfflineStream(stream) },
                            onConfigure: {
                                Task { await collectorCore.loadOfflineSettings(for: stream) }
                                settingsStream = stream
                            }
                        )
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Actions")
                        .font(.subheadline.weight(.semibold))

                    HStack(spacing: 8) {
                        Menu {
                            Button("Start all") {
                                Task { await collectorCore.startOfflineAllSupported() }
                            }
                        } label: {
                            Text(collectorCore.offlineOperation == .starting ? "Starting..." : "Start")
                                .frame(maxWidth: .infinity)
                        } primaryAction: {
                            Task { await collectorCore.startOfflineSelected() }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(collectorCore.isOfflineActionDisabled(.starting) || !collectorCore.canStartOfflineSelected())

                        Menu {
                            Button("Stop all") {
                                Task { await collectorCore.stopOfflineAllSupported() }
                            }
                        } label: {
                            Text(collectorCore.offlineOperation == .stopping ? "Stopping..." : "Stop")
                                .frame(maxWidth: .infinity)
                        } primaryAction: {
                            Task { await collectorCore.stopOfflineSelected() }
                        }
                        .buttonStyle(.bordered)
                        .disabled(collectorCore.isOfflineActionDisabled(.stopping) || !collectorCore.canStopOfflineSelected())
                    }

                    HStack(spacing: 8) {
                        Button(collectorCore.offlineOperation == .listing ? "Refreshing..." : "Refresh") {
                            Task { await collectorCore.refreshOfflineData() }
                        }
                        .buttonStyle(.bordered)
                        .frame(maxWidth: .infinity)
                        .disabled(collectorCore.isOfflineActionDisabled(.listing))

                        Button(collectorCore.offlineOperation == .uploading ? "Uploading..." : "Upload") {
                            Task { await collectorCore.uploadOfflineRecordings() }
                        }
                        .buttonStyle(.borderedProminent)
                        .frame(maxWidth: .infinity)
                        .disabled(collectorCore.isOfflineActionDisabled(.uploading))
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Storage")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.red)
                    HStack(spacing: 8) {
                        Button("Delete selected") {
                            if let firstSelected = collectorCore.offlineRecordings.first(where: {
                                if let stream = $0.stream {
                                    return collectorCore.selectedOfflineStreams.contains(stream)
                                }
                                return false
                            }) {
                                pendingDeleteEntry = firstSelected
                            }
                        }
                        .buttonStyle(.bordered)
                        .tint(.red)
                        .disabled(
                            collectorCore.offlineIsOperationRunning
                                || collectorCore.isUploadingChunk
                                || collectorCore.hasActiveOfflineRecording()
                                || !collectorCore.offlineRecordings.contains(where: {
                                    if let stream = $0.stream {
                                        return collectorCore.selectedOfflineStreams.contains(stream)
                                    }
                                    return false
                                })
                        )

                        Button("Delete all recordings", role: .destructive) {
                            showDeleteAllConfirmation = true
                        }
                        .buttonStyle(.bordered)
                        .disabled(collectorCore.offlineIsOperationRunning || collectorCore.isUploadingChunk || collectorCore.hasActiveOfflineRecording())
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Recordings")
                        .font(.subheadline.weight(.semibold))
                    if collectorCore.offlineRecordings.isEmpty {
                        Text("No offline recordings listed yet.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(collectorCore.offlineRecordings) { entry in
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text(entry.stream?.rawValue ?? "Unknown")
                                        .font(.subheadline.weight(.semibold))
                                    Spacer()
                                    Button(collectorCore.deletingOfflineRecordingIDs.contains(entry.id) ? "Deleting..." : "Delete") {
                                        pendingDeleteEntry = entry
                                    }
                                    .buttonStyle(.bordered)
                                    .disabled(collectorCore.offlineIsOperationRunning || collectorCore.isUploadingChunk || collectorCore.hasActiveOfflineRecording())
                                }
                                Text("path: \(entry.path)")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                Text("size: \(entry.sizeBytes.map(String.init) ?? "n/a")")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                Text("date: \(entry.startedAt.map { dateFormatter.string(from: $0) } ?? "n/a")")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                Text("status: \(entry.status ?? "n/a")")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                if let recordError = collectorCore.offlineRecordErrorsByID[entry.id] {
                                    Text(recordError)
                                        .font(.caption2)
                                        .foregroundStyle(.red)
                                }
                            }
                            .padding(10)
                            .background(.background)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                    }
                }
            }
            .padding(.bottom, 12)
        }
        .alert("Delete offline recording?", isPresented: Binding(
            get: { pendingDeleteEntry != nil },
            set: { isPresented in
                if !isPresented { pendingDeleteEntry = nil }
            }
        )) {
            Button("Delete", role: .destructive) {
                guard let entry = pendingDeleteEntry else { return }
                Task { await collectorCore.deleteOfflineRecording(entry) }
                pendingDeleteEntry = nil
            }
            Button("Cancel", role: .cancel) {
                pendingDeleteEntry = nil
            }
        } message: {
            Text(pendingDeleteEntry?.path ?? "")
        }
        .confirmationDialog(
            "Are you sure? This will delete all offline recordings from device",
            isPresented: $showDeleteAllConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete all", role: .destructive) {
                Task { await collectorCore.deleteAllOfflineRecordings(confirmed: true) }
            }
            Button("Cancel", role: .cancel) {}
        }
        
        .sheet(item: $settingsStream) { stream in
            OfflineSettingsEditorSheet(stream: stream, collectorCore: collectorCore)
        }
    }

    private var offlineStatusCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                if collectorCore.offlineIsOperationRunning {
                    ProgressView().controlSize(.small)
                }
                Text("Operation: \(collectorCore.offlineOperation.rawValue)")
                    .font(.footnote.weight(.medium))
            }
            Text("State: \(offlineLifecycleLabel)")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(offlineGlobalMessage)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("Last success: \(collectorCore.offlineLastSuccessAction)")
                .font(.caption2)
                .foregroundStyle(.secondary)
            if let lastError = collectorCore.offlineLastErrorMessage {
                Text("Last error: \(lastError)")
                    .font(.caption2)
                    .foregroundStyle(.red)
            }
            Text("Per-stream summary: \(collectorCore.offlineProgressSummary)")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var offlineLifecycleLabel: String {
        switch collectorCore.offlineLifecycleState {
        case .refreshing:
            return "Refreshing"
        case .recoveredRecording:
            return "Recovered active recording"
        case .ready:
            return "Ready"
        case .failed:
            return "Failed to refresh offline state"
        default:
            return collectorCore.offlineLifecycleState.rawValue
        }
    }

    private var offlineGlobalMessage: String {
        switch collectorCore.offlineLifecycleState {
        case .refreshing:
            return "Refreshing device offline state..."
        case .recoveredRecording:
            return "Device already has active offline recordings. State restored after reconnect."
        case .ready:
            return "Ready"
        case .failed:
            return collectorCore.offlineStatusMessage
        default:
            return collectorCore.offlineStatusMessage
        }
    }

    private var deviceTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            statusRow(title: "State", value: collectorCore.status.displayName)
            statusRow(title: "Battery", value: collectorCore.selectedDeviceBatteryDisplayText())
            statusRow(title: "Upload", value: collectorCore.uploadStatus.displayName)
            statusRow(title: "Last sync status", value: collectorCore.deviceTimeStatusMessage)
            statusRow(title: "Last time read", value: collectorCore.lastDeviceTimeReadResult)
            statusRow(title: "Last sync result", value: collectorCore.lastDeviceTimeSyncResult)
            statusRow(
                title: "Verification delta",
                value: collectorCore.lastDeviceTimeDeltaSeconds.map { String(format: "%.2fs", $0) } ?? "n/a"
            )
            Text(collectorCore.deviceTimeDebugDetails)
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                Button("Get device time") {
                    Task { await collectorCore.readDeviceTime() }
                }
                .buttonStyle(.bordered)
                .disabled(!collectorCore.deviceTimeAvailability.canReadDeviceTime)

                Button("Sync time to phone") {
                    Task { await collectorCore.syncDeviceTimeToPhoneNow() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!collectorCore.deviceTimeAvailability.canSyncDeviceTime)
            }

            Button("Run pre-offline time check") {
                Task { _ = await collectorCore.runPreOfflineSyncTimeCheck() }
            }
            .buttonStyle(.bordered)
            .disabled(!collectorCore.deviceTimeAvailability.canSyncDeviceTime)

            if let reason = collectorCore.deviceTimeAvailability.reason {
                Text(reason)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
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

private struct OfflineStreamRow: View {
    let stream: PolarOfflineStream
    let capability: OfflineStreamCapability
    let selected: Bool
    let runState: OfflineStreamRunState
    let runMessage: String?
    let settingsSummary: String
    let canConfigure: Bool
    let onToggle: () -> Void
    let onConfigure: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(stream.rawValue)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(capability.isSupported ? streamStatusLabel : (capability.reason ?? "Unavailable"))
                    .font(.caption)
                    .foregroundStyle(capability.isSupported && runState != .failed ? Color.secondary : Color.red)
            }
            HStack(spacing: 8) {
                Button(selected ? "Selected" : "Select") {
                    onToggle()
                }
                .buttonStyle(.bordered)
                .disabled(!capability.isSupported)
                if canConfigure {
                    Button("Configure") {
                        onConfigure()
                    }
                    .buttonStyle(.bordered)
                    .disabled(!capability.isSupported)
                }
            }
            if let runMessage {
                Text(runMessage)
                    .font(.caption2)
                    .foregroundStyle(runState == .failed ? Color.red : Color.secondary)
            }
            Text("Settings: \(settingsSummary)")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(10)
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .opacity(capability.isSupported ? 1 : 0.5)
    }

    private var streamStatusLabel: String {
        switch runState {
        case .recording:
            return "Recording"
        case .ready, .uploaded:
            return "Ready"
        case .failed:
            return "Failed"
        default:
            return "Unknown"
        }
    }
}

private struct OfflineSettingsEditorSheet: View {
    let stream: PolarOfflineStream
    @ObservedObject var collectorCore: CollectorCore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if let settings = collectorCore.offlineSettingsByStream[stream] {
                    Form {
                        if !settings.options.sampleRates.isEmpty {
                            Picker("Sample rate", selection: Binding(
                                get: { settings.selected.sampleRate ?? settings.options.sampleRates.first ?? 0 },
                                set: { value in
                                    collectorCore.updateOfflineSettingsSelection(
                                        for: stream,
                                        sampleRate: value,
                                        resolution: settings.selected.resolution,
                                        range: settings.selected.range,
                                        channels: settings.selected.channels
                                    )
                                }
                            )) {
                                ForEach(settings.options.sampleRates, id: \.self) { value in
                                    Text("\(value)").tag(value)
                                }
                            }
                        }
                        if !settings.options.resolutions.isEmpty {
                            Picker("Resolution", selection: Binding(
                                get: { settings.selected.resolution ?? settings.options.resolutions.first ?? 0 },
                                set: { value in
                                    collectorCore.updateOfflineSettingsSelection(
                                        for: stream,
                                        sampleRate: settings.selected.sampleRate,
                                        resolution: value,
                                        range: settings.selected.range,
                                        channels: settings.selected.channels
                                    )
                                }
                            )) {
                                ForEach(settings.options.resolutions, id: \.self) { value in
                                    Text("\(value)").tag(value)
                                }
                            }
                        }
                        if !settings.options.ranges.isEmpty {
                            Picker("Range", selection: Binding(
                                get: { settings.selected.range ?? settings.options.ranges.first ?? 0 },
                                set: { value in
                                    collectorCore.updateOfflineSettingsSelection(
                                        for: stream,
                                        sampleRate: settings.selected.sampleRate,
                                        resolution: settings.selected.resolution,
                                        range: value,
                                        channels: settings.selected.channels
                                    )
                                }
                            )) {
                                ForEach(settings.options.ranges, id: \.self) { value in
                                    Text("\(value)").tag(value)
                                }
                            }
                        }
                        if !settings.options.channels.isEmpty {
                            Picker("Channels", selection: Binding(
                                get: { settings.selected.channels ?? settings.options.channels.first ?? 0 },
                                set: { value in
                                    collectorCore.updateOfflineSettingsSelection(
                                        for: stream,
                                        sampleRate: settings.selected.sampleRate,
                                        resolution: settings.selected.resolution,
                                        range: settings.selected.range,
                                        channels: value
                                    )
                                }
                            )) {
                                ForEach(settings.options.channels, id: \.self) { value in
                                    Text("\(value)").tag(value)
                                }
                            }
                        }
                    }
                } else {
                    VStack(spacing: 12) {
                        ProgressView()
                        Text("Loading settings...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .task {
                        await collectorCore.loadOfflineSettings(for: stream)
                    }
                }
            }
            .navigationTitle("\(stream.rawValue) Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

private let dateFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
    return formatter
}()

private enum PolarScreenTab: String, CaseIterable, Identifiable {
    case online = "Online"
    case offline = "Offline"
    case device = "Device"

    var id: String { rawValue }
}
