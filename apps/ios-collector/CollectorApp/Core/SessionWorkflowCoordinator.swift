import Foundation

struct PipelineTriggerResult: Equatable {
    let accepted: Bool
    let sessionID: String
    let message: String
    let dashboardURL: String?
}

@MainActor
final class SessionWorkflowCoordinator: NightSessionCoordinating {
    private let core: CollectorCore
    private let pipelineEndpoint: URL?
    private let dashboardEndpoint: URL?

    init(core: CollectorCore, pipelineEndpoint: URL?, dashboardEndpoint: URL?) {
        self.core = core
        self.pipelineEndpoint = pipelineEndpoint
        self.dashboardEndpoint = dashboardEndpoint
    }

    func startNightSession() async throws {
        if core.selectedDevice == nil {
            await core.scanAndSelectDevice()
        }
        if core.status != .connected && core.status != .stopped {
            await core.connectSelectedDevice()
        }
        guard core.status == .connected || core.status == .stopped else {
            throw WorkflowError.failed(core.lastErrorMessage ?? "Device is not connected")
        }

        core.selectOfflineStreams([.ppi, .acc])
        await core.refreshOfflineData()
        if core.canStartOfflineSelected() {
            await core.startOfflineSelected()
        }

        let isRecordingNow = core.offlineLifecycleState == .recording
            || core.offlineLifecycleState == .partialSuccess
            || core.selectedOfflineStreams.contains { core.offlineStreamRunStates[$0] == .recording }
        guard isRecordingNow else {
            throw WorkflowError.failed(
                core.offlineStatusMessage.isEmpty
                    ? "Failed to start offline recording"
                    : core.offlineStatusMessage
            )
        }
    }

    func stopSyncAndUpload() async throws -> String {
        core.selectOfflineStreams([.ppi, .acc])
        await core.stopOfflineSelected()
        if core.offlineLifecycleState == .failed {
            throw WorkflowError.failed(core.offlineStatusMessage)
        }

        await core.refreshOfflineData()
        await core.uploadOfflineRecordings()

        guard core.uploadStatus == .success || core.offlineLifecycleState == .completed else {
            throw WorkflowError.failed(core.offlineStatusMessage)
        }

        if let session = core.activeSession {
            return session.sessionID.uuidString.lowercased()
        }
        guard let session = core.managedSessions.first else {
            throw WorkflowError.failed("No uploaded session found")
        }
        return session.id.uuidString.lowercased()
    }

    func triggerPipeline(sessionID: String) async throws -> PipelineTriggerResult {
        guard let pipelineEndpoint else {
            return PipelineTriggerResult(
                accepted: false,
                sessionID: sessionID,
                message: "Pipeline endpoint is not configured",
                dashboardURL: nil
            )
        }

        var request = URLRequest(url: pipelineEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 10
        let body: [String: Any] = [
            "session_id": sessionID,
            "requested_steps": ["normalize", "window_features", "session_summary"]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw WorkflowError.failed("Pipeline trigger request failed")
        }

        guard
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let accepted = json["accepted"] as? Bool,
            let responseSessionID = json["session_id"] as? String
        else {
            throw WorkflowError.failed("Invalid pipeline trigger response")
        }

        return PipelineTriggerResult(
            accepted: accepted,
            sessionID: responseSessionID,
            message: (json["message"] as? String) ?? "",
            dashboardURL: resolvedDashboardURL(from: json["dashboard_url"] as? String)
        )
    }

    private func resolvedDashboardURL(from rawValue: String?) -> String? {
        guard let rawValue, !rawValue.isEmpty else { return nil }
        let sessionID = extractSessionID(from: rawValue)
        if let sessionID, let uiURL = makeDashboardSessionDetailsURL(sessionID: sessionID) {
            return uiURL
        }
        if let absolute = URL(string: rawValue), absolute.scheme != nil {
            return absolute.absoluteString
        }
        guard let pipelineEndpoint else { return nil }
        guard let relative = URL(string: rawValue) else { return nil }
        return URL(string: relative.relativeString, relativeTo: pipelineEndpoint)?.absoluteURL.absoluteString
    }

    private func extractSessionID(from dashboardPath: String) -> String? {
        if dashboardPath.contains("/api/v1/operator/sessions/"),
           let token = dashboardPath.split(separator: "/").last {
            let value = String(token).trimmingCharacters(in: .whitespacesAndNewlines)
            return value.isEmpty ? nil : value
        }
        return nil
    }

    private func makeDashboardSessionDetailsURL(sessionID: String) -> String? {
        let baseURL = dashboardEndpoint ?? defaultDashboardEndpointFromPipeline()
        guard let baseURL else { return nil }
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else { return nil }
        components.path = "/"
        components.queryItems = [
            URLQueryItem(name: "page", value: "Session Details"),
            URLQueryItem(name: "session_id", value: sessionID)
        ]
        return components.url?.absoluteString
    }

    private func defaultDashboardEndpointFromPipeline() -> URL? {
        guard let pipelineEndpoint, var components = URLComponents(url: pipelineEndpoint, resolvingAgainstBaseURL: false) else {
            return nil
        }
        components.port = 18501
        components.path = "/"
        components.query = nil
        return components.url
    }

    enum WorkflowError: LocalizedError {
        case failed(String)

        var errorDescription: String? {
            switch self {
            case .failed(let message):
                return message
            }
        }
    }
}
