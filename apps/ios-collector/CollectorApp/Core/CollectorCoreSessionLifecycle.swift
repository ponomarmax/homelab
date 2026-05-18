import Foundation

extension CollectorCore {
    func upsertManagedSession(
        id: UUID,
        clientSessionID: String,
        mode: CollectionMode,
        origin: ManagedSessionOrigin,
        lifecycle: ManagedSessionLifecycle,
        startedAtUTC: Date,
        stoppedAtUTC: Date?,
        linkedFiles: [ManagedSessionFile],
        notes: String?
    ) {
        if let index = managedSessions.firstIndex(where: { $0.id == id }) {
            var existing = managedSessions[index]
            existing.lifecycle = lifecycle
            existing.stoppedAtUTC = stoppedAtUTC
            existing.origin = origin
            existing.notes = notes ?? existing.notes
            existing.linkedFiles = Array(Set(existing.linkedFiles + linkedFiles))
            managedSessions[index] = existing
            queueManifestSync(for: managedSessions[index])
        } else {
            managedSessions.append(
                ManagedSessionRecord(
                    id: id,
                    clientSessionID: clientSessionID,
                    deviceID: adapter.deviceIdentity.id,
                    deviceType: "\(adapter.deviceIdentity.vendor) \(adapter.deviceIdentity.model)",
                    collectionMode: mode,
                    origin: origin,
                    lifecycle: lifecycle,
                    startedAtUTC: startedAtUTC,
                    stoppedAtUTC: stoppedAtUTC,
                    linkedFiles: linkedFiles,
                    notes: notes
                )
            )
            if let created = managedSessions.last {
                queueManifestSync(for: created)
            }
        }
        managedSessions.sort { $0.startedAtUTC > $1.startedAtUTC }
        persistLedger()
        refreshUnassignedRecordingGroups()
    }

    func updateManagedSessionLifecycle(
        id: UUID,
        lifecycle: ManagedSessionLifecycle,
        stoppedAtUTC: Date?,
        notes: String?
    ) {
        guard let index = managedSessions.firstIndex(where: { $0.id == id }) else { return }
        managedSessions[index].lifecycle = lifecycle
        if let stoppedAtUTC {
            managedSessions[index].stoppedAtUTC = stoppedAtUTC
        }
        if let notes, !notes.isEmpty {
            managedSessions[index].notes = notes
        }
        queueManifestSync(for: managedSessions[index])
        persistLedger()
        refreshUnassignedRecordingGroups()
    }

    func linkFilesToManagedSession(id: UUID, files: [ManagedSessionFile]) {
        guard let index = managedSessions.firstIndex(where: { $0.id == id }) else { return }
        let existing = managedSessions[index].linkedFiles
        let merged = Array(Set(existing + files))
        managedSessions[index].linkedFiles = merged.sorted { $0.path < $1.path }
        persistLedger()
        refreshUnassignedRecordingGroups()
    }

    func refreshUnassignedRecordingGroups() {
        let assignedPaths = Set(managedSessions.flatMap { $0.linkedFiles.map(\.path) })
        let unassigned = offlineRecordings.filter { !assignedPaths.contains($0.path) }
        unassignedOfflineRecordings = unassigned.sorted {
            ($0.startedAt ?? .distantPast) < ($1.startedAt ?? .distantPast)
        }
        unassignedRecordingGroups = clusterUnassignedRecordings(unassignedOfflineRecordings)
    }

    func unassignedRecordings(from entries: [OfflineRecordingEntry]) -> [OfflineRecordingEntry] {
        let assignedPaths = Set(managedSessions.flatMap { $0.linkedFiles.map(\.path) })
        return entries.filter { !assignedPaths.contains($0.path) }
    }

    func clusterUnassignedRecordings(_ entries: [OfflineRecordingEntry]) -> [UnassignedRecordingGroup] {
        guard !entries.isEmpty else { return [] }
        let sorted = entries.sorted { ($0.startedAt ?? .distantPast) < ($1.startedAt ?? .distantPast) }
        var groups: [[OfflineRecordingEntry]] = []
        var current: [OfflineRecordingEntry] = []

        for entry in sorted {
            guard let last = current.last else {
                current = [entry]
                continue
            }
            guard let left = last.startedAt, let right = entry.startedAt else {
                groups.append(current)
                current = [entry]
                continue
            }
            if abs(right.timeIntervalSince(left)) <= unassignedClusterGapSeconds {
                current.append(entry)
            } else {
                groups.append(current)
                current = [entry]
            }
        }
        if !current.isEmpty {
            groups.append(current)
        }

        return groups.enumerated().map { index, items in
            let starts = items.compactMap(\.startedAt)
            return UnassignedRecordingGroup(
                id: "cluster-\(index + 1)",
                entries: items,
                startAtUTC: starts.min(),
                endAtUTC: starts.max()
            )
        }
    }

    func createExternalManagedSession(from entries: [OfflineRecordingEntry], note: String) -> UUID? {
        let candidates = unassignedRecordings(from: entries)
        guard !candidates.isEmpty else { return nil }
        let start = candidates.compactMap(\.startedAt).min() ?? nowProvider()
        let stop = candidates.compactMap(\.startedAt).max() ?? start
        let sessionUUID = UUID()
        let linkedFiles = candidates.map {
            ManagedSessionFile(
                path: $0.path,
                stream: $0.stream?.rawValue ?? "unknown",
                startedAtUTC: $0.startedAt,
                sizeBytes: $0.sizeBytes
            )
        }
        upsertManagedSession(
            id: sessionUUID,
            clientSessionID: CollectionSession.makeClientSessionID(startedAtUTC: start, sessionID: sessionUUID),
            mode: .offlineRecording,
            origin: .externalApp,
            lifecycle: .stopped,
            startedAtUTC: start,
            stoppedAtUTC: stop,
            linkedFiles: linkedFiles,
            notes: note
        )
        return sessionUUID
    }

    func archiveManagedSessionIfNeeded(_ sessionID: UUID) async {
        guard let session = managedSessions.first(where: { $0.id == sessionID }) else { return }
        if !offlineSessionArchiveStore.loadBatches(sessionID: sessionID).isEmpty {
            return
        }
        let allowedPaths = Set(session.linkedFiles.map(\.path))
        guard !allowedPaths.isEmpty else { return }
        let preparation = await adapter.prepareOfflineUploadBatches(allowedPaths: allowedPaths)
        guard !preparation.batches.isEmpty else { return }
        offlineSessionArchiveStore.saveBatches(
            sessionID: sessionID,
            clientSessionID: session.clientSessionID,
            startedAtUTC: session.startedAtUTC,
            batches: preparation.batches
        )
        managedSessionUploadStatusByID[sessionID] = "Saved locally"
    }

    func persistLedger() {
        sessionLedgerStore.save(sessions: managedSessions, pendingManifests: pendingSessionManifests)
    }

    func queueManifestSync(for record: ManagedSessionRecord) {
        let key = record.clientSessionID
        if pendingSessionManifests.contains(where: { $0.id == key }) {
            return
        }
        pendingSessionManifests.append(
            PendingSessionManifest(
                id: key,
                sessionID: record.id,
                clientSessionID: record.clientSessionID,
                lastError: nil,
                retryCount: 0,
                updatedAtUTC: nowProvider()
            )
        )
        persistLedger()
        guard isManifestAutoRetryEnabled else { return }
        Task { @MainActor [weak self] in
            await self?.retryPendingSessionManifestSync()
        }
    }

    func retryPendingSessionManifestSync() async {
        guard transport.isNetworkUploadConfigured else { return }
        guard !isManifestSyncRunning else { return }
        guard !pendingSessionManifests.isEmpty else {
            manifestSyncStatusMessage = "No pending manifests"
            return
        }

        isManifestSyncRunning = true
        defer {
            isManifestSyncRunning = false
            persistLedger()
        }

        let batch = Array(pendingSessionManifests.prefix(manifestRetryBatchSize))
        manifestSyncStatusMessage = "Syncing \(batch.count) manifest(s)..."
        var successCount = 0
        var failureCount = 0

        for item in batch {
            guard let session = managedSessions.first(where: { $0.id == item.sessionID }) else { continue }
            do {
                let payload = buildSessionManifestPayload(from: session)
                _ = try await transport.uploadSessionManifest(payload)
                pendingSessionManifests.removeAll { $0.id == item.id }
                successCount += 1
            } catch {
                if let index = pendingSessionManifests.firstIndex(where: { $0.id == item.id }) {
                    pendingSessionManifests[index].retryCount += 1
                    pendingSessionManifests[index].lastError = error.localizedDescription
                    pendingSessionManifests[index].updatedAtUTC = nowProvider()
                }
                failureCount += 1
            }
        }
        manifestSyncStatusMessage = "Manifest sync done: ok \(successCount), failed \(failureCount), left \(pendingSessionManifests.count)"
    }

    func buildSessionManifestPayload(from record: ManagedSessionRecord) -> SessionManifestPayload {
        SessionManifestPayload(
            schemaVersion: "1.0",
            sessionID: record.id.uuidString.lowercased(),
            deviceSessionID: record.clientSessionID,
            sessionMode: record.collectionMode.transportValue,
            collector: SessionManifestPayload.Collector(
                collectorID: "ios-collector",
                runtimeType: "ios",
                appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown",
                buildVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
            ),
            device: SessionManifestPayload.Device(
                vendor: "polar",
                model: adapter.deviceIdentity.model.lowercased(),
                deviceID: record.deviceID
            ),
            time: SessionManifestPayload.Time(
                startedAtSource: Self.iso8601(from: record.startedAtUTC),
                startedAtServer: nil
            ),
            metadata: SessionManifestPayload.Metadata(
                notes: record.notes,
                tags: ["origin:\(record.origin.rawValue)", "lifecycle:\(record.lifecycle.rawValue)"]
            )
        )
    }

    func reconcileOpenSessionsAfterLifecycleEvent() {
        // M1 recovery: if app restarted while we had open sessions and device no longer records,
        // mark those sessions as externally stopped to keep state deterministic for upload flows.
        guard adapter.connectionState == .connected else { return }
        let open = managedSessions.filter { $0.lifecycle == .started }
        guard !open.isEmpty else { return }

        Task { @MainActor [weak self] in
            guard let self else { return }
            let statusByStream = await self.adapter.offlineRecordingStatus()
            let hasActiveRecording = statusByStream.values.contains(.recording)
            guard !hasActiveRecording else { return }
            let now = self.nowProvider()
            for session in open {
                self.updateManagedSessionLifecycle(
                    id: session.id,
                    lifecycle: .stoppedExternal,
                    stoppedAtUTC: session.stoppedAtUTC ?? now,
                    notes: "auto_recovered_stopped_externally"
                )
            }
            if !open.isEmpty {
                self.log("Recovered \(open.count) open session(s) as externally stopped", category: "session")
            }
        }
    }

    static let logTimestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    static let logFileDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter
    }()

    static let uploadIso8601Formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }()

    static func iso8601(from date: Date?) -> String {
        guard let date else { return "n/a" }
        return uploadIso8601Formatter.string(from: date)
    }

    func prepareDebugExport(for session: CollectionSession) {
        debugExportFileURL = debugExporter.startSession(sessionID: session.sessionID)
        if let debugExportFileURL {
            log("Raw export file created: \(debugExportFileURL.lastPathComponent)", category: "export")
            activityMessage = "Collecting and writing JSONL export"
        } else {
            reportFailure(
                userMessage: "Failed to create JSONL export file",
                activity: "Export file creation failed",
                technical: "Failed to create JSONL export file",
                category: "export"
            )
        }
    }
}
