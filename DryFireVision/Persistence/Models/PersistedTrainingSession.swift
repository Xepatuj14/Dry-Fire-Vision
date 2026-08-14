import Foundation
import SwiftData

@Model
public final class PersistedTrainingSession {
    @Attribute(.unique) public var id: UUID
    public var mode: String
    public var status: String
    public var createdAt: Date
    public var startedAt: Date?
    public var endedAt: Date?
    public var targetRepCount: Int
    public var validRepCount: Int
    public var degradedRepCount: Int
    public var invalidRepCount: Int
    public var actualSegmentedRepCount: Int
    public var cameraPerspective: String
    public var cameraPosition: String?
    public var captureOrientation: String
    public var nominalCaptureFPS: Double?
    public var analysisCadenceFPS: Double?
    public var deviceModelIdentifier: String?
    public var osVersion: String?
    public var persistenceSchemaVersion: Int
    public var analysisVersion: String
    public var analysisConfigurationVersion: String
    public var overallConfidence: String
    public var movementConsistency: Double?
    public var movementConsistencyAvailability: String
    public var movementConsistencyConfidence: String
    public var movementConsistencyReason: String
    public var averageRepDuration: Double?
    public var representativeRepID: UUID?
    public var fastestRepID: UUID?
    public var videoRetentionState: String
    public var analysisReasonsJSON: String
    public var durationAggregation: String
    public var durationEligibleRepCount: Int

    @Relationship(deleteRule: .cascade, inverse: \PersistedRepRecord.session)
    public var reps: [PersistedRepRecord]

    @Relationship(deleteRule: .cascade, inverse: \PersistedCalibrationRecord.session)
    public var calibrationRecords: [PersistedCalibrationRecord]

    @Relationship(deleteRule: .cascade, inverse: \PersistedPoseAssetRecord.session)
    public var poseAssets: [PersistedPoseAssetRecord]

    @Relationship(deleteRule: .cascade, inverse: \PersistedMediaAssetReference.session)
    public var mediaAssets: [PersistedMediaAssetReference]

    @Relationship(deleteRule: .cascade, inverse: \PersistedLiveEventRecord.session)
    public var liveEvents: [PersistedLiveEventRecord]

    public init(
        id: UUID,
        mode: String,
        status: String,
        createdAt: Date,
        startedAt: Date?,
        endedAt: Date?,
        targetRepCount: Int,
        validRepCount: Int,
        degradedRepCount: Int,
        invalidRepCount: Int,
        actualSegmentedRepCount: Int,
        cameraPerspective: String,
        cameraPosition: String?,
        captureOrientation: String,
        nominalCaptureFPS: Double?,
        analysisCadenceFPS: Double?,
        deviceModelIdentifier: String?,
        osVersion: String?,
        persistenceSchemaVersion: Int,
        analysisVersion: String,
        analysisConfigurationVersion: String,
        overallConfidence: String,
        movementConsistency: Double?,
        movementConsistencyAvailability: String,
        movementConsistencyConfidence: String,
        movementConsistencyReason: String,
        averageRepDuration: Double?,
        representativeRepID: UUID?,
        fastestRepID: UUID?,
        videoRetentionState: String,
        analysisReasonsJSON: String,
        durationAggregation: String,
        durationEligibleRepCount: Int
    ) {
        self.id = id
        self.mode = mode
        self.status = status
        self.createdAt = createdAt
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.targetRepCount = targetRepCount
        self.validRepCount = validRepCount
        self.degradedRepCount = degradedRepCount
        self.invalidRepCount = invalidRepCount
        self.actualSegmentedRepCount = actualSegmentedRepCount
        self.cameraPerspective = cameraPerspective
        self.cameraPosition = cameraPosition
        self.captureOrientation = captureOrientation
        self.nominalCaptureFPS = nominalCaptureFPS
        self.analysisCadenceFPS = analysisCadenceFPS
        self.deviceModelIdentifier = deviceModelIdentifier
        self.osVersion = osVersion
        self.persistenceSchemaVersion = persistenceSchemaVersion
        self.analysisVersion = analysisVersion
        self.analysisConfigurationVersion = analysisConfigurationVersion
        self.overallConfidence = overallConfidence
        self.movementConsistency = movementConsistency
        self.movementConsistencyAvailability = movementConsistencyAvailability
        self.movementConsistencyConfidence = movementConsistencyConfidence
        self.movementConsistencyReason = movementConsistencyReason
        self.averageRepDuration = averageRepDuration
        self.representativeRepID = representativeRepID
        self.fastestRepID = fastestRepID
        self.videoRetentionState = videoRetentionState
        self.analysisReasonsJSON = analysisReasonsJSON
        self.durationAggregation = durationAggregation
        self.durationEligibleRepCount = durationEligibleRepCount
        self.reps = []
        self.calibrationRecords = []
        self.poseAssets = []
        self.mediaAssets = []
        self.liveEvents = []
    }
}
