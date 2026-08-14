import Foundation

public actor PoseRecordingService {
    private var activeRecordingID: UUID?
    private var startTimestampSeconds: Double?
    private var lastRelativeTimestampSeconds: Double?
    private var calibrationResult: CalibrationResult?
    private var metadata = PoseRecordingMetadata()
    private var acceptedFrames: [PoseFrame] = []
    private var rejectedFrameCount = 0
    private var isRecording = false

    public init() {}

    public func start(
        id: UUID = UUID(),
        calibrationResult: CalibrationResult,
        startTimestampSeconds: Double,
        metadata: PoseRecordingMetadata = PoseRecordingMetadata()
    ) throws {
        guard !isRecording else {
            throw PoseRecordingError.alreadyRecording
        }

        activeRecordingID = id
        self.startTimestampSeconds = startTimestampSeconds
        lastRelativeTimestampSeconds = nil
        self.calibrationResult = calibrationResult
        self.metadata = metadata
        acceptedFrames = []
        rejectedFrameCount = 0
        isRecording = true
    }

    public func accept(_ frame: PoseFrame) throws {
        guard isRecording, let startTimestampSeconds else {
            throw PoseRecordingError.notRecording
        }

        let relativeTimestampSeconds = frame.timestampSeconds - startTimestampSeconds
        if let lastRelativeTimestampSeconds, relativeTimestampSeconds <= lastRelativeTimestampSeconds {
            rejectedFrameCount += 1
            throw PoseRecordingError.nonMonotonicTimestamp(
                previousSeconds: lastRelativeTimestampSeconds,
                nextSeconds: relativeTimestampSeconds
            )
        }

        guard relativeTimestampSeconds >= 0 else {
            rejectedFrameCount += 1
            throw PoseRecordingError.nonMonotonicTimestamp(
                previousSeconds: 0,
                nextSeconds: relativeTimestampSeconds
            )
        }

        acceptedFrames.append(
            PoseFrame(
                id: frame.id,
                timestampSeconds: relativeTimestampSeconds,
                joints: frame.joints,
                coordinateConventionVersion: frame.coordinateConventionVersion,
                jointSetVersion: frame.jointSetVersion
            )
        )
        lastRelativeTimestampSeconds = relativeTimestampSeconds
    }

    public func finish(endTimestampSeconds: Double? = nil) throws -> PoseRecording {
        guard isRecording else {
            throw PoseRecordingError.notRecording
        }

        guard let activeRecordingID, let startTimestampSeconds, let calibrationResult else {
            reset()
            throw PoseRecordingError.missingCalibration
        }

        guard let finalRelativeTimestamp = lastRelativeTimestampSeconds else {
            reset()
            throw PoseRecordingError.noAcceptedFrames
        }

        let finalEndTimestamp = endTimestampSeconds ?? startTimestampSeconds + finalRelativeTimestamp
        let durationSeconds = finalEndTimestamp - startTimestampSeconds
        let finalizedMetadata = metadata.finalized(
            durationSeconds: durationSeconds,
            acceptedPoseFrameCount: acceptedFrames.count,
            rejectedPoseFrameCount: rejectedFrameCount
        )

        let recording = PoseRecording(
            id: activeRecordingID,
            startTimestampSeconds: startTimestampSeconds,
            endTimestampSeconds: finalEndTimestamp,
            poseFrames: acceptedFrames,
            calibrationResult: calibrationResult,
            metadata: finalizedMetadata
        )

        reset()
        return recording
    }

    public func cancel() {
        reset()
    }

    public func interrupt() {
        reset()
    }

    private func reset() {
        activeRecordingID = nil
        startTimestampSeconds = nil
        lastRelativeTimestampSeconds = nil
        calibrationResult = nil
        metadata = PoseRecordingMetadata()
        acceptedFrames = []
        rejectedFrameCount = 0
        isRecording = false
    }
}
