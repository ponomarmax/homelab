import SwiftUI

struct UploadStatusCard: View {
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Upload")
                .font(.subheadline.weight(.semibold))
            Text(message)
                .font(.caption)
        }
    }
}
