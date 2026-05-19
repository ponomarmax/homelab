import Foundation

protocol NightSessionCoordinating: AnyObject {
    func startNightSession() async throws
    func stopSyncAndUpload() async throws -> String
    func triggerPipeline(sessionID: String) async throws -> PipelineTriggerResult
}

@MainActor
final class NightSessionViewModel: ObservableObject {
    @Published private(set) var state: SessionOperationState = .idle
    @Published private(set) var collectorSessionID: String?
    @Published private(set) var backendSessionID: String?
    @Published private(set) var dashboardURL: String?
    @Published private(set) var startedAt: Date?
    @Published private(set) var statusMessage: String = "Idle"

    private let coordinator: NightSessionCoordinating

    init(coordinator: NightSessionCoordinating) {
        self.coordinator = coordinator
    }

    var isActionInFlight: Bool {
        switch state {
        case .connecting, .syncing, .uploading, .pipelineTriggering:
            return true
        default:
            return false
        }
    }

    func onPrimaryButtonTapped() async {
        do {
            switch state {
            case .recording:
                state = .syncing
                statusMessage = "Stopping and syncing..."
                let uploadedSessionID = try await coordinator.stopSyncAndUpload()
                collectorSessionID = uploadedSessionID
                backendSessionID = uploadedSessionID

                state = .uploading
                statusMessage = "Upload complete"

                state = .pipelineTriggering
                statusMessage = "Triggering pipeline..."
                let trigger = try await coordinator.triggerPipeline(sessionID: uploadedSessionID)
                dashboardURL = trigger.dashboardURL
                backendSessionID = trigger.sessionID

                if trigger.accepted {
                    state = .completed
                    statusMessage = "Pipeline trigger accepted"
                } else {
                    let normalizedMessage = normalizeMessage(trigger.message)
                    state = .failed(message: normalizedMessage)
                    statusMessage = normalizedMessage
                }

            default:
                state = .connecting
                statusMessage = "Connecting to device..."
                try await coordinator.startNightSession()
                startedAt = Date()
                state = .recording
                statusMessage = "Recording offline PPI + ACC"
            }
        } catch {
            let message = normalizeMessage(error.localizedDescription)
            state = .failed(message: message)
            statusMessage = message
        }
    }

    private func normalizeMessage(_ message: String) -> String {
        message.replacingOccurrences(of: " is no configured", with: " is not configured")
    }
}
