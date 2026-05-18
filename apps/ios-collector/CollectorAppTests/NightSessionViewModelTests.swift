import XCTest
@testable import CollectorApp

@MainActor
final class NightSessionViewModelTests: XCTestCase {
    final class MockCoordinator: NightSessionCoordinating {
        var startError: Error?
        var stopResultSessionID: String = "collector-session-1"
        var stopError: Error?
        var triggerResult = PipelineTriggerResult(
            accepted: true,
            sessionID: "collector-session-1",
            message: "ok",
            dashboardURL: "/api/v1/operator/sessions/collector-session-1"
        )
        var triggerError: Error?

        func startNightSession() async throws {
            if let startError { throw startError }
        }

        func stopSyncAndUpload() async throws -> String {
            if let stopError { throw stopError }
            return stopResultSessionID
        }

        func triggerPipeline(sessionID: String) async throws -> PipelineTriggerResult {
            if let triggerError { throw triggerError }
            return triggerResult
        }
    }

    struct TestError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    func test_idle_to_recording_transition() async {
        let coordinator = MockCoordinator()
        let viewModel = NightSessionViewModel(coordinator: coordinator)

        await viewModel.onPrimaryButtonTapped()

        XCTAssertEqual(viewModel.state, .recording)
    }

    func test_recording_to_completed_transition() async {
        let coordinator = MockCoordinator()
        let viewModel = NightSessionViewModel(coordinator: coordinator)

        await viewModel.onPrimaryButtonTapped()
        await viewModel.onPrimaryButtonTapped()

        XCTAssertEqual(viewModel.state, .completed)
        XCTAssertEqual(viewModel.collectorSessionID, "collector-session-1")
        XCTAssertEqual(viewModel.backendSessionID, "collector-session-1")
    }

    func test_failure_state_visible() async {
        let coordinator = MockCoordinator()
        coordinator.startError = TestError(message: "connect failed")
        let viewModel = NightSessionViewModel(coordinator: coordinator)

        await viewModel.onPrimaryButtonTapped()

        guard case .failed(let message) = viewModel.state else {
            return XCTFail("Expected failure state")
        }
        XCTAssertEqual(message, "connect failed")
    }
}
