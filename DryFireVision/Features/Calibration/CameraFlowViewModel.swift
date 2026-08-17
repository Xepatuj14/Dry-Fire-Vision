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
    @Published public private(set) var completedValidRepCount: Int = 0

    private let cameraCaptureProvider: any CameraCaptureProviding
    private let applicationSettingsOpener: any ApplicationSettingsOpening
    private let poseDetector: any PoseDetecting
    private let poseRecordingService: PoseRecordingService
    private let countdownProvider: any CountdownProviding
    private let calibrationConfiguration: CalibrationConfiguration
    private let recordingReadinessConfiguration: AnalysisConfiguration
    private let recordingConfiguration: PoseRecordingConfiguration
    private let sessionConfiguration: DryFireSessionConfiguration
    private var calibrationEvaluator: CalibrationEvaluator
    private var poseAnalysisCadence: PoseAnalysisCadence
    private var lifecycleObservationTask: Task<Void, Never>?
    private var poseObservationTask: Task<Void, Never>?
    private var countdownTask: Task<Void, Never>?
    private var activeCalibrationResult: CalibrationResult?
    private var recordingArmingTracker: RecordingArmingTracker?
    private var recordingStartTimestampSeconds: Double?
    private var liveRecordingFrames: [PoseFrame] = []
    private var finalRepCompletionTask: Task<Void, Never>?

    public init(
        cameraCaptureProvider: any CameraCaptureProviding,
        applicationSettingsOpener: any ApplicationSettingsOpening,
        poseDetector: any PoseDetecting,
        poseRecordingService: PoseRecordingService,
        countdownProvider: any CountdownProviding,
        calibrationConfiguration: CalibrationConfiguration = CalibrationConfiguration(),
        poseAnalysisCadence: PoseAnalysisCadence = PoseAnalysisCadence(),
        recordingReadinessConfiguration: AnalysisConfiguration = .provisionalSegmentationV1,
        recordingConfiguration: PoseRecordingConfiguration = PoseRecordingConfiguration(),
        sessionConfiguration: DryFireSessionConfiguration = DryFireSessionConfiguration()
    ) {
        self.cameraCaptureProvider = cameraCaptureProvider
        self.applicationSettingsOpener = applicationSettingsOpener
        self.poseDetector = poseDetector
        self.poseRecordingService = poseRecordingService
        self.countdownProvider = countdownProvider
        self.calibrationConfiguration = calibrationConfiguration
        self.recordingReadinessConfiguration = recordingReadinessConfiguration
        self.recordingConfiguration = recordingConfiguration
        self.sessionConfiguration = sessionConfiguration
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
        finalRepCompletionTask?.cancel()
        finalRepCompletionTask = nil
        await poseRecordingService.cancel()
        await cameraCaptureProvider.stopPreview()
        previewSession = nil
        latestPoseFrame = nil
        calibrationState = .startingCamera
        recordingState = .awaitingCalibration
        activeCalibrationResult = nil
        recordingArmingTracker = nil
        recordingStartTimestampSeconds = nil
        liveRecordingFrames = []
        completedValidRepCount = 0
        selectedCameraPosition = .front
        resetCalibrationEvaluation()
    }

    public func startRecordingCountdown() {
        guard case .ready(let calibrationResult) = calibrationState else {
            recordingState = .awaitingCalibration
            return
        }

        activeCalibrationResult = calibrationResult
        recordingArmingTracker = RecordingArmingTracker(
            calibrationResult: calibrationResult,
            calibrationConfiguration: calibrationConfiguration,
            readinessConfiguration: recordingReadinessConfiguration
        )
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
        finalRepCompletionTask?.cancel()
        finalRepCompletionTask = nil
        await poseRecordingService.cancel()
        recordingArmingTracker = nil
        liveRecordingFrames = []
        completedValidRepCount = 0
        recordingState = .cancelled
    }

    public func stopRecording() async {
        finalRepCompletionTask?.cancel()
        finalRepCompletionTask = nil
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
        recordingArmingTracker = nil
        recordingStartTimestampSeconds = nil
        liveRecordingFrames = []
        completedValidRepCount = 0
        finalRepCompletionTask?.cancel()
        finalRepCompletionTask = nil
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
            if let activeCalibrationResult {
                await handlePoseResultWithLockedCalibration(result, calibrationResult: activeCalibrationResult)
                return
            }

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

    private func handlePoseResultWithLockedCalibration(
        _ result: PoseDetectionResult,
        calibrationResult: CalibrationResult
    ) async {
        latestPoseFrame = result.poseFrames.count == 1 ? result.poseFrames.first : nil
        calibrationState = .ready(calibrationResult)

        if case .countdown = recordingState, let latestPoseFrame {
            recordingArmingTracker?.process(latestPoseFrame)
        }

        if case .finishingSession = recordingState {
            return
        }

        if case .recording = recordingState,
           result.poseFrames.count == 1,
           let frame = result.poseFrames.first {
            await acceptRecordingFrame(frame)
            return
        }

        if case .idle = recordingState {
            return
        }

        if case .waitingForStartPosition = recordingState,
           let latestPoseFrame {
            recordingArmingTracker?.process(latestPoseFrame)
            if recordingArmingTracker?.isReady == true {
                await beginRecordingFromVerifiedStartPosition(calibrationResult: calibrationResult)
            }
        }
    }

    private var isRecordingOrCountdown: Bool {
        switch recordingState {
        case .countdown, .recording, .finishingSession:
            return true
        default:
            return false
        }
    }

    private func beginRecordingAfterCountdown() async {
        guard let calibrationResult = activeCalibrationResult else {
            recordingState = .failed(.missingCalibration)
            return
        }

        guard let latestPoseFrame else {
            recordingState = .waitingForStartPosition
            return
        }

        if recordingArmingTracker?.isReady != true {
            recordingArmingTracker?.process(latestPoseFrame)
        }

        guard recordingArmingTracker?.isReady == true else {
            recordingState = .waitingForStartPosition
            return
        }

        await beginRecordingFromVerifiedStartPosition(calibrationResult: calibrationResult)
    }

    private func beginRecordingFromVerifiedStartPosition(
        calibrationResult: CalibrationResult
    ) async {
        guard let startFrames = recordingArmingTracker?.stableFramesForRecording,
              let firstFrame = startFrames.first else {
            recordingState = .waitingForStartPosition
            return
        }

        do {
            try await poseRecordingService.start(
                calibrationResult: calibrationResult,
                startTimestampSeconds: firstFrame.timestampSeconds,
                metadata: PoseRecordingMetadata(
                    cameraPosition: selectedCameraPosition.rawValue,
                    nominalCaptureFPS: nil
                )
            )
            recordingStartTimestampSeconds = firstFrame.timestampSeconds
            liveRecordingFrames = []
            for frame in startFrames {
                try await poseRecordingService.accept(frame)
                appendLiveRecordingFrame(frame)
            }
            recordingArmingTracker = nil
            completedValidRepCount = 0
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
            appendLiveRecordingFrame(frame)
            updateCompletedRepCount()
            if completedValidRepCount >= sessionConfiguration.targetRepCount {
                beginFinalRepCompletionBuffer()
                return
            }

            recordingState = .recording(elapsedSeconds: max(0, frame.timestampSeconds - (recordingStartTimestampSeconds ?? frame.timestampSeconds)))
        } catch let error as PoseRecordingError {
            recordingState = .failed(error)
        } catch {
            recordingState = .failed(.notRecording)
        }
    }

    private func completeRecording() async {
        finalRepCompletionTask = nil
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

    private func beginFinalRepCompletionBuffer() {
        guard finalRepCompletionTask == nil else {
            return
        }

        completedValidRepCount = sessionConfiguration.targetRepCount
        recordingState = .finishingSession
        let bufferSeconds = max(0, recordingConfiguration.finalRepCompletionBufferSeconds)
        finalRepCompletionTask = Task { [weak self] in
            let nanoseconds = UInt64((bufferSeconds * 1_000_000_000).rounded())
            if nanoseconds > 0 {
                try? await Task.sleep(nanoseconds: nanoseconds)
            }
            guard !Task.isCancelled else {
                return
            }

            await self?.completeRecording()
        }
    }

    private func appendLiveRecordingFrame(_ frame: PoseFrame) {
        guard let recordingStartTimestampSeconds else {
            return
        }

        let relativeTimestampSeconds = frame.timestampSeconds - recordingStartTimestampSeconds
        liveRecordingFrames.append(PoseFrame(
            id: frame.id,
            timestampSeconds: relativeTimestampSeconds,
            joints: frame.joints,
            coordinateConventionVersion: frame.coordinateConventionVersion,
            jointSetVersion: frame.jointSetVersion
        ))
    }

    private func updateCompletedRepCount() {
        guard liveRecordingFrames.count >= 2,
              let activeCalibrationResult,
              let recordingStartTimestampSeconds else {
            completedValidRepCount = 0
            return
        }

        let liveRecording = PoseRecording(
            id: UUID(),
            startTimestampSeconds: recordingStartTimestampSeconds,
            endTimestampSeconds: recordingStartTimestampSeconds + (liveRecordingFrames.last?.timestampSeconds ?? 0),
            poseFrames: liveRecordingFrames,
            calibrationResult: activeCalibrationResult,
            metadata: PoseRecordingMetadata(cameraPosition: selectedCameraPosition.rawValue)
        )

        guard let segmentation = try? RepSegmenter(configuration: sessionConfiguration.analysisConfiguration).segment(liveRecording) else {
            return
        }

        completedValidRepCount = segmentation.segments.filter { $0.validity == .valid }.count
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

private struct RecordingArmingTracker {
    private let calibrationResult: CalibrationResult
    private let calibrationConfiguration: CalibrationConfiguration
    private let readinessConfiguration: AnalysisConfiguration
    private let signalJointIDs = MovementSignalBuilder.defaultJointIDs
    private var stableStartTimestampSeconds: Double?
    private var previousFrame: PoseFrame?
    private(set) var stableFramesForRecording: [PoseFrame] = []

    init(
        calibrationResult: CalibrationResult,
        calibrationConfiguration: CalibrationConfiguration,
        readinessConfiguration: AnalysisConfiguration
    ) {
        self.calibrationResult = calibrationResult
        self.calibrationConfiguration = calibrationConfiguration
        self.readinessConfiguration = readinessConfiguration
    }

    var isReady: Bool {
        guard let stableStartTimestampSeconds,
              let latestTimestamp = stableFramesForRecording.last?.timestampSeconds else {
            return false
        }

        return latestTimestamp - stableStartTimestampSeconds >= readinessConfiguration.readyStabilityWindowSeconds
    }

    mutating func process(_ frame: PoseFrame) {
        defer {
            previousFrame = frame
        }

        guard requiredCalibrationJointsAreVisible(in: frame),
              baselineDistance(for: frame) <= readinessConfiguration.resetBaselineDistanceThreshold else {
            resetStableWindow()
            return
        }

        guard let previousFrame else {
            startStableWindow(with: frame)
            return
        }

        guard let velocity = velocity(from: previousFrame, to: frame),
              velocity <= readinessConfiguration.readyStabilityThreshold else {
            startStableWindow(with: frame)
            return
        }

        if stableStartTimestampSeconds == nil {
            stableStartTimestampSeconds = frame.timestampSeconds
            stableFramesForRecording = [frame]
        } else {
            stableFramesForRecording.append(frame)
        }
    }

    private mutating func startStableWindow(with frame: PoseFrame) {
        stableStartTimestampSeconds = frame.timestampSeconds
        stableFramesForRecording = [frame]
    }

    private mutating func resetStableWindow() {
        stableStartTimestampSeconds = nil
        stableFramesForRecording = []
    }

    private func requiredCalibrationJointsAreVisible(in frame: PoseFrame) -> Bool {
        PoseJointID.fullBodyCalibrationRequired.allSatisfy { jointID in
            guard let sample = frame.sample(for: jointID),
                  sample.confidence >= calibrationConfiguration.minimumRequiredJointConfidence else {
                return false
            }

            return true
        }
    }

    private func baselineDistance(for frame: PoseFrame) -> Double {
        let scale = max(calibrationResult.normalizationScale, 0.0001)
        let distances = signalJointIDs.compactMap { jointID -> Double? in
            guard
                let current = frame.sample(for: jointID),
                current.confidence >= readinessConfiguration.mediumConfidenceThreshold,
                let baseline = calibrationResult.baselinePose.joints[jointID],
                baseline.confidence >= readinessConfiguration.mediumConfidenceThreshold
            else {
                return nil
            }

            return hypot(current.x - baseline.x, current.y - baseline.y) / scale
        }

        guard distances.count >= readinessConfiguration.minimumSignalJointCount else {
            return .infinity
        }

        return distances.reduce(0, +) / Double(distances.count)
    }

    private func velocity(from previousFrame: PoseFrame, to frame: PoseFrame) -> Double? {
        let elapsed = frame.timestampSeconds - previousFrame.timestampSeconds
        guard elapsed > 0, elapsed <= readinessConfiguration.maximumPoseSignalGapSeconds else {
            return nil
        }

        let scale = max(calibrationResult.normalizationScale, 0.0001)
        let velocities = signalJointIDs.compactMap { jointID -> Double? in
            guard
                let previous = previousFrame.sample(for: jointID),
                previous.confidence >= readinessConfiguration.mediumConfidenceThreshold,
                let current = frame.sample(for: jointID),
                current.confidence >= readinessConfiguration.mediumConfidenceThreshold
            else {
                return nil
            }

            return (hypot(current.x - previous.x, current.y - previous.y) / scale) / elapsed
        }

        guard velocities.count >= readinessConfiguration.minimumSignalJointCount else {
            return nil
        }

        return velocities.reduce(0, +) / Double(velocities.count)
    }
}
