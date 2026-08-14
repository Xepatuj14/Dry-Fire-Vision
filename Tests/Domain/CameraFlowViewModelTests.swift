import DryFireVisionTestFixtures
import XCTest
@testable import DryFireVisionCore

@MainActor
final class CameraFlowViewModelTests: XCTestCase {
    func testNotDeterminedAuthorizationShowsInterstitial() async {
        let camera = FakeCameraCaptureProvider(authorizationStatus: .notDetermined)
        let viewModel = makeViewModel(camera: camera)

        await viewModel.enter()

        XCTAssertEqual(viewModel.state, .permissionRequired)
        XCTAssertEqual(camera.startPreviewCallCount, 0)
    }

    func testAuthorizedAuthorizationStartsCamera() async {
        let camera = FakeCameraCaptureProvider(authorizationStatus: .authorized)
        let viewModel = makeViewModel(camera: camera)

        await viewModel.enter()

        XCTAssertEqual(viewModel.state, .active)
        XCTAssertEqual(camera.startPreviewCallCount, 1)
    }

    func testDeniedAuthorizationShowsRecovery() async {
        let camera = FakeCameraCaptureProvider(authorizationStatus: .denied)
        let viewModel = makeViewModel(camera: camera)

        await viewModel.enter()

        XCTAssertEqual(viewModel.state, .permissionRecovery(.denied))
        XCTAssertEqual(camera.startPreviewCallCount, 0)
    }

    func testRestrictedAuthorizationShowsRecovery() async {
        let camera = FakeCameraCaptureProvider(authorizationStatus: .restricted)
        let viewModel = makeViewModel(camera: camera)

        await viewModel.enter()

        XCTAssertEqual(viewModel.state, .permissionRecovery(.restricted))
        XCTAssertEqual(camera.startPreviewCallCount, 0)
    }

    func testPermissionGrantFromInterstitialStartsCamera() async {
        let camera = FakeCameraCaptureProvider(authorizationStatus: .notDetermined)
        camera.requestAuthorizationResult = .authorized
        let viewModel = makeViewModel(camera: camera)

        await viewModel.enter()
        await viewModel.continueFromPermissionInterstitial()

        XCTAssertEqual(viewModel.state, .active)
        XCTAssertEqual(camera.requestAuthorizationCallCount, 1)
        XCTAssertEqual(camera.startPreviewCallCount, 1)
    }

    func testPermissionDeniedFromInterstitialShowsRecovery() async {
        let camera = FakeCameraCaptureProvider(authorizationStatus: .notDetermined)
        camera.requestAuthorizationResult = .denied
        let viewModel = makeViewModel(camera: camera)

        await viewModel.enter()
        await viewModel.continueFromPermissionInterstitial()

        XCTAssertEqual(viewModel.state, .permissionRecovery(.denied))
        XCTAssertEqual(camera.requestAuthorizationCallCount, 1)
        XCTAssertEqual(camera.startPreviewCallCount, 0)
    }

    func testPermissionBecomesAuthorizedAfterReturningFromSettingsStartsCamera() async {
        let camera = FakeCameraCaptureProvider(authorizationStatus: .denied)
        let viewModel = makeViewModel(camera: camera)

        await viewModel.enter()
        camera.currentAuthorizationStatus = .authorized
        await viewModel.refreshAfterForeground()

        XCTAssertEqual(viewModel.state, .active)
        XCTAssertEqual(camera.startPreviewCallCount, 1)
    }

    func testLeavingStopsPreview() async {
        let camera = FakeCameraCaptureProvider(authorizationStatus: .authorized)
        let viewModel = makeViewModel(camera: camera)

        await viewModel.enter()
        await viewModel.leave()

        XCTAssertEqual(camera.stopPreviewCallCount, 1)
        XCTAssertNil(viewModel.previewSession)
    }

    func testRepeatedEntryUsesProviderWithoutDuplicateLogicalStartWhenAlreadyRunning() async {
        let camera = FakeCameraCaptureProvider(authorizationStatus: .authorized)
        let viewModel = makeViewModel(camera: camera)

        await viewModel.enter()
        await viewModel.enter()

        XCTAssertEqual(viewModel.state, .active)
        XCTAssertEqual(camera.startPreviewCallCount, 1)
        XCTAssertEqual(camera.activeLogicalSessionCount, 1)
    }

    func testInitializationFailureProducesFailedState() async {
        let camera = FakeCameraCaptureProvider(authorizationStatus: .authorized)
        camera.startError = .deviceUnavailable
        let viewModel = makeViewModel(camera: camera)

        await viewModel.enter()

        XCTAssertEqual(viewModel.state, .failed(.deviceUnavailable))
    }

    func testRetryAttemptsInitializationAgain() async {
        let camera = FakeCameraCaptureProvider(authorizationStatus: .authorized)
        camera.startError = .deviceUnavailable
        let viewModel = makeViewModel(camera: camera)

        await viewModel.enter()
        camera.startError = nil
        await viewModel.retryCameraStart()

        XCTAssertEqual(viewModel.state, .active)
        XCTAssertEqual(camera.startPreviewCallCount, 2)
    }

    func testInterruptionEventProducesInterruptedState() async {
        let camera = FakeCameraCaptureProvider(authorizationStatus: .authorized)
        let viewModel = makeViewModel(camera: camera)

        await viewModel.enter()
        camera.emit(.interrupted)
        await Task.yield()

        XCTAssertEqual(viewModel.state, .interrupted)
        XCTAssertNil(viewModel.previewSession)
    }

    func testRuntimeErrorEventStopsPreviewAndProducesFailedState() async {
        let camera = FakeCameraCaptureProvider(authorizationStatus: .authorized)
        let viewModel = makeViewModel(camera: camera)

        await viewModel.enter()
        camera.emit(.runtimeError)
        await Task.yield()

        XCTAssertEqual(viewModel.state, .failed(.runtimeFailure))
        XCTAssertEqual(camera.stopPreviewCallCount, 1)
        XCTAssertNil(viewModel.previewSession)
    }

    func testValidStablePoseFramesReachReadyCalibrationState() async {
        let camera = FakeCameraCaptureProvider(authorizationStatus: .authorized)
        let poseDetector = FakePoseDetector()
        let viewModel = CameraFlowViewModel(
            cameraCaptureProvider: camera,
            applicationSettingsOpener: FakeSettingsOpener(),
            poseDetector: poseDetector,
            poseRecordingService: PoseRecordingService(),
            countdownProvider: ImmediateCountdownProvider(),
            calibrationConfiguration: CalibrationConfiguration(stabilityWindowSeconds: 0.3, minimumBaselineSamples: 3),
            poseAnalysisCadence: PoseAnalysisCadence(minimumIntervalSeconds: 0)
        )

        await viewModel.enter()
        for frame in SyntheticPoseFixtures.stablePoseSequence(sampleCount: 4, interval: 0.1) {
            poseDetector.nextResult = PoseDetectionResult(poseFrames: [frame])
            camera.emitFrame(CameraFrame(timestampSeconds: frame.timestampSeconds))
            await Task.yield()
        }

        if case .ready(let result) = viewModel.calibrationState {
            XCTAssertEqual(result.normalizationScaleSource, .shoulderWidth)
        } else {
            XCTFail("Expected ready calibration state, got \(viewModel.calibrationState)")
        }
    }

    func testReadyCalibrationCanStartCountdownAndRecording() async {
        let camera = FakeCameraCaptureProvider(authorizationStatus: .authorized)
        let poseDetector = FakePoseDetector()
        let countdown = ManualCountdownProvider()
        let viewModel = CameraFlowViewModel(
            cameraCaptureProvider: camera,
            applicationSettingsOpener: FakeSettingsOpener(),
            poseDetector: poseDetector,
            poseRecordingService: PoseRecordingService(),
            countdownProvider: countdown,
            calibrationConfiguration: CalibrationConfiguration(stabilityWindowSeconds: 0.2, minimumBaselineSamples: 3),
            poseAnalysisCadence: PoseAnalysisCadence(minimumIntervalSeconds: 0),
            recordingConfiguration: PoseRecordingConfiguration(countdownSeconds: 3)
        )

        await viewModel.enter()
        for frame in SyntheticPoseFixtures.stablePoseSequence(sampleCount: 3, interval: 0.1) {
            poseDetector.nextResult = PoseDetectionResult(poseFrames: [frame])
            camera.emitFrame(CameraFrame(timestampSeconds: frame.timestampSeconds))
            await Task.yield()
        }

        viewModel.startRecordingCountdown()
        countdown.emit(3)
        await Task.yield()
        XCTAssertEqual(viewModel.recordingState, .countdown(remainingSeconds: 3))
        countdown.finish()
        await Task.yield()

        if case .recording = viewModel.recordingState {
            XCTAssertTrue(true)
        } else {
            XCTFail("Expected recording state, got \(viewModel.recordingState)")
        }
    }

    func testCountdownCancellationDoesNotCompleteRecording() async {
        let camera = FakeCameraCaptureProvider(authorizationStatus: .authorized)
        let viewModel = makeViewModel(camera: camera)

        await viewModel.cancelRecording()

        XCTAssertEqual(viewModel.recordingState, .cancelled)
    }
}

private func makeViewModel(camera: FakeCameraCaptureProvider) -> CameraFlowViewModel {
    CameraFlowViewModel(
        cameraCaptureProvider: camera,
        applicationSettingsOpener: FakeSettingsOpener(),
        poseDetector: FakePoseDetector(),
        poseRecordingService: PoseRecordingService(),
        countdownProvider: ImmediateCountdownProvider()
    )
}

private final class FakeCameraCaptureProvider: CameraCaptureProviding, @unchecked Sendable {
    var currentAuthorizationStatus: CameraAuthorizationStatus
    var requestAuthorizationResult: CameraAuthorizationStatus
    var startError: CameraCaptureError?
    private(set) var requestAuthorizationCallCount = 0
    private(set) var startPreviewCallCount = 0
    private(set) var stopPreviewCallCount = 0
    private(set) var activeLogicalSessionCount = 0
    private var lifecycleContinuation: AsyncStream<CameraCaptureLifecycleEvent>.Continuation?
    private var frameContinuation: AsyncStream<CameraFrame>.Continuation?

    init(authorizationStatus: CameraAuthorizationStatus) {
        self.currentAuthorizationStatus = authorizationStatus
        self.requestAuthorizationResult = authorizationStatus
    }

    func authorizationStatus() async -> CameraAuthorizationStatus {
        currentAuthorizationStatus
    }

    func requestAuthorization() async -> CameraAuthorizationStatus {
        requestAuthorizationCallCount += 1
        currentAuthorizationStatus = requestAuthorizationResult
        return requestAuthorizationResult
    }

    func startPreview() async throws -> CameraPreviewSession {
        startPreviewCallCount += 1

        if let startError {
            throw startError
        }

        activeLogicalSessionCount = 1
        return CameraPreviewSession()
    }

    func stopPreview() async {
        stopPreviewCallCount += 1
        activeLogicalSessionCount = 0
    }

    func lifecycleEvents() -> AsyncStream<CameraCaptureLifecycleEvent> {
        AsyncStream { continuation in
            lifecycleContinuation = continuation
        }
    }

    func emit(_ event: CameraCaptureLifecycleEvent) {
        lifecycleContinuation?.yield(event)
    }

    func frames() -> AsyncStream<CameraFrame> {
        AsyncStream { continuation in
            frameContinuation = continuation
        }
    }

    func emitFrame(_ frame: CameraFrame) {
        frameContinuation?.yield(frame)
    }
}

private struct FakeSettingsOpener: ApplicationSettingsOpening {
    func openApplicationSettings() async {}
}

private final class FakePoseDetector: PoseDetecting, @unchecked Sendable {
    var nextResult = PoseDetectionResult(poseFrames: [])

    func detectPoses(in frame: CameraFrame) async throws -> PoseDetectionResult {
        nextResult
    }
}

private struct ImmediateCountdownProvider: CountdownProviding {
    func countdown(from seconds: Int) -> AsyncStream<Int> {
        AsyncStream { continuation in
            continuation.finish()
        }
    }
}

private final class ManualCountdownProvider: CountdownProviding, @unchecked Sendable {
    private var continuation: AsyncStream<Int>.Continuation?

    func countdown(from seconds: Int) -> AsyncStream<Int> {
        AsyncStream { continuation in
            self.continuation = continuation
        }
    }

    func emit(_ remainingSeconds: Int) {
        continuation?.yield(remainingSeconds)
    }

    func finish() {
        continuation?.finish()
    }
}
