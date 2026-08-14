import Foundation

public enum NormalizationScaleSource: String, Codable, Equatable, Sendable {
    case shoulderWidth
}

public struct BaselinePose: Codable, Equatable, Sendable {
    public let joints: [PoseJointID: JointSample]
    public let durationSeconds: Double

    public init(joints: [PoseJointID: JointSample], durationSeconds: Double) {
        self.joints = joints
        self.durationSeconds = durationSeconds
    }
}

public struct CalibrationQuality: Codable, Equatable, Sendable {
    public let requiredJointCoverage: Double
    public let averageConfidence: Double
    public let confidenceStatus: ConfidenceStatus

    public init(requiredJointCoverage: Double, averageConfidence: Double, confidenceStatus: ConfidenceStatus) {
        self.requiredJointCoverage = requiredJointCoverage
        self.averageConfidence = averageConfidence
        self.confidenceStatus = confidenceStatus
    }
}

public struct CalibrationResult: Codable, Equatable, Sendable {
    public let baselinePose: BaselinePose
    public let normalizationScale: Double
    public let normalizationScaleSource: NormalizationScaleSource
    public let quality: CalibrationQuality
    public let coordinateConventionVersion: String
    public let jointSetVersion: String

    public init(
        baselinePose: BaselinePose,
        normalizationScale: Double,
        normalizationScaleSource: NormalizationScaleSource,
        quality: CalibrationQuality,
        coordinateConventionVersion: String = VersionCatalog.current.coordinateConventionVersion,
        jointSetVersion: String = VersionCatalog.current.jointSetVersion
    ) {
        self.baselinePose = baselinePose
        self.normalizationScale = normalizationScale
        self.normalizationScaleSource = normalizationScaleSource
        self.quality = quality
        self.coordinateConventionVersion = coordinateConventionVersion
        self.jointSetVersion = jointSetVersion
    }
}
