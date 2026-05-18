import SwiftUI

struct PipelineStatusCard: View {
    @ObservedObject var viewModel: NightSessionViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Pipeline")
                .font(.subheadline.weight(.semibold))
            if let dashboardURL = viewModel.dashboardURL, !dashboardURL.isEmpty {
                Link("Open operator session", destination: URL(string: dashboardURL)!)
                    .font(.caption)
            } else {
                Text("Dashboard link unavailable")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
