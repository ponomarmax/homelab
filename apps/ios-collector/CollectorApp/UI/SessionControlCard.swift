import SwiftUI

struct SessionControlCard: View {
    @ObservedObject var viewModel: NightSessionViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Night Session")
                .font(.headline)
            Button(viewModel.state.buttonTitle) {
                Task { await viewModel.onPrimaryButtonTapped() }
            }
            .buttonStyle(.borderedProminent)
            .disabled(viewModel.isActionInFlight)
        }
    }
}
