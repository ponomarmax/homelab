import SwiftUI

struct DeviceStatusCard: View {
    let deviceName: String
    let batteryText: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Device")
                .font(.subheadline.weight(.semibold))
            Text(deviceName)
                .font(.caption)
            Text("Battery: \(batteryText)")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}
