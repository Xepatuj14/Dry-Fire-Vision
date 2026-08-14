import Foundation

public struct PoseRecording: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let startTimestampSeconds: Double
    public let endTimestampSeconds: Double
    public let poseFrames: [PoseFrame]
    public let calibrationResult: CalibrationResult
    public let metadata: PoseRecordingMetadata

    public init(
        id: UUID,
        startTimestampSeconds: Double,
        endTimestampSeconds: Double,
        poseFrames: [PoseFrame],
        calibrationResult: CalibrationResult,
        metadata: PoseRecordingMetadata
    ) {
        self.id = id
        self.startTimestampSeconds = startTimestampSeconds
        self.endTimestampSeconds = endTimestampSeconds
        self.poseFrames = poseFrames
        self.calibrationResult = calibrationResult
        self.metadata = metadata
    }

    public var durationSeconds: Double {
        endTimestampSeconds - startTimestampSeconds
    }
}
