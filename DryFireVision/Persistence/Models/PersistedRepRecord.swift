import Foundation
import SwiftData

@Model
public final class PersistedRepRecord {
    public var id: UUID
    public var sessionID: UUID
    public var sequenceIndex: Int
    public var startTimestamp: Double
    public var activeMovementEndTimestamp: Double?
    public var completeTimestamp: Double
    public var duration: Double
    public var validity: String
    public var segmentationConfidence: String
    public var segmentationReason: String
    public var aggregateMetricConfidence: String
    public var isOutlier: Bool
    public var outlierReason: String?
    public var similarityToRepresentative: Double?
    public var poseAssetID: UUID?
    public var sourceRecordingID: UUID

    public var durationAvailability: String
    public var durationConfidence: String
    public var durationReason: String

    public var headDisplacement: Double?
    public var headDisplacementAvailability: String
    public var headDisplacementConfidence: String
    public var headDisplacementReason: String

    public var shoulderDisplacement: Double?
    public var shoulderDisplacementAvailability: String
    public var shoulderDisplacementConfidence: String
    public var shoulderDisplacementReason: String

    public var wristPathLength: Double?
    public var wristPathLengthAvailability: String
    public var wristPathLengthConfidence: String
    public var wristPathLengthReason: String

    public var wristPathDirectness: Double?
    public var wristPathDirectnessAvailability: String
    public var wristPathDirectnessConfidence: String
    public var wristPathDirectnessReason: String

    public var analysisVersion: String
    public var analysisConfigurationVersion: String

    public var session: PersistedTrainingSession?

    public init(
        id: UUID,
        sessionID: UUID,
        sequenceIndex: Int,
        startTimestamp: Double,
        activeMovementEndTimestamp: Double?,
        completeTimestamp: Double,
        duration: Double,
        validity: String,
        segmentationConfidence: String,
        segmentationReason: String,
        aggregateMetricConfidence: String,
        isOutlier: Bool,
        outlierReason: String?,
        similarityToRepresentative: Double?,
        poseAssetID: UUID?,
        sourceRecordingID: UUID,
        durationAvailability: String,
        durationConfidence: String,
        durationReason: String,
        headDisplacement: Double?,
        headDisplacementAvailability: String,
        headDisplacementConfidence: String,
        headDisplacementReason: String,
        shoulderDisplacement: Double?,
        shoulderDisplacementAvailability: String,
        shoulderDisplacementConfidence: String,
        shoulderDisplacementReason: String,
        wristPathLength: Double?,
        wristPathLengthAvailability: String,
        wristPathLengthConfidence: String,
        wristPathLengthReason: String,
        wristPathDirectness: Double?,
        wristPathDirectnessAvailability: String,
        wristPathDirectnessConfidence: String,
        wristPathDirectnessReason: String,
        analysisVersion: String,
        analysisConfigurationVersion: String
    ) {
        self.id = id
        self.sessionID = sessionID
        self.sequenceIndex = sequenceIndex
        self.startTimestamp = startTimestamp
        self.activeMovementEndTimestamp = activeMovementEndTimestamp
        self.completeTimestamp = completeTimestamp
        self.duration = duration
        self.validity = validity
        self.segmentationConfidence = segmentationConfidence
        self.segmentationReason = segmentationReason
        self.aggregateMetricConfidence = aggregateMetricConfidence
        self.isOutlier = isOutlier
        self.outlierReason = outlierReason
        self.similarityToRepresentative = similarityToRepresentative
        self.poseAssetID = poseAssetID
        self.sourceRecordingID = sourceRecordingID
        self.durationAvailability = durationAvailability
        self.durationConfidence = durationConfidence
        self.durationReason = durationReason
        self.headDisplacement = headDisplacement
        self.headDisplacementAvailability = headDisplacementAvailability
        self.headDisplacementConfidence = headDisplacementConfidence
        self.headDisplacementReason = headDisplacementReason
        self.shoulderDisplacement = shoulderDisplacement
        self.shoulderDisplacementAvailability = shoulderDisplacementAvailability
        self.shoulderDisplacementConfidence = shoulderDisplacementConfidence
        self.shoulderDisplacementReason = shoulderDisplacementReason
        self.wristPathLength = wristPathLength
        self.wristPathLengthAvailability = wristPathLengthAvailability
        self.wristPathLengthConfidence = wristPathLengthConfidence
        self.wristPathLengthReason = wristPathLengthReason
        self.wristPathDirectness = wristPathDirectness
        self.wristPathDirectnessAvailability = wristPathDirectnessAvailability
        self.wristPathDirectnessConfidence = wristPathDirectnessConfidence
        self.wristPathDirectnessReason = wristPathDirectnessReason
        self.analysisVersion = analysisVersion
        self.analysisConfigurationVersion = analysisConfigurationVersion
    }
}
