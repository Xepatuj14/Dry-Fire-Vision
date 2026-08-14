import DryFireVisionCore
import XCTest

@MainActor
final class LiveFireBetaViewModelTests: XCTestCase {
    func testAcknowledgementChecksMicrophoneWithoutRequestingImmediately() async {
        let permission = RecordingMicrophonePermission(status: .notDetermined, requestedStatus: .authorized)
        let viewModel = LiveFireBetaViewModel(microphonePermissionProvider: permission)

        viewModel.acknowledgeAndContinue()
        for _ in 0..<10 where viewModel.state == .introduction {
            await Task.yield()
        }

        XCTAssertEqual(viewModel.state, .microphonePermissionRequired)
        XCTAssertEqual(await permission.requestCount, 0)
    }

    func testDeniedMicrophoneShowsRecoveryState() async {
        let permission = RecordingMicrophonePermission(status: .denied, requestedStatus: .denied)
        let viewModel = LiveFireBetaViewModel(microphonePermissionProvider: permission)

        await viewModel.refreshPermission()

        XCTAssertEqual(viewModel.state, .permissionDenied)
    }
}

private actor RecordingMicrophonePermission: MicrophonePermissionProviding {
    private var status: MicrophoneAuthorizationStatus
    private let requestedStatus: MicrophoneAuthorizationStatus
    private(set) var requestCount = 0

    init(status: MicrophoneAuthorizationStatus, requestedStatus: MicrophoneAuthorizationStatus) {
        self.status = status
        self.requestedStatus = requestedStatus
    }

    func authorizationStatus() async -> MicrophoneAuthorizationStatus {
        status
    }

    func requestAuthorization() async -> MicrophoneAuthorizationStatus {
        requestCount += 1
        status = requestedStatus
        return requestedStatus
    }
}
