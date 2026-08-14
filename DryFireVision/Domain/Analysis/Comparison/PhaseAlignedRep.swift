import Foundation

public struct PhaseAlignedRep: Codable, Equatable, Sendable {
    public let repID: UUID
    public let sequenceIndex: Int
    public let sourceRecordingID: UUID
    public let startTimestampSeconds: Double
    public let completeTimestampSeconds: Double
    public let phaseGrid: [Double]
    public let trajectories: [PoseJointID: [PhaseSample?]]
    public let analysisVersion: String
    public let configurationVersion: String

    public init(
        repID: UUID,
        sequenceIndex: Int,
        sourceRecordingID: UUID,
        startTimestampSeconds: Double,
        completeTimestampSeconds: Double,
        phaseGrid: [Double],
        trajectories: [PoseJointID: [PhaseSample?]],
        analysisVersion: String = VersionCatalog.current.analysisVersion,
        configurationVersion: String
    ) {
        self.repID = repID
        self.sequenceIndex = sequenceIndex
        self.sourceRecordingID = sourceRecordingID
        self.startTimestampSeconds = startTimestampSeconds
        self.completeTimestampSeconds = completeTimestampSeconds
        self.phaseGrid = phaseGrid
        self.trajectories = trajectories
        self.analysisVersion = analysisVersion
        self.configurationVersion = configurationVersion
    }
}
