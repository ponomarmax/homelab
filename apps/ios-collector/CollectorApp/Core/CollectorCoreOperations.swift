import Foundation
import UIKit

extension CollectorCore {
    private func checkpointKey(sessionID: UUID, batch: OfflineUploadBatch, component: String = "full") -> String {
        "\(sessionID.uuidString.lowercased())|\(batch.stream.transportType)|\(batch.sourcePath.lowercased())|\(batch.samples.count)|\(component)"
    }

    private func loadedCheckpointKeys(sessionID: UUID) -> Set<String> {
        Set(
            uploadedBatchCheckpointStore.load()
                .filter { $0.sessionID == sessionID }
                .map { "\(sessionID.uuidString.lowercased())|\($0.streamType)|\($0.sourcePath.lowercased())|\($0.samplesCount)|\($0.component)" }
        )
    }

    private func markCheckpointUploaded(sessionID: UUID, batch: OfflineUploadBatch, component: String = "full") {
        var all = uploadedBatchCheckpointStore.load()
        let key = checkpointKey(sessionID: sessionID, batch: batch, component: component)
        let existingV2 = Set(all.map { "\($0.sessionID.uuidString.lowercased())|\($0.streamType)|\($0.sourcePath.lowercased())|\($0.samplesCount)|\($0.component)" })
        guard !existingV2.contains(key) else { return }
        all.append(
            UploadedBatchCheckpoint(
                sessionID: sessionID,
                sourcePath: batch.sourcePath,
                streamType: batch.stream.transportType,
                samplesCount: batch.samples.count,
                component: component,
                recordedAtUTC: nowProvider()
            )
        )
        uploadedBatchCheckpointStore.save(all)
    }

    private func markOfflineFileFetched(path: String, sessionID: UUID?) {
        var states = offlineFileTransferStateStore.load()
        let normalized = path.lowercased()
        let now = nowProvider()
        if let idx = states.firstIndex(where: { $0.sourcePath.lowercased() == normalized }) {
            states[idx].lastFetchedAtUTC = now
            states[idx].lastSessionID = sessionID
        } else {
            states.append(
                OfflineFileTransferState(
                    sourcePath: path,
                    firstFetchedAtUTC: now,
                    lastFetchedAtUTC: now,
                    lastUploadedAtUTC: nil,
                    isUploadedComplete: false,
                    lastSessionID: sessionID
                )
            )
        }
        offlineFileTransferStateStore.save(states)
    }

    private func markOfflineFileUploadedComplete(path: String, sessionID: UUID?) {
        var states = offlineFileTransferStateStore.load()
        let normalized = path.lowercased()
        let now = nowProvider()
        if let idx = states.firstIndex(where: { $0.sourcePath.lowercased() == normalized }) {
            states[idx].isUploadedComplete = true
            states[idx].lastUploadedAtUTC = now
            states[idx].lastSessionID = sessionID
        } else {
            states.append(
                OfflineFileTransferState(
                    sourcePath: path,
                    firstFetchedAtUTC: now,
                    lastFetchedAtUTC: now,
                    lastUploadedAtUTC: now,
                    isUploadedComplete: true,
                    lastSessionID: sessionID
                )
            )
        }
        offlineFileTransferStateStore.save(states)
    }

    private func transferState(for path: String) -> OfflineFileTransferState? {
        let normalized = path.lowercased()
        return offlineFileTransferStateStore.load().first { $0.sourcePath.lowercased() == normalized }
    }

    private func isOfflineFileUploadedComplete(path: String) -> Bool {
        transferState(for: path)?.isUploadedComplete == true
    }

    private func clearTransferState(for path: String) {
        let normalized = path.lowercased()
        var all = offlineFileTransferStateStore.load()
        all.removeAll { $0.sourcePath.lowercased() == normalized }
        offlineFileTransferStateStore.save(all)
    }

    private func sanitizedOfflineSelection(for stream: PolarOfflineStream) -> OfflineStreamSettingsSelection? {
        guard let settings = offlineSettingsByStream[stream] else { return nil }
        var changed = false
        func pickAllowed(_ current: UInt32?, allowed: [UInt32]) -> UInt32? {
            guard !allowed.isEmpty else { return current }
            if let current, allowed.contains(current) { return current }
            changed = true
            return allowed.first
        }
        let sanitized = OfflineStreamSettingsSelection(
            sampleRate: pickAllowed(settings.selected.sampleRate, allowed: settings.options.sampleRates),
            resolution: pickAllowed(settings.selected.resolution, allowed: settings.options.resolutions),
            range: pickAllowed(settings.selected.range, allowed: settings.options.ranges),
            channels: pickAllowed(settings.selected.channels, allowed: settings.options.channels)
        )
        if changed {
            offlineSettingsByStream[stream] = OfflineStreamSettings(
                stream: settings.stream,
                options: settings.options,
                selected: sanitized
            )
            adapter.updateOfflineRecordingSettingsSelection(sanitized, for: stream)
            offlineStreamRunMessages[stream] = "Adjusted invalid settings to nearest supported values"
            log("offline_settings_sanitized stream=\(stream.rawValue) selection=[\(sanitized.summary())]", level: .warning, category: "offline-settings")
        }
        return sanitized
    }

    private func applyRegistrySelectionToOfflineStream(_ stream: PolarOfflineStream) {
        guard stream == .acc else { return }
        guard offlineSettingsByStream[stream] != nil else { return }
        let effective = configurationRegistry.effectiveSettings(
            deviceID: "polar_verity_sense",
            modeID: "offline",
            streamID: "acc"
        )
        updateOfflineSettingsSelection(
            for: .acc,
            sampleRate: effective["sample_rate_hz"]?.numberUInt32,
            resolution: effective["resolution_bit"]?.numberUInt32,
            range: effective["range_g"]?.numberUInt32,
            channels: effective["channels"]?.numberUInt32
        )
    }

    private func splitForUpload(_ batch: OfflineUploadBatch, sampleLimit: Int) -> [OfflineUploadBatch] {
        guard sampleLimit > 0, batch.samples.count > sampleLimit else { return [batch] }
        var parts: [OfflineUploadBatch] = []
        var cursor = 0
        while cursor < batch.samples.count {
            let end = min(cursor + sampleLimit, batch.samples.count)
            let slice = Array(batch.samples[cursor..<end])
            parts.append(
                OfflineUploadBatch(
                    stream: batch.stream,
                    sourcePath: batch.sourcePath,
                    samples: slice,
                    timeContext: batch.timeContext
                )
            )
            cursor = end
        }
        return parts
    }

    private func selectOfflineUploadCandidates(
        from entries: [OfflineRecordingEntry],
        allowedPaths: Set<String>?
    ) -> [OfflineRecordingEntry] {
        if let allowedPaths {
            let normalized = Set(allowedPaths.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() })
            let basenames = Set(allowedPaths.map { URL(fileURLWithPath: $0).lastPathComponent.lowercased() })
            return entries.filter { entry in
                let entryPath = entry.path.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                if normalized.contains(entryPath) { return true }
                if normalized.contains(where: { entryPath.hasSuffix($0) || $0.hasSuffix(entryPath) }) { return true }
                return basenames.contains(URL(fileURLWithPath: entry.path).lastPathComponent.lowercased())
            }
        }

        let known = entries.filter { $0.stream != nil }
        guard !known.isEmpty else { return entries }
        guard let anchor = known.compactMap(\.startedAt).max() else { return known }

        func distance(_ date: Date?) -> TimeInterval {
            guard let date else { return .greatestFiniteMagnitude }
            return abs(date.timeIntervalSince(anchor))
        }

        var byStream: [PolarOfflineStream: OfflineRecordingEntry] = [:]
        for entry in known {
            guard let stream = entry.stream else { continue }
            guard byStream[stream] == nil || distance(entry.startedAt) < distance(byStream[stream]?.startedAt) else { continue }
            byStream[stream] = entry
        }

        let selected = Array(byStream.values)
        let close = selected.filter { distance($0.startedAt) <= 15 * 60 }
        return close.count >= 3 ? close : selected
    }

    private func collectorStream(for offlineStream: PolarOfflineStream) -> CollectorStream {
        switch offlineStream {
        case .hr: return .heartRate
        case .ppi: return .ppi
        case .acc: return .accelerometer
        case .ppg: return .battery
        case .mag: return .accelerometer
        case .gyro: return .accelerometer
        }
    }

    func autoConnectToRememberedDevice() async {
        if isScanningDevices || isConnectingDevice {
            return
        }
        guard let rememberedDevice else { return }
        if status == .connected, selectedDevice?.id == rememberedDevice.id {
            return
        }

        if let current = selectedDevice, current.id == rememberedDevice.id {
            if status == .deviceSelected || status == .stopped {
                await connectSelectedDevice()
            }
            return
        }

        if discoveredDevices.isEmpty {
            await scanAndSelectDevice()
        }

        if let matched = discoveredDevices.first(where: { $0.id == rememberedDevice.id }) {
            selectScannedDevice(matched)
            await connectSelectedDevice()
            return
        }

        // Retry one additional scan in case device was not advertising initially.
        await scanAndSelectDevice()
        if let matched = discoveredDevices.first(where: { $0.id == rememberedDevice.id }) {
            selectScannedDevice(matched)
            await connectSelectedDevice()
        }
    }

    private func persistRememberedDevice(_ device: CollectorDevice) {
        let remembered = RememberedDevice(
            id: device.id,
            name: device.name,
            vendor: device.vendor,
            model: device.model,
            updatedAtUTC: nowProvider()
        )
        rememberedDevice = remembered
        if let encoded = try? JSONEncoder().encode(remembered) {
            UserDefaults.standard.set(encoded, forKey: rememberedDeviceStorageKey)
        }
    }

    var deviceActionTitle: String {
        adapter.deviceSelectionActionTitle
    }

    var uploadDestinationDescription: String {
        transport.uploadDestinationDescription
    }

    var polarCapabilities: PolarDeviceProfile {
        PolarDeviceProfile.from(
            device: selectedDevice,
            availableOnlineStreams: adapter.availableStreams,
            supportsManualTimeSync: adapter.deviceTimeAvailability.canSyncDeviceTime
        )
    }

    var deviceTimeAvailability: DeviceTimeActionAvailability {
        adapter.deviceTimeAvailability
    }

    func selectedDeviceBatteryDisplayText() -> String {
        guard let selectedDevice else {
            return "unknown"
        }
        return batteryDisplayText(for: selectedDevice.id)
    }

    func batteryDisplayText(for deviceID: String) -> String {
        let snapshot = latestStatusByDeviceID[deviceID] ?? adapter.cachedDeviceStatusSnapshot(for: deviceID)
        if let snapshot {
            return formatBattery(snapshot.status.battery)
        }

        if let batteryCapability = adapter.deviceStatusCapabilities.first(where: { $0.kind == .battery }) {
            guard batteryCapability.isSupported else {
                return "unsupported"
            }
            return batteryCapability.requiresConnection ? "available after connection" : "unknown"
        }

        return "unknown"
    }

    func connectability(for device: CollectorDevice) -> DeviceConnectability {
        adapter.connectability(for: device)
    }

    func appDidBecomeActive() {
        log("App became active", category: "lifecycle")
        reconcileOpenSessionsAfterLifecycleEvent()
        refreshUnassignedRecordingGroups()
        guard isManifestAutoRetryEnabled else { return }
        Task { @MainActor [weak self] in
            await self?.retryPendingSessionManifestSync()
        }
    }

    func appDidEnterBackground() {
        log("App moved to background", category: "lifecycle")
    }

    func readDeviceTime() async {
        deviceTimeSyncState = .running
        deviceTimeStatusMessage = "Syncing device time..."
        let result = await adapter.readDeviceTime(mode: .live)
        applyDeviceTimeActionResult(result, isSyncAction: false)
    }

    func syncDeviceTimeToPhoneNow() async {
        deviceTimeSyncState = .running
        deviceTimeStatusMessage = "Syncing device time..."
        let result = await adapter.syncDeviceTimeToPhone(mode: .live)
        applyDeviceTimeActionResult(result, isSyncAction: true)
    }

    func runPreOfflineSyncTimeCheck() async -> DeviceTimeActionResult {
        deviceTimeSyncState = .running
        deviceTimeStatusMessage = "Syncing device time..."
        let result = await adapter.prepareDeviceTimeForOfflineSync()
        applyDeviceTimeActionResult(result, isSyncAction: true)
        return result
    }

    func selectDevice() {
        clearFailureState()
        activityMessage = "Selecting mock device..."
        log("Select device tapped")
        do {
            try adapter.selectDevice(adapter.deviceIdentity)
            selectedDevice = adapter.deviceIdentity
            persistRememberedDevice(adapter.deviceIdentity)
            refreshCachedStatus(for: adapter.deviceIdentity.id)
            status = .deviceSelected
            selectedOnlineStreams = Set(adapter.availableStreams)
            selectedOfflineStreams = Set(polarCapabilities.availableOfflineStreams)
            offlineStreamCapabilities = [:]
            offlineSettingsByStream = [:]
            offlineSettingsLoadStateByStream = [:]
            offlineStreamRunMessages = [:]
            offlineRecordings = []
            offlineLifecycleState = .disconnected
            offlineStatusMessage = "Connect to use offline recording"
            offlineSettingsByStream = [:]
            offlineSettingsLoadStateByStream = [:]
            uploadStatus = .idle
            activityMessage = "Device selected"
            log("Device selected: \(selectedDevice?.name ?? "unknown")")
        } catch {
            selectedDevice = nil
            latestDeviceStatusSnapshot = nil
            status = .disconnected
            uploadStatus = .idle
            reportFailure(
                userMessage: "Device selection failed: \(error.localizedDescription)",
                activity: "Device selection failed",
                technical: "Device selection failed: \(error.localizedDescription)",
                category: "device"
            )
        }
    }

    func scanAndSelectDevice() async {
        guard !isScanningDevices else {
            log("Scan request ignored: scan already in progress", category: "core")
            return
        }
        clearFailureState()
        selectedDevice = nil
        latestDeviceStatusSnapshot = nil
        status = .disconnected
        uploadStatus = .idle
        isScanningDevices = true
        activityMessage = "Scanning for Polar devices..."
        log("Scan started")
        defer {
            isScanningDevices = false
        }

        do {
            let devices = try await adapter.scanDevices { [weak self] progressive in
                Task { @MainActor in
                    self?.discoveredDevices = progressive
                    self?.refreshCachedStatuses(for: progressive)
                }
            }
            if devices.isEmpty && !discoveredDevices.isEmpty {
                log(
                    "Scan completed with empty final list; preserving \(discoveredDevices.count) progressively discovered device(s)",
                    level: .warning,
                    category: "device"
                )
            } else {
                discoveredDevices = devices
                refreshCachedStatuses(for: devices)
            }
            log("Scan finished: found \(discoveredDevices.count) device(s)")

            if discoveredDevices.isEmpty {
                lastErrorMessage = "No Polar devices found"
                activityMessage = "No devices found"
            } else {
                lastErrorMessage = "Select a device from the list below"
                activityMessage = "Select device from list"
            }
        } catch {
            discoveredDevices = []
            selectedDevice = nil
            latestDeviceStatusSnapshot = nil
            status = .disconnected
            uploadStatus = .idle
            reportFailure(
                userMessage: "Scan failed: \(error.localizedDescription)",
                activity: "Scan failed",
                technical: "Scan failed: \(error.localizedDescription)",
                category: "device"
            )
        }
    }

    func selectScannedDevice(_ device: CollectorDevice) {
        clearFailureState()
        activityMessage = "Selecting \(device.name)..."
        log("Selecting scanned device: \(device.name)")

        do {
            try adapter.selectDevice(device)
            selectedDevice = adapter.deviceIdentity
            persistRememberedDevice(adapter.deviceIdentity)
            refreshCachedStatus(for: adapter.deviceIdentity.id)
            status = .deviceSelected
            selectedOnlineStreams = Set(adapter.availableStreams)
            selectedOfflineStreams = Set(polarCapabilities.availableOfflineStreams)
            offlineLifecycleState = .disconnected
            offlineStatusMessage = "Connect to use offline recording"
            uploadStatus = .idle
            activityMessage = "Device selected: \(selectedDevice?.name ?? "Unknown")"
            log("Device selected: \(selectedDevice?.id ?? "unknown")")
        } catch {
            selectedDevice = nil
            latestDeviceStatusSnapshot = nil
            status = .disconnected
            uploadStatus = .idle
            reportFailure(
                userMessage: "Device selection failed: \(error.localizedDescription)",
                activity: "Device selection failed",
                technical: "Scanned device selection failed: \(error.localizedDescription)",
                category: "device"
            )
        }
    }

    func connectSelectedDevice() async {
        guard !isConnectingDevice else {
            log("Connect request ignored: connect already in progress", category: "core")
            return
        }
        guard status == .deviceSelected || status == .stopped else { return }
        guard let selectedDevice else { return }
        let connectability = adapter.connectability(for: selectedDevice)
        guard connectability.isConnectable else {
            reportFailure(
                userMessage: connectability.reason ?? "Device is not connectable",
                activity: "Cannot connect selected device",
                technical: "Connect blocked: \(connectability.reason ?? "unknown reason")",
                category: "device"
            )
            return
        }

        clearFailureState()
        isConnectingDevice = true
        activityMessage = "Connecting to device..."

        do {
            try await adapter.connect()
            status = .connected
            persistRememberedDevice(selectedDevice)
            activityMessage = "Connected"
            await recoverOfflineStateAfterReconnect()
        } catch {
            status = .deviceSelected
            reportFailure(
                userMessage: "Connection failed: \(error.localizedDescription)",
                activity: "Connection failed",
                technical: "Connection failed: \(error.localizedDescription)",
                category: "device"
            )
        }
        isConnectingDevice = false
    }

    func startCollection() async {
        guard status == .deviceSelected || status == .connected || status == .stopped else { return }
        guard let selectedDevice else { return }
        refreshCachedStatus(for: selectedDevice.id)

        clearFailureState()
        uploadStatus = .idle
        isConnectingDevice = true
        activityMessage = "Connecting to device..."
        log("Start tapped")

        totalSamplesReceived = 0
        bufferedSamplesByStream.removeAll()
        bufferedSamplesCount = 0
        pendingUploadChunks = []
        pendingUploadChunksCount = 0
        nextChunkSequenceNumberByStream.removeAll()
        lastFlushAtUTCByStream.removeAll()
        consecutiveUploadFailureCount = 0
        nextUploadRetryAtUTC = nil
        latestHeartRateSample = nil
        lastPreparedChunk = nil
        debugExportFileURL = nil
        logExportFileURL = nil
        streamDescriptorsByType.removeAll()

        autoFlushTask?.cancel()
        startAutoFlushTask()

        if adapter.connectionState != .connected {
            do {
                try await adapter.connect()
            } catch {
                status = .deviceSelected
                isConnectingDevice = false
                reportFailure(
                    userMessage: "Connection failed: \(error.localizedDescription)",
                    activity: "Connection failed",
                    technical: "Connection failed: \(error.localizedDescription)",
                    category: "device"
                )
                return
            }
        }
        isConnectingDevice = false

        let providers = adapter.streamProviders().filter { selectedOnlineStreams.contains($0.streamType) }
        guard !providers.isEmpty else {
            status = .deviceSelected
            reportFailure(
                userMessage: "No online streams selected or available for selected device",
                activity: "Cannot start collection",
                technical: "Start blocked after connect: streamProviders() returned empty",
                category: "core"
            )
            return
        }

        let session = CollectionSession(
            device: adapter.deviceIdentity,
            collectionMode: defaultCollectionMode,
            startedAtUTC: Date(),
            supportedStreams: adapter.availableStreams
        )

        activeProviders = providers
        activeSession = session
        upsertManagedSession(
            id: session.sessionID,
            clientSessionID: session.clientSessionID,
            mode: session.collectionMode,
            origin: .ourApp,
            lifecycle: .started,
            startedAtUTC: session.startedAtUTC,
            stoppedAtUTC: nil,
            linkedFiles: [],
            notes: "started_in_app"
        )

        for provider in providers {
            streamDescriptorsByType[provider.streamType] = transport.makeStreamDescriptor(
                for: provider.streamType,
                source: adapter.sourceIdentifier
            )
            nextChunkSequenceNumberByStream[provider.streamType] = 1
            lastFlushAtUTCByStream[provider.streamType] = nowProvider()
            log("Stream provider prepared: \(provider.streamType.transportType)", category: "core")
        }

        streamDescriptor = streamDescriptorsByType[.heartRate] ?? providers.first.flatMap { streamDescriptorsByType[$0.streamType] }
        prepareDebugExport(for: session)

        let streamStartPriority: [CollectorStream] = [.battery, .heartRate, .ecg, .accelerometer, .ppi, .eeg]
        let orderedProviders = providers.sorted {
            let leftIndex = streamStartPriority.firstIndex(of: $0.streamType) ?? Int.max
            let rightIndex = streamStartPriority.firstIndex(of: $1.streamType) ?? Int.max
            return leftIndex < rightIndex
        }

        for provider in orderedProviders {
            provider.start { [weak self] sample in
                guard let self else { return }
                Task { @MainActor in
                    await self.handle(sample: sample)
                }
            }
            // Start streams in sequence to avoid PMD control-point contention on device startup.
            if provider.streamType == .heartRate || provider.streamType == .ecg {
                await sleepProvider(350_000_000)
            }
        }

        status = .collecting
        activityMessage = "Collecting live streams..."
        log("Collection started. Session: \(session.sessionID.uuidString)", category: "core")
    }

    func disconnectDevice() {
        stopCollection()
        selectedDevice = nil
        latestDeviceStatusSnapshot = nil
        discoveredDevices = []
        status = .disconnected
        offlineLifecycleState = .disconnected
        offlineStatusMessage = "Disconnected"
    }

    func toggleOnlineStream(_ stream: CollectorStream) {
        guard status != .collecting else { return }
        guard adapter.availableStreams.contains(stream) else { return }
        if selectedOnlineStreams.contains(stream) {
            selectedOnlineStreams.remove(stream)
        } else {
            selectedOnlineStreams.insert(stream)
        }
    }

    func toggleOfflineStream(_ stream: PolarOfflineStream) {
        guard let capability = offlineStreamCapabilities[stream], capability.isSupported else { return }
        if selectedOfflineStreams.contains(stream) {
            selectedOfflineStreams.remove(stream)
        } else {
            selectedOfflineStreams.insert(stream)
        }
    }

    func capabilityForOfflineStream(_ stream: PolarOfflineStream) -> OfflineStreamCapability {
        if let capability = offlineStreamCapabilities[stream] {
            return capability
        }
        let isSupported = polarCapabilities.availableOfflineStreams.contains(stream)
        return OfflineStreamCapability(
            stream: stream,
            isSupported: isSupported,
            reason: isSupported ? nil : "Unsupported"
        )
    }

    func refreshOfflineCapabilities() async {
        let capabilities = await adapter.offlineCapabilities()
        offlineStreamCapabilities = Dictionary(uniqueKeysWithValues: capabilities.map { ($0.stream, $0) })
        let supported = capabilities.filter(\.isSupported).map(\.stream)
        selectedOfflineStreams = Set(selectedOfflineStreams.filter { supported.contains($0) })
        if selectedOfflineStreams.isEmpty {
            selectedOfflineStreams = Set(supported)
        }
        if adapter.connectionState != .connected {
            offlineLifecycleState = .disconnected
            offlineStatusMessage = "Device disconnected"
            return
        }
        if supported.isEmpty {
            offlineLifecycleState = .featureUnavailable
            offlineStatusMessage = capabilities.first(where: { !$0.isSupported })?.reason ?? "Offline recording unavailable"
        } else {
            offlineLifecycleState = .ready
            offlineStatusMessage = "Ready"
            for stream in supported {
                if offlineStreamRunStates[stream] == nil {
                    offlineStreamRunStates[stream] = .ready
                }
                if offlineSettingsLoadStateByStream[stream] == nil {
                    offlineSettingsLoadStateByStream[stream] = .notLoaded
                }
            }
        }
        updateRecoveredStates()
    }

    func recoverOfflineStateAfterReconnect() async {
        offlineLifecycleState = .refreshing
        offlineStatusMessage = "Refreshing device offline state..."
        offlineLastErrorMessage = nil

        let capabilities = await adapter.offlineCapabilities()
        offlineStreamCapabilities = Dictionary(uniqueKeysWithValues: capabilities.map { ($0.stream, $0) })
        let supportedStreams = Set(capabilities.filter(\.isSupported).map(\.stream))

        let statusByStream = await adapter.offlineRecordingStatus()
        for stream in PolarOfflineStream.allCases {
            let capability = offlineStreamCapabilities[stream]
            let status = statusByStream[stream] ?? .unknown
            if capability?.isSupported == false {
                offlineStreamRunStates[stream] = .unavailable
                offlineStreamRunMessages[stream] = capability?.reason ?? "Unsupported"
                continue
            }
            switch status {
            case .recording:
                offlineStreamRunStates[stream] = .recording
                offlineStreamRunMessages[stream] = "Recording"
            case .ready:
                offlineStreamRunStates[stream] = .ready
                offlineStreamRunMessages[stream] = "Ready"
            case .unavailable:
                offlineStreamRunStates[stream] = .unavailable
                offlineStreamRunMessages[stream] = "Unavailable"
            case .failed:
                offlineStreamRunStates[stream] = .failed
                offlineStreamRunMessages[stream] = "Failed"
            case .unknown:
                offlineStreamRunStates[stream] = .unknown
                offlineStreamRunMessages[stream] = "Unknown"
            }
        }

        if selectedOfflineStreams.isEmpty {
            selectedOfflineStreams = supportedStreams
        } else {
            selectedOfflineStreams = Set(selectedOfflineStreams.filter { supportedStreams.contains($0) })
        }

        do {
            offlineRecordings = try await adapter.listOfflineRecordings()
        } catch {
            offlineLastErrorMessage = "Listing failed during reconnect refresh: \(error.localizedDescription)"
        }

        for stream in supportedStreams where offlineSettingsLoadStateByStream[stream] == nil {
            offlineSettingsLoadStateByStream[stream] = .notLoaded
        }

        updateRecoveredStates()
        let hasRecording = offlineRecoveredStateByStream.values.contains(where: { $0.isRecording })
        let hasFailedStream = offlineRecoveredStateByStream.values.contains(where: { $0.status == .failed || $0.status == .unknown })
        if hasRecording {
            offlineLifecycleState = .recoveredRecording
            offlineStatusMessage = "Device already has active offline recordings. State restored after reconnect."
        } else if hasFailedStream {
            offlineLifecycleState = .failed
            offlineStatusMessage = "Failed to refresh offline state"
        } else if supportedStreams.isEmpty {
            offlineLifecycleState = .featureUnavailable
            offlineStatusMessage = capabilities.first(where: { !$0.isSupported })?.reason ?? "Offline recording unavailable"
        } else {
            offlineLifecycleState = .ready
            offlineStatusMessage = "Ready"
        }
    }

    func offlineSettingsSummary(for stream: PolarOfflineStream) -> String {
        if let settings = offlineSettingsByStream[stream] {
            return settings.selected.summary()
        }
        switch offlineSettingsLoadStateByStream[stream] ?? .notLoaded {
        case .notLoaded:
            return "Not loaded"
        case .loading:
            return "Loading..."
        case .ready:
            return "Ready"
        case .failed(let message):
            return "Failed: \(message)"
        }
    }

    func canConfigureOfflineStream(_ stream: PolarOfflineStream) -> Bool {
        guard let capability = offlineStreamCapabilities[stream], capability.isSupported else { return false }
        if let settings = offlineSettingsByStream[stream] {
            return settings.options.isConfigurable
        }
        return true
    }

    func loadOfflineSettings(for stream: PolarOfflineStream) async {
        guard let capability = offlineStreamCapabilities[stream], capability.isSupported else { return }
        offlineSettingsLoadStateByStream[stream] = .loading
        offlineStreamRunStates[stream] = .loadingSettings
        offlineStreamRunMessages[stream] = "Loading settings..."
        let result = await adapter.offlineRecordingSettings(for: stream)
        switch result {
        case .success(let settings):
            offlineSettingsByStream[stream] = settings
            applyRegistrySelectionToOfflineStream(stream)
            offlineSettingsLoadStateByStream[stream] = .ready
            offlineStreamRunStates[stream] = .ready
            offlineStreamRunMessages[stream] = settings.options.isConfigurable ? "Settings ready" : "No configurable settings"
        case .failure(let failure):
            let message = failure.message
            offlineSettingsLoadStateByStream[stream] = .failed(message: message)
            offlineStreamRunStates[stream] = .failed
            offlineStreamRunMessages[stream] = "Settings failed: \(message)"
        }
    }

    func applyRegistryOfflineConfiguration() async {
        let streams = configurationRegistry.quickSessionOfflineStreams
        selectOfflineStreams(streams)
        for stream in streams {
            await loadOfflineSettings(for: stream)
            guard let settings = offlineSettingsByStream[stream] else { continue }
            if stream == .acc {
                configurationRegistry.updateAccFallbackFromSDKOptions(
                    deviceID: "polar_verity_sense",
                    modeID: "offline",
                    sampleRates: settings.options.sampleRates
                )
                let effective = configurationRegistry.effectiveSettings(
                    deviceID: "polar_verity_sense",
                    modeID: "offline",
                    streamID: "acc"
                )
                let sampleRate = effective["sample_rate_hz"]?.numberUInt32
                let resolution = effective["resolution_bit"]?.numberUInt32
                let rangeG = effective["range_g"]?.numberUInt32
                let channels = effective["channels"]?.numberUInt32
                updateOfflineSettingsSelection(
                    for: .acc,
                    sampleRate: sampleRate,
                    resolution: resolution,
                    range: rangeG,
                    channels: channels
                )
            }
        }
    }

    func updateOfflineSettingsSelection(
        for stream: PolarOfflineStream,
        sampleRate: UInt32?,
        resolution: UInt32?,
        range: UInt32?,
        channels: UInt32?
    ) {
        guard let existing = offlineSettingsByStream[stream] else { return }
        let selection = OfflineStreamSettingsSelection(
            sampleRate: sampleRate,
            resolution: resolution,
            range: range,
            channels: channels
        )
        let updated = OfflineStreamSettings(stream: stream, options: existing.options, selected: selection)
        offlineSettingsByStream[stream] = updated
        adapter.updateOfflineRecordingSettingsSelection(selection, for: stream)
    }

    var offlineProgressSummary: String {
        let all = PolarOfflineStream.allCases
        let failed = all.filter { offlineStreamRunStates[$0] == .failed }.count
        let recording = all.filter { offlineStreamRunStates[$0] == .recording }.count
        let uploaded = all.filter { offlineStreamRunStates[$0] == .uploaded }.count
        return "recording: \(recording), uploaded: \(uploaded), failed: \(failed)"
    }

    func isOfflineActionDisabled(_ action: OfflineOperation) -> Bool {
        if action == .uploading && hasActiveOfflineRecording() {
            return true
        }
        if action == .deleting && hasActiveOfflineRecording() {
            return true
        }
        guard offlineIsOperationRunning else { return false }
        return offlineOperation != action
    }

    func canStartOfflineSelected() -> Bool {
        selectedOfflineStreams.contains { stream in
            guard capabilityForOfflineStream(stream).isSupported else { return false }
            return offlineStreamRunStates[stream] != .recording
        }
    }

    func canStopOfflineSelected() -> Bool {
        selectedOfflineStreams.contains { offlineStreamRunStates[$0] == .recording }
    }

    func selectOfflineStreams(_ streams: Set<PolarOfflineStream>) {
        selectedOfflineStreams = streams
    }

    func startOfflineSelected() async {
        await startOffline(streams: selectedOfflineStreams.sorted { $0.rawValue < $1.rawValue })
    }

    func startOfflineAllSupported() async {
        let streams = offlineStreamCapabilities.values.filter(\.isSupported).map(\.stream).sorted { $0.rawValue < $1.rawValue }
        await startOffline(streams: streams)
    }

    func stopOfflineSelected() async {
        await stopOffline(streams: selectedOfflineStreams.sorted { $0.rawValue < $1.rawValue })
    }

    func stopOfflineAllSupported() async {
        let streams = offlineStreamCapabilities.values.filter(\.isSupported).map(\.stream).sorted { $0.rawValue < $1.rawValue }
        await stopOffline(streams: streams)
        await uploadOfflineRecordings()
    }

    func listOfflineRecordings() async {
        guard beginOfflineOperation(.listing, lifecycle: .listing, statusMessage: "Listing offline recordings...") else { return }
        defer { completeOfflineOperation() }
        guard adapter.connectionState == .connected else {
            offlineLifecycleState = .disconnected
            offlineStatusMessage = "Device disconnected"
            offlineLastErrorMessage = "Device disconnected"
            return
        }
        do {
            let entries = try await adapter.listOfflineRecordings()
            offlineRecordings = entries
            refreshUnassignedRecordingGroups()
            offlineLifecycleState = .completed
            offlineStatusMessage = entries.isEmpty ? "No recordings found" : "Loaded \(entries.count) recording(s)"
            offlineLastSuccessAction = "Listed offline recordings"
        } catch {
            offlineLifecycleState = .failed
            offlineStatusMessage = "List failed: \(error.localizedDescription)"
            offlineLastErrorMessage = offlineStatusMessage
        }
    }

    func refreshOfflineData() async {
        await refreshOfflineCapabilities()
        await listOfflineRecordings()
        refreshUnassignedRecordingGroups()
    }

    func assignUnassignedAsSingleSession() {
        guard !unassignedOfflineRecordings.isEmpty else { return }
        let createdID = createExternalManagedSession(from: unassignedOfflineRecordings, note: "manual_merge_single_session")
        if let createdID {
            Task { @MainActor [weak self] in
                await self?.archiveManagedSessionIfNeeded(createdID)
            }
        }
        refreshUnassignedRecordingGroups()
    }

    func assignUnassignedByClusters() {
        guard !unassignedRecordingGroups.isEmpty else { return }
        for group in unassignedRecordingGroups where !group.entries.isEmpty {
            let createdID = createExternalManagedSession(from: group.entries, note: "manual_split_by_time_cluster")
            if let createdID {
                Task { @MainActor [weak self] in
                    await self?.archiveManagedSessionIfNeeded(createdID)
                }
            }
        }
        refreshUnassignedRecordingGroups()
    }

    func assignVisibleRecordingsAsSingleSession() {
        let candidates = unassignedRecordings(from: offlineRecordings)
        guard !candidates.isEmpty else {
            offlineLastErrorMessage = "All visible recordings are already assigned to sessions"
            return
        }
        let createdID = createExternalManagedSession(from: candidates, note: "manual_merge_visible_recordings")
        if let createdID {
            Task { @MainActor [weak self] in
                await self?.archiveManagedSessionIfNeeded(createdID)
            }
        }
        refreshUnassignedRecordingGroups()
    }

    func assignVisibleRecordingsByClusters() {
        let candidates = unassignedRecordings(from: offlineRecordings)
        let clusters = clusterUnassignedRecordings(candidates)
        guard !clusters.isEmpty else { return }
        for group in clusters where !group.entries.isEmpty {
            let createdID = createExternalManagedSession(from: group.entries, note: "manual_split_visible_recordings_by_cluster")
            if let createdID {
                Task { @MainActor [weak self] in
                    await self?.archiveManagedSessionIfNeeded(createdID)
                }
            }
        }
        refreshUnassignedRecordingGroups()
    }

    func pendingManifest(for sessionID: UUID) -> PendingSessionManifest? {
        pendingSessionManifests.first(where: { $0.sessionID == sessionID })
    }

    func removePendingManifest(id: String) {
        pendingSessionManifests.removeAll { $0.id == id }
        persistLedger()
    }

    func deleteManagedSession(id: UUID) {
        managedSessions.removeAll { $0.id == id }
        pendingSessionManifests.removeAll { $0.sessionID == id }
        offlineSessionArchiveStore.deleteSessionArchive(sessionID: id)
        persistLedger()
        refreshUnassignedRecordingGroups()
    }

    func deleteAllManagedSessions() {
        let ids = Set(managedSessions.map(\.id))
        managedSessions.removeAll()
        pendingSessionManifests.removeAll { ids.contains($0.sessionID) }
        for id in ids {
            offlineSessionArchiveStore.deleteSessionArchive(sessionID: id)
        }
        expandedCleanupAfterSessionDelete(ids: ids)
        persistLedger()
        refreshUnassignedRecordingGroups()
    }

    private func expandedCleanupAfterSessionDelete(ids: Set<UUID>) {
        guard !ids.isEmpty else { return }
        var transferStates = offlineFileTransferStateStore.load()
        transferStates.removeAll { state in
            guard let sid = state.lastSessionID else { return false }
            return ids.contains(sid)
        }
        offlineFileTransferStateStore.save(transferStates)
    }

    func uploadManagedSessionsChronologically() async {
        let ordered = managedSessions.sorted { $0.startedAtUTC < $1.startedAtUTC }
        managedSessionUploadStatusMessage = "Uploading \(ordered.count) session(s) in chronology..."
        for session in ordered {
            await uploadManagedSession(session.id)
        }
        managedSessionUploadStatusMessage = "Chronological upload completed"
    }

    func isManagedSessionArchived(_ id: UUID) -> Bool {
        !offlineSessionArchiveStore.loadBatches(sessionID: id).isEmpty
    }

    func localArchiveFilePath(for sessionID: UUID) -> String {
        offlineSessionArchiveStore.archiveFileURL(sessionID: sessionID).path
    }

    func offlineRecordingSafetySummary(for entry: OfflineRecordingEntry) -> OfflineRecordingSafetySummary {
        let isRecordingNow: Bool
        if let stream = entry.stream {
            isRecordingNow = offlineStreamRunStates[stream] == .recording
        } else {
            isRecordingNow = false
        }

        let linkedSession = managedSessions.first(where: { session in
            session.linkedFiles.contains(where: { $0.path == entry.path })
        })

        let state = transferState(for: entry.path)
        let hasLocalArchiveCopy = state != nil
        let hasUploadedComplete = state?.isUploadedComplete == true

        return OfflineRecordingSafetySummary(
            isRecordingNow: isRecordingNow,
            isAssignedToSession: linkedSession != nil,
            assignedSessionID: linkedSession?.clientSessionID,
            hasLocalArchiveCopy: hasLocalArchiveCopy,
            safeToDeleteFromSensor: !isRecordingNow && hasUploadedComplete
        )
    }

    func retryPendingManifest(for sessionID: UUID) async {
        guard !isManifestSyncRunning else { return }
        guard transport.isNetworkUploadConfigured else {
            manifestSyncStatusMessage = "Network upload is not configured"
            return
        }
        guard let session = managedSessions.first(where: { $0.id == sessionID }) else { return }
        guard let pending = pendingSessionManifests.first(where: { $0.sessionID == sessionID }) else { return }

        isManifestSyncRunning = true
        manifestSyncStatusMessage = "Syncing manifest for \(session.clientSessionID)..."
        defer {
            isManifestSyncRunning = false
            persistLedger()
        }

        do {
            let payload = buildSessionManifestPayload(from: session)
            _ = try await transport.uploadSessionManifest(payload)
            pendingSessionManifests.removeAll { $0.id == pending.id }
            manifestSyncStatusMessage = "Manifest synced for \(session.clientSessionID)"
        } catch {
            if let index = pendingSessionManifests.firstIndex(where: { $0.id == pending.id }) {
                pendingSessionManifests[index].retryCount += 1
                pendingSessionManifests[index].lastError = error.localizedDescription
                pendingSessionManifests[index].updatedAtUTC = nowProvider()
            }
            manifestSyncStatusMessage = "Manifest sync failed for \(session.clientSessionID)"
        }
    }

    func uploadOfflineRecordings() async {
        beginBackgroundTaskIfNeeded(name: "offline-upload")
        defer { endBackgroundTaskIfNeeded() }
        guard beginOfflineOperation(.uploading, lifecycle: .uploading, statusMessage: "Uploading offline recordings...") else { return }
        defer {
            offlineFetchProgress = nil
            completeOfflineOperation()
        }
        guard adapter.connectionState == .connected else {
            offlineLifecycleState = .disconnected
            offlineStatusMessage = "Device disconnected"
            offlineLastErrorMessage = "Device disconnected"
            return
        }

        offlineStatusMessage = "Fetching offline recordings..."
        for stream in selectedOfflineStreams {
            offlineStreamRunStates[stream] = .fetching
        }
        let entries: [OfflineRecordingEntry]
        do {
            entries = try await adapter.listOfflineRecordings()
        } catch {
            offlineLifecycleState = .failed
            offlineStatusMessage = "Failed to list offline recordings: \(error.localizedDescription)"
            offlineLastErrorMessage = offlineStatusMessage
            return
        }
        let candidates = selectOfflineUploadCandidates(from: entries, allowedPaths: nil)
            .filter { !isOfflineFileUploadedComplete(path: $0.path) }
        guard !candidates.isEmpty else {
            uploadStatus = .success
            offlineLifecycleState = .completed
            offlineStatusMessage = "No pending offline recordings (already uploaded)"
            offlineLastSuccessAction = "Skipped already uploaded files"
            return
        }

        let candidateStreams = candidates.compactMap { entry -> CollectorStream? in
            guard let stream = entry.stream else { return nil }
            return collectorStream(for: stream)
        }
        ensureUploadSessionIfNeeded(for: candidateStreams)
        guard let session = activeSession else {
            offlineLifecycleState = .failed
            offlineStatusMessage = "No active session for upload"
            offlineLastErrorMessage = offlineStatusMessage
            return
        }
        let sampleChunkLimit = max(500, Int(ProcessInfo.processInfo.environment["COLLECTOR_OFFLINE_UPLOAD_CHUNK_SAMPLES"] ?? "") ?? 5000)
        let existingCheckpoints = loadedCheckpointKeys(sessionID: session.sessionID)
        let files = candidates.compactMap { entry -> ManagedSessionFile? in
            guard let offlineStream = entry.stream else { return nil }
            let stream = collectorStream(for: offlineStream)
            return ManagedSessionFile(
                path: entry.path,
                stream: stream.transportType,
                startedAtUTC: entry.startedAt,
                sizeBytes: entry.sizeBytes
            )
        }
        linkFilesToManagedSession(id: session.sessionID, files: files)

        offlineStatusMessage = "Uploading chunks..."
        log("offline_upload_stage=server_upload_start files=\(candidates.count)", category: "offline-upload")
        for stream in selectedOfflineStreams {
            offlineStreamRunStates[stream] = .uploading
        }

        var attemptedParts = 0
        var skippedParts = 0
        for (fileIndex, entry) in candidates.enumerated() {
            offlineStatusMessage = "Reading file \(fileIndex + 1)/\(candidates.count)..."
            let preparation = await adapter.prepareOfflineUploadBatches(allowedPaths: [entry.path]) { [weak self] progress in
                Task { @MainActor in
                    guard let self else { return }
                    self.offlineFetchProgress = progress
                }
            }
            if !preparation.batches.isEmpty {
                markOfflineFileFetched(path: entry.path, sessionID: session.sessionID)
            }
            offlineStreamRunMessages.merge(preparation.messagesByStream, uniquingKeysWith: { _, new in new })
            var fileUploadedOrDeduped = true
            for batch in preparation.batches {
                let parts = splitForUpload(batch, sampleLimit: sampleChunkLimit)
                for (partIndex, part) in parts.enumerated() {
                    attemptedParts += 1
                    let component = "\(part.sourcePath.lowercased())#part-\(partIndex)"
                    let dedupeKey = checkpointKey(sessionID: session.sessionID, batch: part, component: component)
                    if existingCheckpoints.contains(dedupeKey) {
                        skippedParts += 1
                        continue
                    }
                    bufferedSamplesByStream[part.stream] = part.samples
                    if let context = part.timeContext {
                        pendingTimeContextByStream[part.stream] = context
                    }
                    bufferedSamplesCount = bufferedSampleTotalCount()
                    offlineStatusMessage = "Uploading file \(fileIndex + 1)/\(candidates.count), part \(partIndex + 1)/\(parts.count) (\(part.stream.transportType))..."
                    await flushAndUploadAllBufferedSamples(trigger: .manual)
                    if uploadStatus == .failure {
                        fileUploadedOrDeduped = false
                        break
                    }
                    markCheckpointUploaded(sessionID: session.sessionID, batch: part, component: component)
                }
                if uploadStatus == .failure {
                    fileUploadedOrDeduped = false
                    break
                }
            }
            if fileUploadedOrDeduped {
                markOfflineFileUploadedComplete(path: entry.path, sessionID: session.sessionID)
            }
            if uploadStatus == .failure { break }
        }
        if skippedParts > 0 {
            log("offline_upload_stage=dedupe_skip skipped=\(skippedParts) total=\(attemptedParts)", category: "offline-upload")
        }
        if attemptedParts > 0 && skippedParts == attemptedParts && uploadStatus != .failure {
            uploadStatus = .success
            offlineLifecycleState = .completed
            offlineStatusMessage = "All prepared files already uploaded (deduplicated)"
            offlineLastSuccessAction = "Deduplicated retry upload"
        } else if uploadStatus == .idle {
            uploadStatus = .success
        }
        if uploadStatus == .success {
            offlineLifecycleState = .completed
            offlineStatusMessage = "Offline recordings uploaded"
            offlineLastSuccessAction = "Uploaded offline recordings"
            if let session = activeSession {
                updateManagedSessionLifecycle(
                    id: session.sessionID,
                    lifecycle: .uploaded,
                    stoppedAtUTC: session.stoppedAtUTC,
                    notes: "offline_upload_success"
                )
            }
            for stream in selectedOfflineStreams {
                offlineStreamRunStates[stream] = .uploaded
            }
        } else if uploadStatus == .failure {
            offlineLifecycleState = .failed
            offlineStatusMessage = "Offline upload failed"
            offlineLastErrorMessage = offlineStatusMessage
            if let session = activeSession {
                updateManagedSessionLifecycle(
                    id: session.sessionID,
                    lifecycle: .partiallyUploaded,
                    stoppedAtUTC: session.stoppedAtUTC,
                    notes: "offline_upload_failed"
                )
            }
            for stream in selectedOfflineStreams {
                offlineStreamRunStates[stream] = .failed
            }
        } else {
            offlineLifecycleState = .partialSuccess
            offlineStatusMessage = "Offline upload completed with mixed result"
        }
    }

    func uploadManagedSession(_ id: UUID) async {
        guard let session = managedSessions.first(where: { $0.id == id }) else { return }
        let allowedPaths = Set(session.linkedFiles.map(\.path))
        guard !allowedPaths.isEmpty else {
            offlineLastErrorMessage = "Session has no linked files to upload"
            managedSessionUploadStatusByID[id] = "No linked files"
            return
        }
        isManagedSessionUploadRunning = true
        managedSessionUploadStatusByID[id] = "Preparing upload..."
        managedSessionUploadStatusMessage = "Uploading \(session.clientSessionID)..."
        defer {
            isManagedSessionUploadRunning = false
        }
        log("Session upload requested: \(session.clientSessionID) files=\(allowedPaths.count)", category: "session")

        guard beginOfflineOperation(.uploading, lifecycle: .uploading, statusMessage: "Uploading session...") else { return }
        defer { completeOfflineOperation() }

        let sourceLabel = "device files (streamed)"
        managedSessionUploadStatusByID[id] = "Reading files from device..."
        log("session_upload_stage=device_read_start session=\(session.clientSessionID) files=\(allowedPaths.count)", category: "session")
        let sampleChunkLimit = max(500, Int(ProcessInfo.processInfo.environment["COLLECTOR_OFFLINE_UPLOAD_CHUNK_SAMPLES"] ?? "") ?? 5000)
        let checkpointKeys = loadedCheckpointKeys(sessionID: session.id)
        managedSessionUploadStatusByID[id] = "Uploading (\(sourceLabel))..."
        log("session_upload_stage=server_upload_start session=\(session.clientSessionID) source=\(sourceLabel) files=\(allowedPaths.count)", category: "session")

        activeSession = CollectionSession(
            sessionID: session.id,
            device: adapter.deviceIdentity,
            collectionMode: session.collectionMode,
            startedAtUTC: session.startedAtUTC,
            stoppedAtUTC: session.stoppedAtUTC,
            supportedStreams: adapter.availableStreams
        )

        var attemptedParts = 0
        var skippedParts = 0
        var uploadedParts = 0
        let orderedPaths = Array(allowedPaths).sorted()
        for (fileIndex, path) in orderedPaths.enumerated() {
            managedSessionUploadStatusByID[id] = "Reading file \(fileIndex + 1)/\(orderedPaths.count)..."
            let fetched = await adapter.prepareOfflineUploadBatches(allowedPaths: [path]) { [weak self] progress in
                Task { @MainActor in
                    guard let self else { return }
                    self.offlineFetchProgress = progress
                    let total = max(progress.totalEntries, 1)
                    let percent = Int((Double(progress.processedEntries) / Double(total)) * 100.0)
                    self.managedSessionUploadStatusByID[id] = "Reading file \(fileIndex + 1)/\(orderedPaths.count)... \(progress.processedEntries)/\(progress.totalEntries) (\(percent)%)"
                }
            }
            if !fetched.batches.isEmpty {
                markOfflineFileFetched(path: path, sessionID: session.id)
            }
            offlineStreamRunMessages.merge(fetched.messagesByStream, uniquingKeysWith: { _, new in new })
            var fileUploadedOrDeduped = true
            for batch in fetched.batches {
                if streamDescriptorsByType[batch.stream] == nil {
                    streamDescriptorsByType[batch.stream] = transport.makeStreamDescriptor(
                        for: batch.stream,
                        source: adapter.sourceIdentifier
                    )
                }
                if nextChunkSequenceNumberByStream[batch.stream] == nil {
                    nextChunkSequenceNumberByStream[batch.stream] = 1
                }
                if lastFlushAtUTCByStream[batch.stream] == nil {
                    lastFlushAtUTCByStream[batch.stream] = nowProvider()
                }
                let parts = splitForUpload(batch, sampleLimit: sampleChunkLimit)
                for (partIndex, part) in parts.enumerated() {
                    attemptedParts += 1
                    let component = "\(part.sourcePath.lowercased())#part-\(partIndex)"
                    let dedupeKey = checkpointKey(sessionID: session.id, batch: part, component: component)
                    if checkpointKeys.contains(dedupeKey) {
                        skippedParts += 1
                        continue
                    }
                    managedSessionUploadStatusByID[id] = "Uploading file \(fileIndex + 1)/\(orderedPaths.count), part \(partIndex + 1)/\(parts.count) (\(part.stream.transportType))..."
                    bufferedSamplesByStream[part.stream] = part.samples
                    if let context = part.timeContext {
                        pendingTimeContextByStream[part.stream] = context
                    }
                    bufferedSamplesCount = bufferedSampleTotalCount()
                    await flushAndUploadAllBufferedSamples(trigger: .manual)
                    if uploadStatus == .failure {
                        fileUploadedOrDeduped = false
                        break
                    }
                    markCheckpointUploaded(sessionID: session.id, batch: part, component: component)
                    uploadedParts += 1
                }
                if uploadStatus == .failure {
                    fileUploadedOrDeduped = false
                    break
                }
            }
            if fileUploadedOrDeduped {
                markOfflineFileUploadedComplete(path: path, sessionID: session.id)
            }
            if uploadStatus == .failure { break }
        }
        if skippedParts > 0 {
            log("session_upload_stage=dedupe_skip session=\(session.clientSessionID) skipped=\(skippedParts) total=\(attemptedParts)", category: "session")
        }
        if attemptedParts > 0 && skippedParts == attemptedParts && uploadStatus != .failure {
            uploadStatus = .success
            managedSessionUploadStatusByID[id] = "All files already uploaded"
            managedSessionUploadStatusMessage = "Deduplicated \(session.clientSessionID)"
        } else if uploadStatus == .idle && uploadedParts > 0 {
            uploadStatus = .success
        }
        if uploadStatus == .success {
            updateManagedSessionLifecycle(
                id: session.id,
                lifecycle: .uploaded,
                stoppedAtUTC: session.stoppedAtUTC,
                notes: "session_upload_success"
            )
            managedSessionUploadStatusByID[id] = "Uploaded to server"
            managedSessionUploadStatusMessage = "Uploaded \(session.clientSessionID)"
            log("session_upload_stage=server_upload_done session=\(session.clientSessionID)", category: "session")
            await retryPendingManifest(for: session.id)
        } else if uploadStatus == .failure {
            updateManagedSessionLifecycle(
                id: session.id,
                lifecycle: .partiallyUploaded,
                stoppedAtUTC: session.stoppedAtUTC,
                notes: "session_upload_failed"
            )
            managedSessionUploadStatusByID[id] = "Upload failed, local copy kept"
            managedSessionUploadStatusMessage = "Upload failed for \(session.clientSessionID)"
            log("session_upload_stage=server_upload_failed session=\(session.clientSessionID)", level: .error, category: "session")
        } else {
            managedSessionUploadStatusByID[id] = "Upload completed with mixed result"
            managedSessionUploadStatusMessage = "Mixed upload result for \(session.clientSessionID)"
            log("session_upload_stage=server_upload_mixed session=\(session.clientSessionID)", level: .warning, category: "session")
        }
        offlineFetchProgress = nil
    }

    func deleteOfflineRecording(_ entry: OfflineRecordingEntry) async {
        guard !isUploadingChunk else {
            offlineLastErrorMessage = "Cannot delete while upload is running"
            return
        }
        guard beginOfflineOperation(.deleting, lifecycle: .deleting, statusMessage: "Deleting offline recording...") else { return }
        deletingOfflineRecordingIDs.insert(entry.id)
        defer {
            deletingOfflineRecordingIDs.remove(entry.id)
            completeOfflineOperation()
        }
        if let stream = entry.stream {
            let liveStatus = await adapter.offlineRecordingStatus()
            if liveStatus[stream] == .recording {
                _ = await adapter.stopOfflineRecordings(streams: [stream])
                try? await Task.sleep(nanoseconds: 300_000_000)
            }
        }
        do {
            try await adapter.removeOfflineRecording(path: entry.path)
            clearTransferState(for: entry.path)
            offlineRecordings.removeAll { $0.id == entry.id }
            refreshUnassignedRecordingGroups()
            offlineRecordErrorsByID[entry.id] = nil
            offlineLifecycleState = .completed
            offlineStatusMessage = "Deleted recording"
            offlineLastSuccessAction = "Deleted offline recording"
        } catch {
            let message = "Delete failed: \(error.localizedDescription)"
            offlineRecordErrorsByID[entry.id] = message
            offlineLifecycleState = .failed
            offlineStatusMessage = message
            offlineLastErrorMessage = message
        }
    }

    func deleteAllOfflineRecordings(confirmed: Bool) async {
        guard confirmed else {
            offlineLastErrorMessage = "Delete all recordings requires confirmation"
            return
        }
        guard !isUploadingChunk else {
            offlineLastErrorMessage = "Cannot delete while upload is running"
            return
        }
        guard beginOfflineOperation(.deleting, lifecycle: .deleting, statusMessage: "Deleting all offline recordings...") else { return }
        defer { completeOfflineOperation() }
        guard adapter.connectionState == .connected else {
            offlineLifecycleState = .disconnected
            offlineStatusMessage = "Device disconnected"
            offlineLastErrorMessage = "Device disconnected"
            return
        }

        let liveStatus = await adapter.offlineRecordingStatus()
        let activeStreams = liveStatus.compactMap { stream, status in
            status == .recording ? stream : nil
        }
        if !activeStreams.isEmpty {
            offlineStatusMessage = "Stopping active recordings before delete..."
            _ = await adapter.stopOfflineRecordings(streams: activeStreams)
            try? await Task.sleep(nanoseconds: 400_000_000)
        }

        let entries: [OfflineRecordingEntry]
        do {
            entries = try await adapter.listOfflineRecordings()
        } catch {
            offlineLifecycleState = .failed
            offlineStatusMessage = "List failed: \(error.localizedDescription)"
            offlineLastErrorMessage = offlineStatusMessage
            return
        }

        if entries.isEmpty {
            offlineLifecycleState = .completed
            offlineStatusMessage = "No recordings to delete"
            offlineLastSuccessAction = "Deleted all offline recordings"
            offlineRecordings = []
            refreshUnassignedRecordingGroups()
            return
        }

        var deletedIDs = Set<String>()
        var failed: [String] = []

        for (index, entry) in entries.enumerated() {
            deletingOfflineRecordingIDs.insert(entry.id)
            offlineStatusMessage = "Deleting recording \(index + 1)/\(entries.count)..."
            do {
                try await adapter.removeOfflineRecording(path: entry.path)
                clearTransferState(for: entry.path)
                deletedIDs.insert(entry.id)
                offlineRecordErrorsByID[entry.id] = nil
            } catch {
                let message = "Delete failed: \(error.localizedDescription)"
                offlineRecordErrorsByID[entry.id] = message
                failed.append(entry.path)
            }
            deletingOfflineRecordingIDs.remove(entry.id)
        }

        offlineRecordings.removeAll { deletedIDs.contains($0.id) }
        refreshUnassignedRecordingGroups()
        if failed.isEmpty {
            offlineLifecycleState = .completed
            offlineStatusMessage = "Deleted \(entries.count) recording(s)"
            offlineLastSuccessAction = "Deleted all offline recordings"
            return
        }

        offlineLifecycleState = .partialSuccess
        let successCount = entries.count - failed.count
        offlineStatusMessage = "Deleted \(successCount)/\(entries.count) recording(s)"
        offlineLastErrorMessage = "Failed to delete \(failed.count) recording(s)"
    }

    func stopCollection() {
        log("Stop tapped")
        autoFlushTask?.cancel()
        autoFlushTask = nil

        activeProviders.forEach { $0.stop() }
        activeProviders.removeAll()

        adapter.disconnect()
        debugExporter.stopSession()
        if activeSession != nil {
            activeSession?.markStopped(at: Date())
            if let session = activeSession {
                updateManagedSessionLifecycle(
                    id: session.sessionID,
                    lifecycle: .stopped,
                    stoppedAtUTC: session.stoppedAtUTC,
                    notes: "stopped_in_app"
                )
            }
        }
        status = selectedDevice == nil ? .disconnected : .stopped
        activityMessage = "Collection stopped"
        log("Collection stopped")

        if bufferedSamplesCount > 0 {
            log(
                "Final flush requested on stop, buffered samples: \(bufferedSamplesCount)",
                category: "upload"
            )
            Task { @MainActor [weak self] in
                await self?.flushAndUploadAllBufferedSamples(trigger: .finalOnStop)
            }
        }

        if let debugExportFileURL {
            log("Export ready: \(debugExportFileURL.lastPathComponent)")
        }
    }

    @discardableResult
    func prepareUploadChunk() -> UploadChunk? {
        guard let stream = firstBufferedStream() else {
            activityMessage = "Nothing to prepare (no buffered samples)"
            log("Prepare skipped: no buffered samples")
            return nil
        }
        return prepareUploadChunk(for: stream, trigger: .manual)
    }

    @discardableResult
    func prepareUploadChunk(for stream: CollectorStream, trigger: FlushTrigger) -> UploadChunk? {
        isPreparingChunk = true
        uploadStatus = .idle

        let streamLabel = stream.transportType
        switch trigger {
        case .manual:
            activityMessage = "Preparing \(streamLabel) chunk..."
            log("Prepare Chunk tapped for stream=\(streamLabel)")
        case .sampleCount:
            activityMessage = "Auto flush: \(streamLabel) threshold reached"
            log(
                "Auto flush triggered by sample count for stream=\(streamLabel)",
                category: "upload"
            )
        case .timer:
            activityMessage = "Auto flush: interval reached for \(streamLabel)"
            log(
                "Auto flush triggered by timer for stream=\(streamLabel)",
                category: "upload"
            )
        case .finalOnStop:
            activityMessage = "Final flush on stop (\(streamLabel))..."
            log("Final flush on stop triggered for stream=\(streamLabel)", category: "upload")
        }
        defer {
            isPreparingChunk = false
        }

        guard
            let session = activeSession,
            let streamDescriptor = streamDescriptorsByType[stream],
            let streamSamples = bufferedSamplesByStream[stream],
            !streamSamples.isEmpty
        else {
            activityMessage = "Nothing to prepare (no buffered samples)"
            log("Prepare skipped: no buffered samples for stream=\(streamLabel)")
            return nil
        }

        let streamProfile = resolvedStreamProfile(for: stream, session: session)
        let chunkSequenceNumber = nextChunkSequenceNumberByStream[stream] ?? 1

        let chunk = transport.prepareUploadChunk(
            session: session,
            streamDescriptor: streamDescriptor,
            streamProfile: streamProfile,
            chunkSequenceNumber: chunkSequenceNumber,
            samples: streamSamples,
            timeContext: resolveChunkTimeContext(for: stream, session: session)
        )

        if let chunk {
            let firstSampleAt = Self.iso8601(from: chunk.samples.first?.collectorReceivedAtUTC)
            let lastSampleAt = Self.iso8601(from: chunk.samples.last?.collectorReceivedAtUTC)
            let sessionID = chunk.sessionID.uuidString.lowercased()
            pendingUploadChunks.append(chunk)
            pendingUploadChunksCount = pendingUploadChunks.count
            lastPreparedChunk = pendingUploadChunks.last

            nextChunkSequenceNumberByStream[stream] = chunkSequenceNumber + 1
            bufferedSamplesByStream[stream] = []
            pendingTimeContextByStream[stream] = nil
            bufferedSamplesCount = bufferedSampleTotalCount()
            lastFlushAtUTCByStream[stream] = nowProvider()
            self.streamDescriptor = streamDescriptor

            activityMessage = "Chunk #\(chunk.chunkSequenceNumber) prepared (\(chunk.samples.count) samples)"
            log(
                "Chunk prepared session_id=\(sessionID) stream_type=\(chunk.streamType) sequence=\(chunk.chunkSequenceNumber) chunk_id=\(chunk.chunkID.uuidString.lowercased()) samples=\(chunk.samples.count) first_sample=\(firstSampleAt) last_sample=\(lastSampleAt) pending=\(pendingUploadChunksCount)",
                category: "upload"
            )
        } else {
            activityMessage = "Chunk preparation returned no data"
            log("Prepare returned nil chunk", level: .warning, category: "upload")
        }

        return chunk
    }

    func resolveChunkTimeContext(for stream: CollectorStream, session: CollectionSession) -> UploadChunkTimeContext {
        if let pending = pendingTimeContextByStream[stream] {
            return pending
        }

        let now = nowProvider()
        let timezoneOffsetMinutes = TimeZone.current.secondsFromGMT(for: now) / 60
        let clockSyncState: String
        switch deviceTimeSyncState {
        case .success:
            clockSyncState = "synced"
        case .failed:
            clockSyncState = "unsynced"
        case .idle, .running, .unavailable:
            clockSyncState = "unknown"
        }

        return UploadChunkTimeContext(
            recordingStartUTC: session.startedAtUTC,
            recordingEndUTC: session.stoppedAtUTC,
            fileCreatedAtDevice: nil,
            fileClosedAtDevice: nil,
            deviceLocalTimeAtFetch: now,
            deviceTimezoneOffset: timezoneOffsetMinutes,
            clockSyncState: clockSyncState,
            clockDriftEstimate: nil,
            sourceAppOrigin: session.collectionMode == .offlineRecording ? "unknown" : "our_app",
            sensorRecordingID: nil,
            fetchStartedAtCollector: now,
            fetchCompletedAtCollector: now
        )
    }

    func uploadLastPreparedChunk() async {
        guard !pendingUploadChunks.isEmpty else {
            reportFailure(
                userMessage: "No prepared chunk available",
                activity: "Nothing to upload (prepare chunk first)",
                technical: "Upload requested with empty pending queue",
                category: "upload"
            )
            uploadStatus = .failure
            return
        }

        isUploadingChunk = true
        uploadStatus = .idle
        clearFailureState()
        let firstChunk = pendingUploadChunks[0]
        let firstSampleAt = Self.iso8601(from: firstChunk.samples.first?.collectorReceivedAtUTC)
        let lastSampleAt = Self.iso8601(from: firstChunk.samples.last?.collectorReceivedAtUTC)
        activityMessage = "Uploading chunk #\(firstChunk.chunkSequenceNumber) to server..."
        let firstSessionID = firstChunk.sessionID.uuidString.lowercased()
        log(
            "Upload started session_id=\(firstSessionID) stream_type=\(firstChunk.streamType) sequence=\(firstChunk.chunkSequenceNumber) chunk_id=\(firstChunk.chunkID.uuidString.lowercased()) samples=\(firstChunk.samples.count) first_sample=\(firstSampleAt) last_sample=\(lastSampleAt) destination=\(transport.uploadDestinationDescription) pending_before=\(pendingUploadChunksCount)",
            category: "upload"
        )
        if !transport.isNetworkUploadConfigured {
            log(
                "Network upload endpoint is not configured. This upload runs in mock mode and does not send an HTTP request.",
                level: .warning,
                category: "upload"
            )
        }
        defer {
            isUploadingChunk = false
        }

        var uploadedCount = 0

        while let chunk = pendingUploadChunks.first {
            do {
                let ack = try await transport.upload(chunk: chunk)
                pendingUploadChunks.removeFirst()
                pendingUploadChunksCount = pendingUploadChunks.count
                lastPreparedChunk = pendingUploadChunks.last
                uploadedCount += 1
                uploadStatus = .success
                consecutiveUploadFailureCount = 0
                nextUploadRetryAtUTC = nil
                activityMessage = "Uploaded \(uploadedCount) chunk(s). Pending: \(pendingUploadChunksCount)"
                let uploadedFirstSampleAt = Self.iso8601(from: chunk.samples.first?.collectorReceivedAtUTC)
                let uploadedLastSampleAt = Self.iso8601(from: chunk.samples.last?.collectorReceivedAtUTC)
                let sessionID = chunk.sessionID.uuidString.lowercased()
                log(
                    "Upload succeeded session_id=\(sessionID) stream_type=\(chunk.streamType) sequence=\(chunk.chunkSequenceNumber) chunk_id=\(chunk.chunkID.uuidString.lowercased()) samples=\(chunk.samples.count) first_sample=\(uploadedFirstSampleAt) last_sample=\(uploadedLastSampleAt) ack_status=\(ack.status) accepted=\(ack.accepted) pending_after=\(pendingUploadChunksCount) message=\(ack.message ?? "none")",
                    category: "upload"
                )
            } catch {
                uploadStatus = .failure
                consecutiveUploadFailureCount += 1
                let retryDelay = uploadConfiguration.retry.nextDelaySeconds(forAttempt: consecutiveUploadFailureCount)
                nextUploadRetryAtUTC = nowProvider().addingTimeInterval(retryDelay)
                let message = error.localizedDescription
                reportFailure(
                    userMessage: "Upload failed: \(message)",
                    activity: "Upload failed after \(uploadedCount) success(es). Pending: \(pendingUploadChunksCount)",
                    technical: "Upload failed session_id=\(chunk.sessionID.uuidString.lowercased()) stream_type=\(chunk.streamType) sequence=\(chunk.chunkSequenceNumber) chunk_id=\(chunk.chunkID.uuidString.lowercased()) error=\(message). Chunk kept in pending queue for retry.",
                    category: "upload"
                )
                if let nextUploadRetryAtUTC {
                    log(
                        "Retry scheduled in \(Int(retryDelay))s at \(Self.iso8601(from: nextUploadRetryAtUTC))",
                        level: .warning,
                        category: "upload"
                    )
                }
                return
            }
        }
    }

    func handle(sample: HeartRateSample) async {
        if sample.stream == .heartRate {
            latestHeartRateSample = sample
        }
        if let batteryData = sample.batteryData {
            updateBatteryStatus(
                from: batteryData,
                deviceID: selectedDevice?.id ?? activeSession?.deviceID,
                timestamp: sample.collectorReceivedAtUTC
            )
        }

        totalSamplesReceived += 1

        var streamSamples = bufferedSamplesByStream[sample.stream] ?? []
        streamSamples.append(sample)
        bufferedSamplesByStream[sample.stream] = streamSamples
        bufferedSamplesCount = bufferedSampleTotalCount()

        if totalSamplesReceived == 1 {
            log("First sample received for stream=\(sample.stream.transportType)", category: "samples")
        } else if totalSamplesReceived.isMultiple(of: 25) {
            log("Samples received total: \(totalSamplesReceived)", level: .debug, category: "samples")
        }

        if let sessionID = activeSession?.sessionID {
            debugExporter.appendSample(
                sessionID: sessionID,
                sample: sample
            )
        }

        if status == .collecting, let flushCount = uploadConfiguration.sampleFlushCount(for: sample.stream) {
            if streamSamples.count >= flushCount {
                await flushAndUploadBufferedSamples(
                    for: sample.stream,
                    trigger: .sampleCount,
                    enforceThreshold: true
                )
            }
        }
    }

    func startAutoFlushTask() {
        autoFlushTask = Task { @MainActor [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                await self.sleepProvider(1_000_000_000)
                guard !Task.isCancelled else { return }
                guard self.status == .collecting else { continue }

                if !self.pendingUploadChunks.isEmpty,
                   !self.isUploadingChunk,
                   self.shouldRetryPendingUploads(now: self.nowProvider()) {
                    self.log("Retrying pending chunks (\(self.pendingUploadChunks.count))", category: "upload")
                    await self.uploadLastPreparedChunk()
                }

                guard self.bufferedSamplesCount > 0 else { continue }

                for stream in self.streamFlushOrder() {
                    guard let streamSamples = self.bufferedSamplesByStream[stream], !streamSamples.isEmpty else {
                        continue
                    }
                    guard let lastFlushAtUTC = self.lastFlushAtUTCByStream[stream] else { continue }

                    let elapsed = self.nowProvider().timeIntervalSince(lastFlushAtUTC)
                    if elapsed >= self.uploadConfiguration.uploadFlushIntervalSeconds {
                        await self.flushAndUploadBufferedSamples(
                            for: stream,
                            trigger: .timer,
                            enforceThreshold: false
                        )
                    }
                }
            }
        }
    }

    func flushAndUploadAllBufferedSamples(trigger: FlushTrigger) async {
        for stream in streamFlushOrder() {
            await flushAndUploadBufferedSamples(
                for: stream,
                trigger: trigger,
                enforceThreshold: false
            )
        }
    }

    func flushAndUploadBufferedSamples(
        for stream: CollectorStream,
        trigger: FlushTrigger,
        enforceThreshold: Bool
    ) async {
        guard !isAutoFlushing else { return }
        guard let buffered = bufferedSamplesByStream[stream], !buffered.isEmpty else { return }

        isAutoFlushing = true
        defer { isAutoFlushing = false }

        var currentTrigger = trigger

        while let currentBuffered = bufferedSamplesByStream[stream], !currentBuffered.isEmpty {
            let threshold = uploadConfiguration.sampleFlushCount(for: stream)
            if enforceThreshold, let threshold, currentBuffered.count < threshold {
                return
            }

            guard prepareUploadChunk(for: stream, trigger: currentTrigger) != nil else { return }
            await uploadLastPreparedChunk()

            if status != .collecting && trigger != .finalOnStop {
                return
            }

            guard let remaining = bufferedSamplesByStream[stream], !remaining.isEmpty else { return }

            if trigger == .sampleCount {
                guard let threshold else { return }
                guard remaining.count >= threshold else { return }
                currentTrigger = .sampleCount
                continue
            }

            if trigger == .timer || trigger == .finalOnStop {
                currentTrigger = trigger
                continue
            }

            return
        }
    }

    func prepareLogExportFile() {
        guard !eventLogs.isEmpty else {
            reportFailure(
                userMessage: "No logs available for export",
                activity: "No logs to export",
                technical: "Log export skipped: no logs",
                category: "logging"
            )
            return
        }

        let fileName = "collector-events-\(Self.logFileDateFormatter.string(from: Date())).log"
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        let payload = eventLogs.joined(separator: "\n") + "\n"

        do {
            try payload.write(to: fileURL, atomically: true, encoding: .utf8)
            logExportFileURL = fileURL
            activityMessage = "Log export ready"
            log("Log export created: \(fileURL.lastPathComponent)", category: "logging")
        } catch {
            reportFailure(
                userMessage: "Failed to export logs: \(error.localizedDescription)",
                activity: "Log export failed",
                technical: "Failed to export logs: \(error.localizedDescription)",
                category: "logging"
            )
        }
    }

    func refreshCachedStatuses(for devices: [CollectorDevice]) {
        for device in devices {
            refreshCachedStatus(for: device.id)
        }
        discoveredDeviceStatusByID = Dictionary(
            uniqueKeysWithValues: devices.compactMap { device in
                guard let snapshot = latestStatusByDeviceID[device.id] else { return nil }
                return (device.id, snapshot)
            }
        )
    }

    func refreshCachedStatus(for deviceID: String) {
        guard let adapterSnapshot = adapter.cachedDeviceStatusSnapshot(for: deviceID) else {
            if selectedDevice?.id == deviceID {
                latestDeviceStatusSnapshot = latestStatusByDeviceID[deviceID]
            }
            return
        }

        let existing = latestStatusByDeviceID[deviceID]
        let source = adapterSnapshot.status.battery?.source ?? .cached
        let mergedBattery = BatteryStatus(
            levelPercent: adapterSnapshot.status.battery?.levelPercent ?? existing?.status.battery?.levelPercent,
            chargeState: adapterSnapshot.status.battery?.chargeState ?? existing?.status.battery?.chargeState,
            lastUpdatedAt: adapterSnapshot.status.battery?.lastUpdatedAt ?? adapterSnapshot.updatedAt,
            source: source,
            unavailableReason: adapterSnapshot.status.battery?.unavailableReason
        )
        latestStatusByDeviceID[deviceID] = DeviceStatusSnapshot(
            deviceID: deviceID,
            status: DeviceStatus(battery: mergedBattery),
            updatedAt: adapterSnapshot.updatedAt
        )
        if selectedDevice?.id == deviceID {
            latestDeviceStatusSnapshot = latestStatusByDeviceID[deviceID]
        }
    }

    func updateBatteryStatus(from batteryData: PolarBatteryData, deviceID: String?, timestamp: Date) {
        guard let deviceID else { return }

        let source: BatteryStatusSource?
        switch batteryData.eventType {
        case .callbackUpdate:
            source = .callback
        case .pollSnapshot:
            source = .poll
        case .batteryUnavailable:
            source = .unavailable
        }

        let battery = BatteryStatus(
            levelPercent: batteryData.levelPercent,
            chargeState: BatteryChargeState(rawOrNil: batteryData.chargeState),
            lastUpdatedAt: timestamp,
            source: source,
            unavailableReason: batteryData.unavailableReason
        )
        let snapshot = DeviceStatusSnapshot(
            deviceID: deviceID,
            status: DeviceStatus(battery: battery),
            updatedAt: timestamp
        )
        latestStatusByDeviceID[deviceID] = snapshot
        latestDeviceStatusSnapshot = snapshot
        if discoveredDevices.contains(where: { $0.id == deviceID }) {
            discoveredDeviceStatusByID[deviceID] = snapshot
        }
    }

    func formatBattery(_ battery: BatteryStatus?) -> String {
        guard let battery else {
            return "unknown"
        }
        if let levelPercent = battery.levelPercent {
            return "\(levelPercent)%"
        }
        if let chargeState = battery.chargeState {
            return chargeState.rawValue.replacingOccurrences(of: "_", with: " ")
        }
        if battery.source == .unavailable {
            return "unavailable"
        }
        return "unknown"
    }

    func clearFailureState() {
        lastErrorMessage = nil
        shouldSuggestLogExport = false
    }

    func ensureUploadSessionIfNeeded(for streams: [CollectorStream]) {
        if activeSession == nil {
            let session = CollectionSession(
                device: adapter.deviceIdentity,
                collectionMode: .offlineRecording,
                startedAtUTC: nowProvider(),
                supportedStreams: adapter.availableStreams
            )
            activeSession = session
            prepareDebugExport(for: session)
            upsertManagedSession(
                id: session.sessionID,
                clientSessionID: session.clientSessionID,
                mode: session.collectionMode,
                origin: .ourApp,
                lifecycle: .started,
                startedAtUTC: session.startedAtUTC,
                stoppedAtUTC: nil,
                linkedFiles: [],
                notes: "offline_upload_session_bootstrap"
            )
        }

        for stream in Set(streams) {
            if streamDescriptorsByType[stream] == nil {
                streamDescriptorsByType[stream] = transport.makeStreamDescriptor(
                    for: stream,
                    source: adapter.sourceIdentifier
                )
            }
            if nextChunkSequenceNumberByStream[stream] == nil {
                nextChunkSequenceNumberByStream[stream] = 1
            }
            if lastFlushAtUTCByStream[stream] == nil {
                lastFlushAtUTCByStream[stream] = nowProvider()
            }
        }
    }

    func startOffline(streams: [PolarOfflineStream]) async {
        guard beginOfflineOperation(.starting, lifecycle: .starting, statusMessage: "Starting offline recordings...") else { return }
        defer { completeOfflineOperation() }
        guard adapter.connectionState == .connected else {
            offlineLifecycleState = .disconnected
            offlineStatusMessage = "Device disconnected"
            offlineLastErrorMessage = "Device disconnected"
            return
        }
        guard !streams.isEmpty else {
            offlineLifecycleState = .featureUnavailable
            offlineStatusMessage = "No supported offline streams selected"
            offlineLastErrorMessage = offlineStatusMessage
            return
        }

        _ = await runPreOfflineSyncTimeCheck()
        for stream in streams {
            let state = offlineSettingsLoadStateByStream[stream] ?? .notLoaded
            if case .notLoaded = state {
                await loadOfflineSettings(for: stream)
            }
        }
        let liveStatusByStream = await adapter.offlineRecordingStatus()
        let alreadyRecordingStreams = streams.filter {
            offlineStreamRunStates[$0] == .recording || liveStatusByStream[$0] == .recording
        }
        let startableStreams = streams.filter { stream in
            guard !alreadyRecordingStreams.contains(stream) else { return false }
            if case .failed = (offlineSettingsLoadStateByStream[stream] ?? .notLoaded) {
                return false
            }
            return true
        }
        for stream in startableStreams {
            offlineStreamRunStates[stream] = .starting
            offlineStreamRunMessages[stream] = "Starting..."
        }
        let requests = startableStreams.map { stream in
            OfflineRecordingStartRequest(stream: stream, selectedSettings: sanitizedOfflineSelection(for: stream))
        }
        let adapterResults = await adapter.startOfflineRecordings(requests: requests)
        let alreadyRecordingResults = alreadyRecordingStreams.map {
            OfflineStreamOperationResult(stream: $0, success: true, message: "Already recording (attached)")
        }
        let failedSettingsResults = streams.filter {
            !startableStreams.contains($0) && !alreadyRecordingStreams.contains($0)
        }.map {
            OfflineStreamOperationResult(stream: $0, success: false, message: "Settings unavailable for stream")
        }
        let results = adapterResults + failedSettingsResults + alreadyRecordingResults
        offlineStreamRunMessages.merge(
            Dictionary(uniqueKeysWithValues: results.map { ($0.stream, $0.message) }),
            uniquingKeysWith: { _, new in new }
        )
        for result in results {
            offlineStreamRunStates[result.stream] = result.success ? .recording : .failed
        }
        let successCount = results.filter(\.success).count
        if successCount == results.count {
            offlineLifecycleState = .recording
            offlineStatusMessage = "Offline recording started (\(successCount)/\(results.count))"
            offlineLastSuccessAction = "Started offline recordings"
        } else if successCount > 0 {
            offlineLifecycleState = .partialSuccess
            offlineStatusMessage = "Partial start success (\(successCount)/\(results.count))"
            offlineLastErrorMessage = results.first(where: { !$0.success })?.message
        } else {
            offlineLifecycleState = .failed
            offlineStatusMessage = "Offline start failed"
            offlineLastErrorMessage = results.first?.message
        }
    }

    func stopOffline(streams: [PolarOfflineStream]) async {
        guard beginOfflineOperation(.stopping, lifecycle: .stopping, statusMessage: "Stopping offline recordings...") else { return }
        defer { completeOfflineOperation() }
        guard adapter.connectionState == .connected else {
            offlineLifecycleState = .disconnected
            offlineStatusMessage = "Device disconnected"
            offlineLastErrorMessage = "Device disconnected"
            return
        }
        guard !streams.isEmpty else {
            offlineLifecycleState = .featureUnavailable
            offlineStatusMessage = "No supported offline streams selected"
            offlineLastErrorMessage = offlineStatusMessage
            return
        }

        let liveStatusByStream = await adapter.offlineRecordingStatus()
        let stoppableStreams = streams.filter {
            offlineStreamRunStates[$0] == .recording || liveStatusByStream[$0] == .recording
        }
        let alreadyStoppedStreams = streams.filter { !stoppableStreams.contains($0) }

        stoppableStreams.forEach { offlineStreamRunStates[$0] = .stopping }
        let adapterResults = await adapter.stopOfflineRecordings(streams: stoppableStreams)
        let alreadyStoppedResults = alreadyStoppedStreams.map {
            OfflineStreamOperationResult(stream: $0, success: true, message: "Already stopped")
        }
        let results = adapterResults + alreadyStoppedResults
        offlineStreamRunMessages.merge(
            Dictionary(uniqueKeysWithValues: results.map { ($0.stream, $0.message) }),
            uniquingKeysWith: { _, new in new }
        )
        for result in results {
            offlineStreamRunStates[result.stream] = result.success ? .ready : .failed
        }
        let successCount = results.filter(\.success).count
        if successCount == results.count {
            offlineLifecycleState = .ready
            offlineStatusMessage = "Offline recording stopped (\(successCount)/\(results.count))"
            offlineLastSuccessAction = "Stopped offline recordings"
        } else if successCount > 0 {
            offlineLifecycleState = .partialSuccess
            offlineStatusMessage = "Partial stop success (\(successCount)/\(results.count))"
            offlineLastErrorMessage = results.first(where: { !$0.success })?.message
        } else {
            offlineLifecycleState = .failed
            offlineStatusMessage = "Offline stop failed"
            offlineLastErrorMessage = results.first?.message
        }
    }

    func beginOfflineOperation(
        _ operation: OfflineOperation,
        lifecycle: OfflineLifecycleState,
        statusMessage: String
    ) -> Bool {
        guard !offlineIsOperationRunning else { return false }
        offlineIsOperationRunning = true
        offlineOperation = operation
        offlineLifecycleState = lifecycle
        offlineStatusMessage = statusMessage
        return true
    }

    func completeOfflineOperation() {
        offlineIsOperationRunning = false
        offlineOperation = .none
        updateRecoveredStates()
    }

    func hasActiveOfflineRecording() -> Bool {
        offlineRecoveredStateByStream.values.contains(where: { $0.isRecording })
    }

    func updateRecoveredStates() {
        var next: [PolarOfflineStream: OfflineStreamRecoveredState] = [:]
        let recordingsByStream = Dictionary(grouping: offlineRecordings, by: \.stream)
        for stream in PolarOfflineStream.allCases {
            let capability = capabilityForOfflineStream(stream)
            let runState = offlineStreamRunStates[stream] ?? .unknown
            let status: OfflineStreamStatus
            switch runState {
            case .recording:
                status = .recording
            case .ready, .uploaded:
                status = .ready
            case .unavailable:
                status = .unavailable
            case .failed:
                status = .failed
            case .unknown, .loadingSettings, .starting, .stopping, .fetching, .uploading:
                status = .unknown
            }
            next[stream] = OfflineStreamRecoveredState(
                isSelected: selectedOfflineStreams.contains(stream),
                isSupported: capability.isSupported,
                isRecording: runState == .recording,
                status: status,
                lastError: runState == .failed ? offlineStreamRunMessages[stream] : nil,
                lastKnownRecordInfo: recordingsByStream[stream]?.first ?? nil
            )
        }
        offlineRecoveredStateByStream = next
    }

    func applyDeviceTimeActionResult(_ result: DeviceTimeActionResult, isSyncAction: Bool) {
        deviceTimeSyncState = result.state
        deviceTimeStatusMessage = result.message
        deviceTimeDebugDetails = result.debugDetails ?? "Stream timestamp verification not performed"
        lastDeviceTimeDeltaSeconds = result.verificationDeltaSeconds
        operationalTimeEvents.append(contentsOf: result.operationalEvents)
        if operationalTimeEvents.count > 100 {
            operationalTimeEvents.removeFirst(operationalTimeEvents.count - 100)
        }

        if let readback = result.readbackDeviceTime {
            lastDeviceTimeReadResult = Self.iso8601(from: readback)
        } else if result.state == .unavailable {
            lastDeviceTimeReadResult = "Read-back unavailable"
        }

        if isSyncAction {
            lastDeviceTimeSyncResult = result.message
        }
        log("Device time action result: state=\(result.state.rawValue) message=\(result.message)", category: "device-time")
    }

    func reportFailure(
        userMessage: String,
        activity: String,
        technical: String,
        category: String
    ) {
        lastErrorMessage = userMessage
        activityMessage = activity
        shouldSuggestLogExport = true
        log(technical, level: .error, category: category)
    }

    func log(
        _ message: String,
        level: CoreLogLevel = .info,
        category: String = "core"
    ) {
        if level == .debug && !isVerboseLoggingEnabled {
            return
        }

        let timestamp = Self.logTimestampFormatter.string(from: Date())
        let line = "[\(timestamp)] [\(level.rawValue)] [\(category)] \(message)"
        print(line)
        eventLogs.append(line)
        if eventLogs.count > 1000 {
            eventLogs.removeFirst(eventLogs.count - 1000)
        }
        appendToPersistentLog(line)
    }

    private func appendToPersistentLog(_ line: String) {
        if persistentLogFileHandle == nil {
            let fileURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("collector-app-events.log")
            if !FileManager.default.fileExists(atPath: fileURL.path) {
                FileManager.default.createFile(atPath: fileURL.path, contents: nil)
            }
            do {
                let handle = try FileHandle(forWritingTo: fileURL)
                try handle.seekToEnd()
                persistentLogFileHandle = handle
                persistentLogFileURL = fileURL
            } catch {
                return
            }
        }

        guard let persistentLogFileHandle else { return }
        guard let data = (line + "\n").data(using: .utf8) else { return }
        do {
            try persistentLogFileHandle.write(contentsOf: data)
        } catch {
            // Ignore write failures to keep main flow unaffected.
        }
    }

    func bufferedSampleTotalCount() -> Int {
        bufferedSamplesByStream.values.reduce(0) { $0 + $1.count }
    }

    func shouldRetryPendingUploads(now: Date) -> Bool {
        guard let nextUploadRetryAtUTC else { return true }
        return now >= nextUploadRetryAtUTC
    }

    func streamFlushOrder() -> [CollectorStream] {
        [
            .heartRate,
            .ecg,
            .accelerometer,
            .ppi,
            .ppg,
            .magnetometer,
            .gyroscope,
            .battery,
            .eeg
        ]
    }

    func firstBufferedStream() -> CollectorStream? {
        streamFlushOrder().first { stream in
            let samples = bufferedSamplesByStream[stream] ?? []
            return !samples.isEmpty
        }
    }

    func resolvedStreamProfile(for stream: CollectorStream, session: CollectionSession) -> StreamMetadataProfile {
        guard session.collectionMode == .offlineRecording else {
            return uploadConfiguration.streamProfile(for: stream)
        }
        switch stream {
        case .heartRate: return PolarStreamProfile.hrOffline
        case .ppi: return PolarStreamProfile.ppiOffline
        case .accelerometer: return PolarStreamProfile.accOffline
        case .ppg: return PolarStreamProfile.ppgOffline
        case .magnetometer: return PolarStreamProfile.magOffline
        case .gyroscope: return PolarStreamProfile.gyrOffline
        case .ecg, .eeg, .battery:
            return uploadConfiguration.streamProfile(for: stream)
        }
    }

}

@MainActor
private extension CollectorCore {
    func runWithBackgroundTask<T>(
        name: String,
        operation: @escaping @MainActor () async -> T
    ) async -> T {
        beginBackgroundTaskIfNeeded(name: name)
        defer { endBackgroundTaskIfNeeded() }
        return await operation()
    }

    func beginBackgroundTaskIfNeeded(name: String) {
        guard backgroundTaskID == .invalid else { return }
        backgroundTaskID = UIApplication.shared.beginBackgroundTask(withName: name) { [weak self] in
            Task { @MainActor in
                self?.log("Background task expired: \(name)", level: .warning, category: "lifecycle")
                self?.endBackgroundTaskIfNeeded()
            }
        }
        if backgroundTaskID != .invalid {
            log("Background task started: \(name)", category: "lifecycle")
        } else {
            log("Background task unavailable: \(name)", level: .warning, category: "lifecycle")
        }
    }

    func endBackgroundTaskIfNeeded() {
        guard backgroundTaskID != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTaskID)
        backgroundTaskID = .invalid
        log("Background task ended", category: "lifecycle")
    }
}

private extension StreamSettingValue {
    var numberUInt32: UInt32? {
        guard case .number(let value) = self, value >= 0 else { return nil }
        return UInt32(value.rounded())
    }
}
