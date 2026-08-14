import Foundation

public struct AnalysisInput: Equatable, Sendable {
    public let sessionID: UUID
    public let mode: SessionMode
    public let recording: PoseRecording?
    public let targetRepCount: Int
    public let configuration: AnalysisConfiguration

    public init(
        sessionID: UUID,
        mode: SessionMode,
        recording: PoseRecording? = nil,
        targetRepCount: Int = 10,
        configuration: AnalysisConfiguration = .provisionalSegmentationV1
    ) {
        self.sessionID = sessionID
        self.mode = mode
        self.recording = recording
        self.targetRepCount = targetRepCount
        self.configuration = configuration
    }

    public init(
        recording: PoseRecording,
        mode: SessionMode = .dryFire,
        targetRepCount: Int = 10,
        configuration: AnalysisConfiguration = .provisionalSegmentationV1
    ) {
        self.init(
            sessionID: recording.id,
            mode: mode,
            recording: recording,
            targetRepCount: targetRepCount,
            configuration: configuration
        )
    }
}
