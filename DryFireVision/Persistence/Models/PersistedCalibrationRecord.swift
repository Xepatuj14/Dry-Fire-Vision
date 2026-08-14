import Foundation
import SwiftData

@Model
public final class PersistedCalibrationRecord {
    public var id: UUID
    public var sessionID: UUID
    public var createdAt: Date
    public var baselineDuration: Double
    public var normalizationScale: Double
    public var normalizationSource: String
    public var baselinePoseAssetID: UUID?
    public var requiredJointCoverage: Double
    public var averageJointConfidence: Double
    public var calibrationConfidence: String
    public var blockingFailureReason: String?

    public var session: PersistedTrainingSession?

    public init(
        id: UUID,
        sessionID: UUID,
        createdAt: Date,
        baselineDuration: Double,
        normalizationScale: Double,
        normalizationSource: String,
        baselinePoseAssetID: UUID?,
        requiredJointCoverage: Double,
        averageJointConfidence: Double,
        calibrationConfidence: String,
        blockingFailureReason: String?
    ) {
        self.id = id
        self.sessionID = sessionID
        self.createdAt = createdAt
        self.baselineDuration = baselineDuration
        self.normalizationScale = normalizationScale
        self.normalizationSource = normalizationSource
        self.baselinePoseAssetID = baselinePoseAssetID
        self.requiredJointCoverage = requiredJointCoverage
        self.averageJointConfidence = averageJointConfidence
        self.calibrationConfidence = calibrationConfidence
        self.blockingFailureReason = blockingFailureReason
    }
}
