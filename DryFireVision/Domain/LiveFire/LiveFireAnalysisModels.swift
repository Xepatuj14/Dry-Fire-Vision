import Foundation

public struct RecoveryTrajectorySample: Codable, Equatable, Sendable {
    public let timeSinceEventSeconds: Double
    public let displacement: Double

    public init(timeSinceEventSeconds: Double, displacement: Double) {
        self.timeSinceEventSeconds = timeSinceEventSeconds
        self.displacement = displacement
    }
}

public struct LiveEventAnalysis: Equatable, Identifiable, Sendable {
    public let id: UUID
    public let sessionID: UUID
    public let sequenceIndex: Int
    public let timestampSeconds: Double
    public let eventConfidence: ConfidenceStatus
    public let status: LiveEventStatus
    public let interEventDurationSeconds: Double?
    public let headDisplacement: MovementMetricResult
    public let upperBodyDisplacement: MovementMetricResult
    public let peakVisibleDisplacement: MovementMetricResult
    public let recoveryDuration: MovementMetricResult
    public let recoverySimilarity: Double?
    public let recoveryConfidence: ConfidenceStatus
    public let isOutlier: Bool
    public let poseAssetID: UUID?
    public let reason: LiveEventReason
    public let trajectory: [RecoveryTrajectorySample]

    public init(
        id: UUID = UUID(),
        sessionID: UUID,
        sequenceIndex: Int,
        timestampSeconds: Double,
        eventConfidence: ConfidenceStatus,
        status: LiveEventStatus,
        interEventDurationSeconds: Double? = nil,
        headDisplacement: MovementMetricResult,
        upperBodyDisplacement: MovementMetricResult,
        peakVisibleDisplacement: MovementMetricResult,
        recoveryDuration: MovementMetricResult,
        recoverySimilarity: Double? = nil,
        recoveryConfidence: ConfidenceStatus,
        isOutlier: Bool = false,
        poseAssetID: UUID? = nil,
        reason: LiveEventReason,
        trajectory: [RecoveryTrajectorySample] = []
    ) {
        self.id = id
        self.sessionID = sessionID
        self.sequenceIndex = sequenceIndex
        self.timestampSeconds = timestampSeconds
        self.eventConfidence = eventConfidence
        self.status = status
        self.interEventDurationSeconds = interEventDurationSeconds
        self.headDisplacement = headDisplacement
        self.upperBodyDisplacement = upperBodyDisplacement
        self.peakVisibleDisplacement = peakVisibleDisplacement
        self.recoveryDuration = recoveryDuration
        self.recoverySimilarity = recoverySimilarity
        self.recoveryConfidence = recoveryConfidence
        self.isOutlier = isOutlier
        self.poseAssetID = poseAssetID
        self.reason = reason
        self.trajectory = trajectory
    }
}

public struct LiveFireSessionAnalysis: Equatable, Sendable {
    public let sessionID: UUID
    public let createdAt: Date
    public let analysisVersion: String
    public let analysisConfigurationVersion: String
    public let events: [LiveEventAnalysis]
    public let recoveryPoseAssetsByEventID: [UUID: PoseAssetPayload]
    public let acceptedEventCount: Int
    public let averageRecoveryDurationSeconds: Double?
    public let recoveryConsistency: SessionConsistencyResult
    public let overallConfidence: ConfidenceStatus

    public init(
        sessionID: UUID,
        createdAt: Date = Date(timeIntervalSince1970: 0),
        analysisVersion: String = VersionCatalog.current.analysisVersion,
        analysisConfigurationVersion: String = VersionCatalog.current.analysisConfigurationVersion,
        events: [LiveEventAnalysis],
        recoveryPoseAssetsByEventID: [UUID: PoseAssetPayload] = [:],
        recoveryConsistency: SessionConsistencyResult,
        overallConfidence: ConfidenceStatus
    ) {
        self.sessionID = sessionID
        self.createdAt = createdAt
        self.analysisVersion = analysisVersion
        self.analysisConfigurationVersion = analysisConfigurationVersion
        self.events = events
        self.recoveryPoseAssetsByEventID = recoveryPoseAssetsByEventID
        self.acceptedEventCount = events.filter { $0.status == .accepted }.count
        let durations = events.compactMap { event in
            event.status == .accepted && event.recoveryDuration.availability == .available ? event.recoveryDuration.value : nil
        }
        self.averageRecoveryDurationSeconds = durations.isEmpty ? nil : durations.reduce(0, +) / Double(durations.count)
        self.recoveryConsistency = recoveryConsistency
        self.overallConfidence = overallConfidence
    }
}
