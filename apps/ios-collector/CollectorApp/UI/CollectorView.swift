import SwiftUI

struct CollectorView: View {
    @StateObject private var collectorCore: CollectorCore

    init(collectorCore: CollectorCore) {
        _collectorCore = StateObject(wrappedValue: collectorCore)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Wearable HR Collector")
                .font(.largeTitle.weight(.semibold))

            statusCard
            metricsCard
            actionRow

            Spacer()
        }
        .padding(24)
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
                value: collectorCore.activeSession?.id.uuidString ?? "Not started"
            )
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
                    value: collectorCore.latestHeartRateSample.map { "\($0.value) bpm" } ?? "--"
                )
                metricTile(
                    title: "Samples",
                    value: "\(collectorCore.totalSamplesReceived)"
                )
            }

            if let sample = collectorCore.latestHeartRateSample {
                Text("Received at \(sample.collectorReceivedAtUTC.formatted(date: .omitted, time: .standard)) UTC metadata placeholder")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var actionRow: some View {
        HStack(spacing: 12) {
            Button("Select Mock Device") {
                collectorCore.selectDevice()
            }
            .buttonStyle(.bordered)
            .disabled(collectorCore.status == .collecting)

            Button("Start") {
                Task {
                    await collectorCore.startCollection()
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(!(collectorCore.status == .deviceSelected || collectorCore.status == .stopped))

            Button("Stop") {
                collectorCore.stopCollection()
            }
            .buttonStyle(.bordered)
            .disabled(collectorCore.status != .collecting)
        }
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
