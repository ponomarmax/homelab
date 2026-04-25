import SwiftUI

struct CollectorView: View {
    @StateObject private var collectorCore: CollectorCore

    init(collectorCore: CollectorCore) {
        _collectorCore = StateObject(wrappedValue: collectorCore)
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Wearable HR Collector")
                        .font(.largeTitle.weight(.semibold))

                    statusCard
                    activityCard
                    exportCard
                    discoveredDevicesCard
                    metricsCard
                    diagnosticsCard
                    logsCard
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            actionRow
                .padding(16)
                .background(.ultraThinMaterial)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(.systemGroupedBackground))
    }

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            statusRow(title: "State", value: collectorCore.status.displayName)
            statusRow(title: "Device", value: collectorCore.selectedDevice?.name ?? "None")
            statusRow(title: "Mode", value: collectorCore.defaultCollectionMode.rawValue)
            statusRow(
                title: "Session",
                value: collectorCore.activeSession?.sessionID.uuidString ?? "Not started"
            )
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var activityCard: some View {
        HStack(spacing: 12) {
            if collectorCore.isScanningDevices || collectorCore.isConnectingDevice || collectorCore.isPreparingChunk {
                ProgressView()
                    .controlSize(.small)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Activity")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(collectorCore.activityMessage)
                    .font(.subheadline.weight(.medium))
            }
            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var discoveredDevicesCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Discovered Devices")
                .font(.headline)

            if collectorCore.discoveredDevices.isEmpty {
                Text("Run scan to list nearby Polar devices")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(collectorCore.discoveredDevices) { device in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(device.name)
                                .fontWeight(.medium)
                            Text(device.id)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Select") {
                            collectorCore.selectScannedDevice(device)
                        }
                        .buttonStyle(.bordered)
                        .disabled(
                            collectorCore.status == .collecting
                            || collectorCore.isScanningDevices
                            || collectorCore.isConnectingDevice
                        )

                        if collectorCore.selectedDevice?.id == device.id {
                            Text("Selected")
                                .font(.caption)
                                .foregroundStyle(.green)
                        }
                    }
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var exportCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Raw Export")
                .font(.headline)

            if let url = collectorCore.debugExportFileURL {
                Text("JSONL file: \(url.lastPathComponent)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Text("Each HR sample is appended immediately. Prepare Chunk does not export data.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                ShareLink(item: url) {
                    Text("Export Raw JSONL")
                }
                .buttonStyle(.borderedProminent)
                .disabled(collectorCore.totalSamplesReceived == 0)
            } else {
                Text("Start collection to create JSONL export file.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var metricsCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Live Metrics")
                .font(.headline)

            HStack(spacing: 16) {
                metricTile(
                    title: "Latest HR",
                    value: collectorCore.latestHeartRateSample.map { "\($0.hrBPM) bpm" } ?? "--"
                )
                metricTile(
                    title: "Samples",
                    value: "\(collectorCore.totalSamplesReceived)"
                )
            }

            if let sample = collectorCore.latestHeartRateSample {
                Text("Received at \(sample.collectorReceivedAtUTC.formatted(date: .omitted, time: .standard))")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var diagnosticsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Diagnostics")
                .font(.headline)

            statusRow(title: "Buffered Samples", value: "\(collectorCore.bufferedSamplesCount)")
            statusRow(
                title: "Stream",
                value: collectorCore.streamDescriptor?.streamName ?? "Not prepared"
            )
            statusRow(
                title: "Last Chunk",
                value: collectorCore.lastPreparedChunk.map {
                    "#\($0.chunkSequenceNumber) (\($0.samples.count) samples)"
                } ?? "Not prepared"
            )
            statusRow(
                title: "Export File",
                value: collectorCore.debugExportFileURL?.lastPathComponent ?? "Not created"
            )

            if let lastErrorMessage = collectorCore.lastErrorMessage {
                Text(lastErrorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var actionRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
            Button(collectorCore.isScanningDevices ? "Scanning..." : collectorCore.deviceActionTitle) {
                Task {
                    await collectorCore.scanAndSelectDevice()
                }
            }
            .buttonStyle(.bordered)
            .disabled(
                collectorCore.status == .collecting
                || collectorCore.isScanningDevices
                || collectorCore.isConnectingDevice
            )

            Button(collectorCore.isConnectingDevice ? "Connecting..." : "Start") {
                Task {
                    await collectorCore.startCollection()
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(
                !(collectorCore.status == .deviceSelected || collectorCore.status == .stopped)
                || collectorCore.isConnectingDevice
                || collectorCore.isScanningDevices
            )

            Button("Stop") {
                collectorCore.stopCollection()
            }
            .buttonStyle(.bordered)
            .disabled(collectorCore.status != .collecting)

            Button(collectorCore.isPreparingChunk ? "Preparing..." : "Prepare Chunk (Buffer -> Chunk)") {
                collectorCore.prepareUploadChunk()
            }
            .buttonStyle(.bordered)
            .disabled(collectorCore.bufferedSamplesCount == 0 || collectorCore.isPreparingChunk)
            }
        }
    }

    private var logsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Event Log")
                .font(.headline)
            Text("Prepare Chunk only packs buffered samples into a chunk and clears that buffer.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(collectorCore.eventLogs.suffix(20).enumerated()), id: \.offset) { item in
                        Text(item.element)
                            .font(.caption.monospaced())
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .frame(maxHeight: 180)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func statusRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.medium)
        }
    }

    private func metricTile(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title2.weight(.semibold))
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
