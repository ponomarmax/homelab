import SwiftUI

struct UploadStatusCard: View {
    @ObservedObject var collectorCore: CollectorCore

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Upload")
                .font(.subheadline.weight(.semibold))
            if collectorCore.offlineOperation == .uploading || collectorCore.offlineIsOperationRunning {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text(collectorCore.offlineOperation.rawValue)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            if let progress = collectorCore.offlineFetchProgress {
                ProgressView(value: progressValue(progress))
                Text(progressSummary(progress))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                if let path = progress.currentPath, !path.isEmpty {
                    Text("Current file: \(path)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            if !collectorCore.selectedOfflineStreams.isEmpty {
                ForEach(collectorCore.selectedOfflineStreams.sorted(by: { $0.rawValue < $1.rawValue }), id: \.self) { stream in
                    let message = collectorCore.offlineStreamRunMessages[stream] ?? "Idle"
                    HStack {
                        Text(stream.rawValue)
                            .font(.caption2.weight(.semibold))
                        Spacer()
                        Text(message)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
            Text(collectorCore.offlineStatusMessage)
                .font(.caption)
        }
    }

    private func progressValue(_ progress: OfflineUploadFetchProgress) -> Double {
        guard progress.totalEntries > 0 else { return 0 }
        return min(max(Double(progress.processedEntries) / Double(progress.totalEntries), 0), 1)
    }

    private func progressSummary(_ progress: OfflineUploadFetchProgress) -> String {
        let stage = progress.stage.capitalized
        let entries = "\(progress.processedEntries)/\(progress.totalEntries) files"
        let bytes: String
        if let totalBytes = progress.totalBytes, totalBytes > 0 {
            bytes = " • \(progress.processedBytes)/\(totalBytes) bytes"
        } else {
            bytes = ""
        }
        return "\(stage): \(entries)\(bytes)"
    }
}
