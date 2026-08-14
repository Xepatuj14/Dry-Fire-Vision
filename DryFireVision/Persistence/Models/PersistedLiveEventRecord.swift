import Foundation
import SwiftData

@Model
public final class PersistedLiveEventRecord {
    public var id: UUID
    public var sessionID: UUID
    public var sequenceIndex: Int
    public var timestampSeconds: Double
    public var eventConfidence: String
    public var status: String
    public var interEventDurationSeconds: Double?
    public var headDisplacement: Double?
    public var headDisplacementAvailability: String
    public var upperBodyDisplacement: Double?
    public var upperBodyDisplacementAvailability: String
    public var peakVisibleDisplacement: Double?
    public var peakVisibleDisplacementAvailability: String
    public var recoveryDuration: Double?
    public var recoveryDurationAvailability: String
    public var recoverySimilarity: Double?
    public var recoveryConfidence: String
    public var isOutlier: Bool
    public var poseAssetID: UUID?
    public var reason: String
    public var analysisVersion: String
    public var analysisConfigurationVersion: String

    public var session: PersistedTrainingSession?

    public init(
        id: UUID,
        sessionID: UUID,
        sequenceIndex: Int,
        timestampSeconds: Double,
        eventConfidence: String,
        status: String,
        interEventDurationSeconds: Double?,
        headDisplacement: Double?,
        headDisplacementAvailability: String,
        upperBodyDisplacement: Double?,
        upperBodyDisplacementAvailability: String,
        peakVisibleDisplacement: Double?,
        peakVisibleDisplacementAvailability: String,
        recoveryDuration: Double?,
        recoveryDurationAvailability: String,
        recoverySimilarity: Double?,
        recoveryConfidence: String,
        isOutlier: Bool,
        poseAssetID: UUID?,
        reason: String,
        analysisVersion: String,
        analysisConfigurationVersion: String
    ) {
        self.id = id
        self.sessionID = sessionID
        self.sequenceIndex = sequenceIndex
        self.timestampSeconds = timestampSeconds
        self.eventConfidence = eventConfidence
        self.status = status
        self.interEventDurationSeconds = interEventDurationSeconds
        self.headDisplacement = headDisplacement
        self.headDisplacementAvailability = headDisplacementAvailability
        self.upperBodyDisplacement = upperBodyDisplacement
        self.upperBodyDisplacementAvailability = upperBodyDisplacementAvailability
        self.peakVisibleDisplacement = peakVisibleDisplacement
        self.peakVisibleDisplacementAvailability = peakVisibleDisplacementAvailability
        self.recoveryDuration = recoveryDuration
        self.recoveryDurationAvailability = recoveryDurationAvailability
        self.recoverySimilarity = recoverySimilarity
        self.recoveryConfidence = recoveryConfidence
        self.isOutlier = isOutlier
        self.poseAssetID = poseAssetID
        self.reason = reason
        self.analysisVersion = analysisVersion
        self.analysisConfigurationVersion = analysisConfigurationVersion
    }
}
