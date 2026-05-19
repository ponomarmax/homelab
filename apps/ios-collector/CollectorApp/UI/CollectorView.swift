import SwiftUI

struct CollectorView: View {
    @StateObject private var collectorCore: CollectorCore
    @StateObject private var nightSessionViewModel: NightSessionViewModel
    @State private var selectedTab: PolarScreenTab = .online
    @State private var pendingDeleteEntry: OfflineRecordingEntry?
    @State private var showDeleteAllConfirmation: Bool = false
    @State private var settingsStream: PolarOfflineStream?
    @State private var expandedSessionIDs: Set<UUID> = []

    init(collectorCore: CollectorCore, nightSessionViewModel: NightSessionViewModel? = nil) {
        _collectorCore = StateObject(wrappedValue: collectorCore)
        if let nightSessionViewModel {
            _nightSessionViewModel = StateObject(wrappedValue: nightSessionViewModel)
        } else {
            _nightSessionViewModel = StateObject(
                wrappedValue: NightSessionViewModel(
                    coordinator: SessionWorkflowCoordinator(
                        core: collectorCore,
                        pipelineEndpoint: nil,
                        dashboardEndpoint: nil
                    )
                )
            )
        }
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
            case .sessions:
                sessionsTab
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
                SessionControlCard(viewModel: nightSessionViewModel)
                SessionStatusCard(viewModel: nightSessionViewModel)
                UploadStatusCard(collectorCore: collectorCore)
                PipelineStatusCard(viewModel: nightSessionViewModel)
                DeviceStatusCard(
                    deviceName: collectorCore.selectedDevice?.name ?? "Unknown",
                    batteryText: collectorCore.selectedDeviceBatteryDisplayText()
                )
                offlineStatusSection
                offlineStreamsSection
                offlineActionsSection
                offlineUnassignedSection
                offlinePendingSyncSection
                offlineStorageSection
                offlineRecordingsSection
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

    private var offlineStatusSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Status")
                .font(.subheadline.weight(.semibold))
            offlineStatusCard
        }
    }

    private var offlineStreamsSection: some View {
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
    }

    private var offlineActionsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Actions")
                .font(.subheadline.weight(.semibold))
            HStack(spacing: 8) {
                Menu {
                    Button("Start all") { Task { await collectorCore.startOfflineAllSupported() } }
                } label: {
                    Text(collectorCore.offlineOperation == .starting ? "Starting..." : "Start")
                        .frame(maxWidth: .infinity)
                } primaryAction: {
                    Task { await collectorCore.startOfflineSelected() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(collectorCore.isOfflineActionDisabled(.starting) || !collectorCore.canStartOfflineSelected())

                Menu {
                    Button("Stop all") { Task { await collectorCore.stopOfflineAllSupported() } }
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
    }

    private var offlineUnassignedSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Unassigned Recordings")
                .font(.subheadline.weight(.semibold))
            Text("Found: \(collectorCore.unassignedOfflineRecordings.count)")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                Button("Assign as one session") { collectorCore.assignUnassignedAsSingleSession() }
                    .buttonStyle(.borderedProminent)
                    .disabled(collectorCore.unassignedOfflineRecordings.isEmpty)
                Button("Assign by clusters") { collectorCore.assignUnassignedByClusters() }
                    .buttonStyle(.bordered)
                    .disabled(collectorCore.unassignedRecordingGroups.isEmpty)
            }
            if !collectorCore.unassignedRecordingGroups.isEmpty {
                ForEach(collectorCore.unassignedRecordingGroups) { group in
                    Text("\(group.id): \(group.entries.count) file(s)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Divider().padding(.vertical, 4)
            Text("All visible recordings: \(collectorCore.offlineRecordings.count)")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                Button("Organize visible as one") { collectorCore.assignVisibleRecordingsAsSingleSession() }
                    .buttonStyle(.borderedProminent)
                    .disabled(collectorCore.offlineRecordings.isEmpty)
                Button("Organize visible by clusters") { collectorCore.assignVisibleRecordingsByClusters() }
                    .buttonStyle(.bordered)
                    .disabled(collectorCore.offlineRecordings.isEmpty)
            }
        }
    }

    private var offlinePendingSyncSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Pending Server Sync")
                .font(.subheadline.weight(.semibold))
            Text("Manifests queued: \(collectorCore.pendingSessionManifests.count)")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(collectorCore.manifestSyncStatusMessage)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Button(collectorCore.isManifestSyncRunning ? "Retrying..." : "Retry pending sync") {
                Task { await collectorCore.retryPendingSessionManifestSync() }
            }
            .buttonStyle(.bordered)
            .disabled(collectorCore.pendingSessionManifests.isEmpty || collectorCore.isManifestSyncRunning)
            ForEach(collectorCore.pendingSessionManifests) { item in
                Text("\(item.clientSessionID) • retries: \(item.retryCount)\(item.lastError == nil ? "" : " • \(item.lastError!)")")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var offlineStorageSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Storage")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.red)
            HStack(spacing: 8) {
                Button("Delete selected") {
                    if let firstSelected = collectorCore.offlineRecordings.first(where: {
                        if let stream = $0.stream { return collectorCore.selectedOfflineStreams.contains(stream) }
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
                            if let stream = $0.stream { return collectorCore.selectedOfflineStreams.contains(stream) }
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
    }

    private var offlineRecordingsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Recordings")
                .font(.subheadline.weight(.semibold))
            if collectorCore.offlineRecordings.isEmpty {
                Text("No offline recordings listed yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(collectorCore.offlineRecordings) { entry in
                    let safety = collectorCore.offlineRecordingSafetySummary(for: entry)
                    OfflineRecordingCard(
                        entry: entry,
                        safety: safety,
                        isDeleting: collectorCore.deletingOfflineRecordingIDs.contains(entry.id),
                        isDeleteDisabled: collectorCore.offlineIsOperationRunning || collectorCore.isUploadingChunk || collectorCore.hasActiveOfflineRecording(),
                        recordError: collectorCore.offlineRecordErrorsByID[entry.id],
                        dateText: entry.startedAt.map { dateFormatter.string(from: $0) } ?? "n/a",
                        onDelete: {
                            pendingDeleteEntry = entry
                        }
                    )
                }
            }
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

    private var sessionsTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Session Management")
                    .font(.headline)
                Text("Sessions: \(collectorCore.managedSessions.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        if collectorCore.isManagedSessionUploadRunning {
                            ProgressView().controlSize(.small)
                        }
                        Text(collectorCore.managedSessionUploadStatusMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    HStack(spacing: 8) {
                        Button("Upload all (chronology)") {
                            Task { await collectorCore.uploadManagedSessionsChronologically() }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(collectorCore.managedSessions.isEmpty || collectorCore.offlineIsOperationRunning || collectorCore.isUploadingChunk)
                    }
                }
                .padding(10)
                .background(.background)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                if collectorCore.managedSessions.isEmpty {
                    Text("No managed sessions yet.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(collectorCore.managedSessions) { session in
                        let pending = collectorCore.pendingManifest(for: session.id)
                        let hasLocalArchive = collectorCore.isManagedSessionArchived(session.id)
                        let isServerSynced = session.lifecycle == .uploaded
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(session.clientSessionID)
                                    .font(.subheadline.weight(.semibold))
                                Spacer()
                                Text(session.lifecycle.rawValue)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Text("\(session.deviceType) • \(session.collectionMode.rawValue)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text("files: \(session.linkedFiles.count)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            SessionSyncBar(
                                hasLocalCopy: hasLocalArchive,
                                isServerUploaded: isServerSynced,
                                isPendingServerSync: pending != nil,
                                isUploadingNow: collectorCore.isManagedSessionUploadRunning
                            )
                            if let uploadStatus = collectorCore.managedSessionUploadStatusByID[session.id] {
                                Text(uploadStatus)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }

                            if let pending {
                                Text("manifest pending • retries: \(pending.retryCount)")
                                    .font(.caption2)
                                    .foregroundStyle(.orange)
                                if let error = pending.lastError, !error.isEmpty {
                                    Text(error)
                                        .font(.caption2)
                                        .foregroundStyle(.red)
                                }
                            }

                            HStack(spacing: 8) {
                                Button(expandedSessionIDs.contains(session.id) ? "Hide files" : "Show files") {
                                    if expandedSessionIDs.contains(session.id) {
                                        expandedSessionIDs.remove(session.id)
                                    } else {
                                        expandedSessionIDs.insert(session.id)
                                    }
                                }
                                .buttonStyle(.bordered)

                                Button("Retry manifest") {
                                    Task { await collectorCore.retryPendingManifest(for: session.id) }
                                }
                                .buttonStyle(.bordered)
                                .disabled(pending == nil || collectorCore.isManifestSyncRunning)

                                Button("Upload session") {
                                    Task { await collectorCore.uploadManagedSession(session.id) }
                                }
                                .buttonStyle(.borderedProminent)
                                .disabled(session.linkedFiles.isEmpty || collectorCore.offlineIsOperationRunning || collectorCore.isUploadingChunk)

                                Button("Drop pending") {
                                    guard let pending else { return }
                                    collectorCore.removePendingManifest(id: pending.id)
                                }
                                .buttonStyle(.bordered)
                                .disabled(pending == nil)

                                Button("Delete session", role: .destructive) {
                                    collectorCore.deleteManagedSession(id: session.id)
                                    expandedSessionIDs.remove(session.id)
                                }
                                .buttonStyle(.bordered)
                            }

                            if expandedSessionIDs.contains(session.id) {
                                if session.linkedFiles.isEmpty {
                                    Text("No linked files")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                } else {
                                    Text("local archive file:")
                                        .font(.caption2.weight(.semibold))
                                    Text(collectorCore.localArchiveFilePath(for: session.id))
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                    ForEach(Array(session.linkedFiles.enumerated()), id: \.offset) { _, file in
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(file.stream)
                                                .font(.caption2.weight(.semibold))
                                            Text(file.path)
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                }
                            }
                        }
                        .padding(10)
                        .background(.background)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                }
            }
            .padding(.bottom, 12)
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
            HStack(spacing: 8) {
                Button("Prepare log export") {
                    collectorCore.prepareLogExportFile()
                }
                .buttonStyle(.bordered)

                if let exportURL = collectorCore.logExportFileURL {
                    ShareLink(item: exportURL) {
                        Text("Share snapshot log")
                    }
                    .buttonStyle(.bordered)
                }

                if let persistentURL = collectorCore.persistentLogFileURL {
                    ShareLink(item: persistentURL) {
                        Text("Share full app log")
                    }
                    .buttonStyle(.bordered)
                }
            }
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

private struct SessionSyncBar: View {
    let hasLocalCopy: Bool
    let isServerUploaded: Bool
    let isPendingServerSync: Bool
    let isUploadingNow: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                syncPill(
                    title: "Local copy",
                    color: hasLocalCopy ? .green : .gray,
                    value: hasLocalCopy ? "saved" : "missing"
                )
                syncPill(
                    title: "Server upload",
                    color: isServerUploaded ? .green : (isPendingServerSync || isUploadingNow ? .orange : .gray),
                    value: isServerUploaded ? "done" : (isPendingServerSync ? "queued" : (isUploadingNow ? "uploading" : "not uploaded"))
                )
            }
            GeometryReader { geo in
                HStack(spacing: 6) {
                    Rectangle()
                        .fill(hasLocalCopy ? Color.green : Color.gray.opacity(0.35))
                    Rectangle()
                        .fill(isServerUploaded ? Color.green : (isPendingServerSync || isUploadingNow ? Color.orange : Color.gray.opacity(0.35)))
                }
                .frame(width: geo.size.width, height: 8)
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
            }
            .frame(height: 8)
        }
    }

    private func syncPill(title: String, color: Color, value: String) -> some View {
        Text("\(title): \(value)")
            .font(.caption2)
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.12))
            .clipShape(Capsule())
    }
}

private struct OfflineRecordingCard: View {
    let entry: OfflineRecordingEntry
    let safety: OfflineRecordingSafetySummary
    let isDeleting: Bool
    let isDeleteDisabled: Bool
    let recordError: String?
    let dateText: String
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(entry.stream?.rawValue ?? "Unknown")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Button(isDeleting ? "Deleting..." : "Delete") {
                    onDelete()
                }
                .buttonStyle(.bordered)
                .disabled(isDeleteDisabled)
            }
            Text("path: \(entry.path)").font(.caption2).foregroundStyle(.secondary)
            Text("size: \(entry.sizeBytes.map(String.init) ?? "n/a")").font(.caption2).foregroundStyle(.secondary)
            Text("date: \(dateText)").font(.caption2).foregroundStyle(.secondary)
            Text("status: \(entry.status ?? "n/a")").font(.caption2).foregroundStyle(.secondary)
            Text("recording now: \(safety.isRecordingNow ? "yes" : "no")").font(.caption2).foregroundStyle(safety.isRecordingNow ? .orange : .secondary)
            Text("assigned session: \(safety.assignedSessionID ?? "no")").font(.caption2).foregroundStyle(safety.isAssignedToSession ? Color.secondary : Color.orange)
            Text("local copy: \(safety.hasLocalArchiveCopy ? "saved" : "missing")").font(.caption2).foregroundStyle(safety.hasLocalArchiveCopy ? .green : .orange)
            Text("safe to delete from sensor: \(safety.safeToDeleteFromSensor ? "yes" : "no")")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(safety.safeToDeleteFromSensor ? .green : .orange)
            if let recordError {
                Text(recordError).font(.caption2).foregroundStyle(.red)
            }
        }
        .padding(10)
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
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
    case sessions = "Sessions"
    case device = "Device"

    var id: String { rawValue }
}
