import Combine
import Foundation

@MainActor
public final class CameraFlowViewModel: ObservableObject {
    @Published public private(set) var state: CameraFlowState = .startingCamera
    @Published public private(set) var previewSession: CameraPreviewSession?
    @Published public private(set) var calibrationState: CalibrationReadinessState = .startingCamera
    @Published public private(set) var latestPoseFrame: PoseFrame?
    @Published public private(set) var recordingState: PoseRecordingState = .awaitingCalibration
    @Published public private(set) var selectedCameraPosition: CameraPosition = .front

    private let cameraCaptureProvider: any CameraCaptureProviding
    private let applicationSettingsOpener: any ApplicationSettingsOpening
    private let poseDetector: any PoseDetecting
    private let poseRecordingService: PoseRecordingService
    private let countdownProvider: any CountdownProviding
    private let calibrationConfiguration: CalibrationConfiguration
    private let recordingConfiguration: PoseRecordingConfiguration
    private var calibrationEvaluator: CalibrationEvaluator
    private var poseAnalysisCadence: PoseAnalysisCadence
    private var lifecycleObservationTask: Task<Void, Never>?
    private var poseObservationTask: Task<Void, Never>?
    private var countdownTask: Task<Void, Never>?
    private var activeCalibrationResult: CalibrationResult?
    private var recordingStartTimestampSeconds: Double?

    public init(
        cameraCaptureProvider: any CameraCaptureProviding,
        applicationSettingsOpener: any ApplicationSettingsOpening,
        poseDetector: any PoseDetecting,
        poseRecordingService: PoseRecordingService,
        countdownProvider: any CountdownProviding,
        calibrationConfiguration: CalibrationConfiguration = CalibrationConfiguration(),
        poseAnalysisCadence: PoseAnalysisCadence = PoseAnalysisCadence(),
        recordingConfiguration: PoseRecordingConfiguration = PoseRecordingConfiguration()
    ) {
        self.cameraCaptureProvider = cameraCaptureProvider
        self.applicationSettingsOpener = applicationSettingsOpener
        self.poseDetector = poseDetector
        self.poseRecordingService = poseRecordingService
        self.countdownProvider = countdownProvider
        self.calibrationConfiguration = calibrationConfiguration
        self.recordingConfiguration = recordingConfiguration
        self.calibrationEvaluator = CalibrationEvaluator(configuration: calibrationConfiguration)
        self.poseAnalysisCadence = poseAnalysisCadence
    }

    public var canSwitchCamera: Bool {
        guard state == .active else {
            return false
        }

        guard case .awaitingCalibration = recordingState else {
            return false
        }

        if case .ready = calibrationState {
            return false
        }

        return true
    }

    public func enter() async {
        observeLifecycleEventsIfNeeded()
        await routeForCurrentAuthorization()
    }

    public func continueFromPermissionInterstitial() async {
        let authorizationStatus = await cameraCaptureProvider.requestAuthorization()
        await route(authorizationStatus: authorizationStatus)
    }

    public func retryCameraStart() async {
        await startCamera()
    }

    public func switchCamera() async {
        guard canSwitchCamera else {
            return
        }

        selectedCameraPosition = selectedCameraPosition.toggled
        await restartCameraForSelectedPosition()
    }

    public func openSettings() async {
        await applicationSettingsOpener.openApplicationSettings()
    }

    public func refreshAfterForeground() async {
        await routeForCurrentAuthorization()
    }

    public func leave() async {
        lifecycleObservationTask?.cancel()
        lifecycleObservationTask = nil
        poseObservationTask?.cancel()
        poseObservationTask = nil
        countdownTask?.cancel()
        countdownTask = nil
        await poseRecordingService.cancel()
        await cameraCaptureProvider.stopPreview()
        previewSession = nil
        latestPoseFrame = nil
        calibrationState = .startingCamera
        recordingState = .awaitingCalibration
        activeCalibrationResult = nil
        recordingStartTimestampSeconds = nil
        selectedCameraPosition = .front
        resetCalibrationEvaluation()
    }

    public func startRecordingCountdown() {
        guard case .ready(let calibrationResult) = calibrationState else {
            recordingState = .awaitingCalibration
            return
        }

        activeCalibrationResult = calibrationResult
        countdownTask?.cancel()
        recordingState = .countdown(remainingSeconds: recordingConfiguration.countdownSeconds)

        countdownTask = Task { [weak self] in
            guard let self else {
                return
            }

            for await remaining in countdownProvider.countdown(from: recordingConfiguration.countdownSeconds) {
                await MainActor.run {
                    self.recordingState = .countdown(remainingSeconds: remaining)
                }
            }

            await self.beginRecordingAfterCountdown()
        }
    }

    public func cancelRecording() async {
        countdownTask?.cancel()
        countdownTask = nil
        await poseRecordingService.cancel()
        recordingState = .cancelled
    }

    public func stopRecording() async {
        recordingState = .completing

        do {
            let recording = try await poseRecordingService.finish()
            recordingState = .completed(recording)
        } catch let error as PoseRecordingError {
            recordingState = .failed(error)
        } catch {
            recordingState = .failed(.notRecording)
        }
    }

    private func observeLifecycleEventsIfNeeded() {
        guard lifecycleObservationTask == nil else {
            return
        }

        let events = cameraCaptureProvider.lifecycleEvents()
        lifecycleObservationTask = Task { [weak self] in
            for await event in events {
                await self?.handleLifecycleEvent(event)
            }
        }
    }

    private func handleLifecycleEvent(_ event: CameraCaptureLifecycleEvent) async {
        switch event {
        case .interrupted:
            previewSession = nil
            state = .interrupted
            if isRecordingOrCountdown {
                await poseRecordingService.interrupt()
                recordingState = .interrupted
            }
        case .interruptionEnded:
            await routeForCurrentAuthorization()
        case .runtimeError:
            await cameraCaptureProvider.stopPreview()
            previewSession = nil
            state = .failed(.runtimeFailure)
            if isRecordingOrCountdown {
                await poseRecordingService.interrupt()
                recordingState = .interrupted
            }
        }
    }

    private func routeForCurrentAuthorization() async {
        let authorizationStatus = await cameraCaptureProvider.authorizationStatus()
        await route(authorizationStatus: authorizationStatus)
    }

    private func route(authorizationStatus: CameraAuthorizationStatus) async {
        switch authorizationStatus {
        case .notDetermined:
            previewSession = nil
            state = .permissionRequired
        case .authorized:
            await startCamera()
        case .denied:
            await leave()
            state = .permissionRecovery(.denied)
        case .restricted:
            await leave()
            state = .permissionRecovery(.restricted)
        }
    }

    private func startCamera() async {
        guard state != .active || previewSession == nil else {
            return
        }

        resetCalibrationForCameraStart()

        do {
            previewSession = try await cameraCaptureProvider.startPreview(position: selectedCameraPosition)
            state = .active
            observePoseFramesIfNeeded()
        } catch let error as CameraCaptureError {
            state = .failed(mapFailureReason(error))
        } catch {
            state = .failed(.runtimeFailure)
        }
    }

    private func restartCameraForSelectedPosition() async {
        poseObservationTask?.cancel()
        poseObservationTask = nil
        await cameraCaptureProvider.stopPreview()
        resetCalibrationForCameraStart()

        do {
            previewSession = try await cameraCaptureProvider.startPreview(position: selectedCameraPosition)
            state = .active
            observePoseFramesIfNeeded()
        } catch let error as CameraCaptureError {
            state = .failed(mapFailureReason(error))
        } catch {
            state = .failed(.runtimeFailure)
        }
    }

    private func resetCalibrationForCameraStart() {
        previewSession = nil
        latestPoseFrame = nil
        calibrationState = .startingCamera
        recordingState = .awaitingCalibration
        activeCalibrationResult = nil
        recordingStartTimestampSeconds = nil
        state = .startingCamera
        resetCalibrationEvaluation()
    }

    private func resetCalibrationEvaluation() {
        calibrationEvaluator = CalibrationEvaluator(configuration: calibrationConfiguration)
        poseAnalysisCadence = PoseAnalysisCadence(minimumIntervalSeconds: poseAnalysisCadence.minimumIntervalSeconds)
    }

    private func observePoseFramesIfNeeded() {
        guard poseObservationTask == nil else {
            return
        }

        let frames = cameraCaptureProvider.frames()
        poseObservationTask = Task { [weak self] in
            for await frame in frames {
                await self?.processCameraFrame(frame)
            }
        }
    }

    private func processCameraFrame(_ frame: CameraFrame) async {
        guard poseAnalysisCadence.shouldAnalyze(timestampSeconds: frame.timestampSeconds) else {
            return
        }

        do {
            let result = try await poseDetector.detectPoses(in: frame)
            let evaluation = calibrationEvaluator.evaluate(poseFrames: result.poseFrames)
            latestPoseFrame = evaluation.selectedPoseFrame
            calibrationState = evaluation.state
            if case .ready(let calibrationResult) = evaluation.state {
                activeCalibrationResult = calibrationResult
                if case .awaitingCalibration = recordingState {
                    recordingState = .idle
                }
            } else if case .idle = recordingState {
                recordingState = .awaitingCalibration
            }

            if case .recording = recordingState, result.poseFrames.count == 1, let frame = result.poseFrames.first {
                await acceptRecordingFrame(frame)
            }
        } catch let error as PoseDetectionError {
            latestPoseFrame = nil
            calibrationState = .failed(mapPoseDetectionError(error))
        } catch {
            latestPoseFrame = nil
            calibrationState = .failed(.poseDetectionFailed)
        }
    }

    private var isRecordingOrCountdown: Bool {
        switch recordingState {
        case .countdown, .recording:
            return true
        default:
            return false
        }
    }

    private func beginRecordingAfterCountdown() async {
        guard let calibrationResult = activeCalibrationResult, let startTimestampSeconds = latestPoseFrame?.timestampSeconds else {
            recordingState = .failed(.missingCalibration)
            return
        }

        do {
            try await poseRecordingService.start(
                calibrationResult: calibrationResult,
                startTimestampSeconds: startTimestampSeconds,
                metadata: PoseRecordingMetadata(
                    cameraPosition: selectedCameraPosition.rawValue,
                    nominalCaptureFPS: nil
                )
            )
            recordingStartTimestampSeconds = startTimestampSeconds
            recordingState = .recording(elapsedSeconds: 0)
        } catch let error as PoseRecordingError {
            recordingState = .failed(error)
        } catch {
            recordingState = .failed(.alreadyRecording)
        }
    }

    private func acceptRecordingFrame(_ frame: PoseFrame) async {
        do {
            try await poseRecordingService.accept(frame)
            recordingState = .recording(elapsedSeconds: max(0, frame.timestampSeconds - (recordingStartTimestampSeconds ?? frame.timestampSeconds)))
        } catch let error as PoseRecordingError {
            recordingState = .failed(error)
        } catch {
            recordingState = .failed(.notRecording)
        }
    }

    private func mapPoseDetectionError(_ error: PoseDetectionError) -> CalibrationFailureReason {
        switch error {
        case .unsupportedPoseRequest:
            return .unsupportedPoseRequest
        case .visionRequestFailed:
            return .poseDetectionFailed
        case .invalidObservation:
            return .invalidObservation
        }
    }

    private func mapFailureReason(_ error: CameraCaptureError) -> CameraFailureReason {
        switch error {
        case .deviceUnavailable:
            return .deviceUnavailable
        case .cannotAddInput:
            return .cannotAddInput
        case .permissionDenied:
            return .runtimeFailure
        case .permissionRestricted:
            return .runtimeFailure
        case .sessionInterrupted:
            return .runtimeFailure
        case .runtimeFailure:
            return .runtimeFailure
        }
    }
}
