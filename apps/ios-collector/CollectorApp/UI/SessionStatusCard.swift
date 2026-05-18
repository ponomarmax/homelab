import SwiftUI

struct SessionStatusCard: View {
    @ObservedObject var viewModel: NightSessionViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Session Status")
                .font(.subheadline.weight(.semibold))
            Text(viewModel.statusMessage)
                .font(.caption)
            if let collectorSessionID = viewModel.collectorSessionID {
                Text("collector_session_id: \(collectorSessionID)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            if let backendSessionID = viewModel.backendSessionID {
                Text("backend_session_id: \(backendSessionID)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            if let startedAt = viewModel.startedAt {
                Text("started_at: \(startedAt.formatted())")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
