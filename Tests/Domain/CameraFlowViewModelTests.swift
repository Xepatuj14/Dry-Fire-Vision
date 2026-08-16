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
        XCTAssertEqual(viewModel.selectedCameraPosition, .front)
        XCTAssertEqual(camera.startedPositions, [.front])
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

    func testMovementAfterReadyDoesNotResetCalibrationOrChangeBaseline() async {
        let camera = FakeCameraCaptureProvider(authorizationStatus: .authorized)
        let poseDetector = FakePoseDetector()
        let viewModel = CameraFlowViewModel(
            cameraCaptureProvider: camera,
            applicationSettingsOpener: FakeSettingsOpener(),
            poseDetector: poseDetector,
            poseRecordingService: PoseRecordingService(),
            countdownProvider: ImmediateCountdownProvider(),
            calibrationConfiguration: CalibrationConfiguration(stabilityWindowSeconds: 0.2, stabilityMovementThreshold: 0.02, minimumBaselineSamples: 3),
            poseAnalysisCadence: PoseAnalysisCadence(minimumIntervalSeconds: 0)
        )

        await viewModel.enter()
        for frame in SyntheticPoseFixtures.stablePoseSequence(sampleCount: 3, interval: 0.1) {
            poseDetector.nextResult = PoseDetectionResult(poseFrames: [frame])
            camera.emitFrame(CameraFrame(timestampSeconds: frame.timestampSeconds))
            await Task.yield()
        }

        guard case .ready(let originalCalibration) = viewModel.calibrationState else {
            return XCTFail("Expected ready calibration before movement, got \(viewModel.calibrationState)")
        }

        poseDetector.nextResult = PoseDetectionResult(poseFrames: [offsetPose(timestampSeconds: 0.3, xOffset: 0.08)])
        camera.emitFrame(CameraFrame(timestampSeconds: 0.3))
        await Task.yield()

        XCTAssertEqual(viewModel.recordingState, .idle)
        guard case .ready(let latchedCalibration) = viewModel.calibrationState else {
            return XCTFail("Expected ready calibration to stay latched after movement, got \(viewModel.calibrationState)")
        }
        XCTAssertEqual(latchedCalibration, originalCalibration)
    }

    func testSwitchingCameraSelectsRearAndResetsCalibration() async {
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
        poseDetector.nextResult = PoseDetectionResult(poseFrames: [SyntheticPoseFixtures.centeredFullBodyPerson(timestampSeconds: 0)])
        camera.emitFrame(CameraFrame(timestampSeconds: 0))
        await Task.yield()

        if case .holdStill = viewModel.calibrationState {
            XCTAssertTrue(viewModel.canSwitchCamera)
        } else {
            XCTFail("Expected in-progress calibration before camera switch, got \(viewModel.calibrationState)")
        }

        await viewModel.switchCamera()

        XCTAssertEqual(viewModel.selectedCameraPosition, .rear)
        XCTAssertEqual(camera.startedPositions, [.front, .rear])
        XCTAssertEqual(camera.stopPreviewCallCount, 1)
        XCTAssertEqual(viewModel.calibrationState, .startingCamera)
        XCTAssertNil(viewModel.latestPoseFrame)
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
        XCTAssertFalse(viewModel.canSwitchCamera)
        await viewModel.switchCamera()
        XCTAssertEqual(viewModel.selectedCameraPosition, .front)
        for frame in stableReturnFrames(start: 0.3, count: 4) {
            poseDetector.nextResult = PoseDetectionResult(poseFrames: [frame])
            camera.emitFrame(CameraFrame(timestampSeconds: frame.timestampSeconds))
            await Task.yield()
        }
        countdown.finish()
        await Task.yield()

        if case .recording = viewModel.recordingState {
            XCTAssertTrue(true)
        } else {
            XCTFail("Expected recording state, got \(viewModel.recordingState)")
        }
    }

    func testCountdownWaitsForReturnToLatchedStartPositionWithoutErasingCalibration() async {
        let camera = FakeCameraCaptureProvider(authorizationStatus: .authorized)
        let poseDetector = FakePoseDetector()
        let countdown = ManualCountdownProvider()
        let viewModel = CameraFlowViewModel(
            cameraCaptureProvider: camera,
            applicationSettingsOpener: FakeSettingsOpener(),
            poseDetector: poseDetector,
            poseRecordingService: PoseRecordingService(),
            countdownProvider: countdown,
            calibrationConfiguration: CalibrationConfiguration(stabilityWindowSeconds: 0.2, stabilityMovementThreshold: 0.02, minimumBaselineSamples: 3),
            poseAnalysisCadence: PoseAnalysisCadence(minimumIntervalSeconds: 0),
            recordingConfiguration: PoseRecordingConfiguration(countdownSeconds: 3)
        )

        await viewModel.enter()
        for frame in SyntheticPoseFixtures.stablePoseSequence(sampleCount: 3, interval: 0.1) {
            poseDetector.nextResult = PoseDetectionResult(poseFrames: [frame])
            camera.emitFrame(CameraFrame(timestampSeconds: frame.timestampSeconds))
            await Task.yield()
        }

        guard case .ready(let originalCalibration) = viewModel.calibrationState else {
            return XCTFail("Expected ready calibration before countdown, got \(viewModel.calibrationState)")
        }

        poseDetector.nextResult = PoseDetectionResult(poseFrames: [offsetPose(timestampSeconds: 0.3, xOffset: 0.08)])
        camera.emitFrame(CameraFrame(timestampSeconds: 0.3))
        await Task.yield()

        viewModel.startRecordingCountdown()
        countdown.finish()
        await Task.yield()

        XCTAssertEqual(viewModel.recordingState, .waitingForStartPosition)
        guard case .ready(let latchedCalibration) = viewModel.calibrationState else {
            return XCTFail("Expected calibration to remain ready while waiting for start position, got \(viewModel.calibrationState)")
        }
        XCTAssertEqual(latchedCalibration, originalCalibration)

        for frame in stableReturnFrames(start: 0.4, count: 4, xOffset: 0.002) {
            poseDetector.nextResult = PoseDetectionResult(poseFrames: [frame])
            camera.emitFrame(CameraFrame(timestampSeconds: frame.timestampSeconds))
            await Task.yield()
        }

        if case .recording = viewModel.recordingState {
            XCTAssertTrue(true)
        } else {
            XCTFail("Expected recording to begin after returning to the latched start position, got \(viewModel.recordingState)")
        }
    }

    func testNeverReturningToStartPositionDoesNotBeginRecordingOrClearCalibration() async {
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
            recordingReadinessConfiguration: .fixtureTestConfiguration,
            recordingConfiguration: PoseRecordingConfiguration(countdownSeconds: 3)
        )

        await viewModel.enter()
        for frame in SyntheticPoseFixtures.stablePoseSequence(sampleCount: 3, interval: 0.1) {
            poseDetector.nextResult = PoseDetectionResult(poseFrames: [frame])
            camera.emitFrame(CameraFrame(timestampSeconds: frame.timestampSeconds))
            await Task.yield()
        }

        guard case .ready(let originalCalibration) = viewModel.calibrationState else {
            return XCTFail("Expected ready calibration before countdown, got \(viewModel.calibrationState)")
        }

        viewModel.startRecordingCountdown()
        countdown.finish()
        await Task.yield()

        for frame in stableReturnFrames(start: 0.3, count: 5, xOffset: 0.12) {
            poseDetector.nextResult = PoseDetectionResult(poseFrames: [frame])
            camera.emitFrame(CameraFrame(timestampSeconds: frame.timestampSeconds))
            await Task.yield()
        }

        XCTAssertEqual(viewModel.recordingState, .waitingForStartPosition)
        guard case .ready(let latchedCalibration) = viewModel.calibrationState else {
            return XCTFail("Expected calibration to remain ready while user is away, got \(viewModel.calibrationState)")
        }
        XCTAssertEqual(latchedCalibration, originalCalibration)
    }

    func testSelectedCameraPositionIsStoredOnCompletedRecording() async {
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
        await viewModel.switchCamera()

        for frame in SyntheticPoseFixtures.stablePoseSequence(sampleCount: 3, interval: 0.1) {
            poseDetector.nextResult = PoseDetectionResult(poseFrames: [frame])
            camera.emitFrame(CameraFrame(timestampSeconds: frame.timestampSeconds))
            await Task.yield()
        }

        viewModel.startRecordingCountdown()
        for frame in stableReturnFrames(start: 0.3, count: 4) {
            poseDetector.nextResult = PoseDetectionResult(poseFrames: [frame])
            camera.emitFrame(CameraFrame(timestampSeconds: frame.timestampSeconds))
            await Task.yield()
        }
        countdown.finish()
        await Task.yield()

        for frame in [
            SyntheticPoseFixtures.centeredFullBodyPerson(timestampSeconds: 0.7),
            SyntheticPoseFixtures.centeredFullBodyPerson(timestampSeconds: 0.8)
        ] {
            poseDetector.nextResult = PoseDetectionResult(poseFrames: [frame])
            camera.emitFrame(CameraFrame(timestampSeconds: frame.timestampSeconds))
            await Task.yield()
        }

        await viewModel.stopRecording()

        if case .completed(let recording) = viewModel.recordingState {
            XCTAssertEqual(recording.metadata.cameraPosition, CameraPosition.rear.rawValue)
        } else {
            XCTFail("Expected completed recording, got \(viewModel.recordingState)")
        }
    }

    func testStartButtonExcursionIsNotRecordedAsFirstRepAndFirstRealRepStartsNormally() async throws {
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
            recordingReadinessConfiguration: .fixtureTestConfiguration,
            recordingConfiguration: PoseRecordingConfiguration(countdownSeconds: 3)
        )

        await viewModel.enter()
        for frame in SyntheticPoseFixtures.stablePoseSequence(sampleCount: 3, interval: 0.1) {
            poseDetector.nextResult = PoseDetectionResult(poseFrames: [frame])
            camera.emitFrame(CameraFrame(timestampSeconds: frame.timestampSeconds))
            await Task.yield()
        }

        poseDetector.nextResult = PoseDetectionResult(poseFrames: [offsetPose(timestampSeconds: 0.3, xOffset: 0.12)])
        camera.emitFrame(CameraFrame(timestampSeconds: 0.3))
        await Task.yield()

        viewModel.startRecordingCountdown()
        countdown.finish()
        await Task.yield()

        XCTAssertEqual(viewModel.recordingState, .waitingForStartPosition)

        for frame in stableReturnFrames(start: 0.4, count: 5) {
            poseDetector.nextResult = PoseDetectionResult(poseFrames: [frame])
            camera.emitFrame(CameraFrame(timestampSeconds: frame.timestampSeconds))
            await Task.yield()
        }

        guard case .recording = viewModel.recordingState else {
            return XCTFail("Expected recording to arm after stable return, got \(viewModel.recordingState)")
        }

        for frame in firstRepFrames(start: 0.95) {
            poseDetector.nextResult = PoseDetectionResult(poseFrames: [frame])
            camera.emitFrame(CameraFrame(timestampSeconds: frame.timestampSeconds))
            await Task.yield()
        }

        await viewModel.stopRecording()

        guard case .completed(let recording) = viewModel.recordingState else {
            return XCTFail("Expected completed recording, got \(viewModel.recordingState)")
        }

        let result = try RepSegmenter(configuration: .fixtureTestConfiguration).segment(recording)
        XCTAssertEqual(result.segments.count, 1)
        XCTAssertTrue(result.diagnostics.containsTransition(from: .waitingForStable, to: .ready))
        XCTAssertTrue(result.diagnostics.containsTransition(from: .ready, to: .moving))
        XCTAssertEqual(result.segments.first?.startTimestampSeconds ?? -1, 0.55, accuracy: SegmentationGoldenFixtures.timestampTolerance)
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

private func offsetPose(timestampSeconds: Double, xOffset: Double) -> PoseFrame {
    let base = SyntheticPoseFixtures.centeredFullBodyPerson(timestampSeconds: timestampSeconds)
    let shifted = Dictionary(uniqueKeysWithValues: base.joints.map { jointID, sample in
        (
            jointID,
            JointSample(
                jointID: jointID,
                x: sample.x + xOffset,
                y: sample.y,
                confidence: sample.confidence
            )
        )
    })

    return PoseFrame(timestampSeconds: timestampSeconds, joints: shifted)
}

private func stableReturnFrames(start: Double, count: Int, xOffset: Double = 0) -> [PoseFrame] {
    (0..<count).map { index in
        offsetPose(timestampSeconds: start + Double(index) * 0.1, xOffset: xOffset)
    }
}

private func firstRepFrames(start: Double) -> [PoseFrame] {
    let offsets = [0.04, 0.08, 0.12, 0.12, 0.12, 0.12, 0.12, 0.12, 0.08, 0.04, 0.0]
    return offsets.enumerated().map { index, offset in
        offsetPose(timestampSeconds: start + Double(index) * 0.05, xOffset: offset)
    }
}

private extension Array where Element == SegmentationDiagnostic {
    func containsTransition(from: MovementAnalysisState, to: MovementAnalysisState) -> Bool {
        contains { diagnostic in
            diagnostic.event == .stateTransition &&
                diagnostic.fromState == from &&
                diagnostic.toState == to
        }
    }
}

private final class FakeCameraCaptureProvider: CameraCaptureProviding, @unchecked Sendable {
    var currentAuthorizationStatus: CameraAuthorizationStatus
    var requestAuthorizationResult: CameraAuthorizationStatus
    var startError: CameraCaptureError?
    private(set) var requestAuthorizationCallCount = 0
    private(set) var startPreviewCallCount = 0
    private(set) var stopPreviewCallCount = 0
    private(set) var activeLogicalSessionCount = 0
    private(set) var startedPositions: [CameraPosition] = []
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

    func startPreview(position: CameraPosition) async throws -> CameraPreviewSession {
        startPreviewCallCount += 1
        startedPositions.append(position)

        if let startError {
            throw startError
        }

        activeLogicalSessionCount = 1
        return CameraPreviewSession(cameraPosition: position)
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
