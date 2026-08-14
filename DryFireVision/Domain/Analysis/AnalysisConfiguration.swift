import Foundation

public struct AnalysisConfiguration: Codable, Equatable, Sendable {
    public let version: String
    public let lowConfidenceThreshold: Double
    public let mediumConfidenceThreshold: Double
    public let highConfidenceThreshold: Double
    public let maximumInterpolationGapSeconds: Double
    public let smoothingAlpha: Double
    public let readyStabilityThreshold: Double
    public let readyStabilityWindowSeconds: Double
    public let movementStartThreshold: Double
    public let movementStartConfirmationWindowSeconds: Double
    public let activeMovementThreshold: Double
    public let settleThreshold: Double
    public let settleWindowSeconds: Double
    public let resetBaselineDistanceThreshold: Double
    public let resetStabilityWindowSeconds: Double
    public let plausibleRepDurationMinimumSeconds: Double
    public let plausibleRepDurationMaximumSeconds: Double
    public let minimumSignalJointCount: Int
    public let maximumPoseSignalGapSeconds: Double
    public let minimumHeadMetricCoverage: Double
    public let minimumShoulderMetricCoverage: Double
    public let minimumWristMetricCoverage: Double
    public let maximumMetricGapSeconds: Double
    public let nearZeroPathLengthThreshold: Double
    public let primaryWristJointID: PoseJointID?
    public let comparisonPhaseSampleCount: Int
    public let minimumComparisonJointCoverage: Double
    public let minimumUsableComparisonJoints: Int
    public let comparisonJointWeights: [PoseJointID: Double]
    public let similarityErrorScale: Double
    public let minimumRepsForSessionConsistency: Int
    public let minimumRepsForOutlierDetection: Int
    public let outlierMedianAbsoluteDeviationMultiplier: Double
    public let zeroDispersionThreshold: Double
    public let liveFireAudioImpulseThreshold: Double
    public let liveFireAudioHighConfidenceThreshold: Double
    public let liveFireAudioMediumConfidenceThreshold: Double
    public let liveFireMinimumEventSpacingSeconds: Double
    public let liveFireDebounceWindowSeconds: Double
    public let liveFirePreEventWindowSeconds: Double
    public let liveFirePostEventWindowSeconds: Double
    public let liveFireRecoveryTolerance: Double
    public let liveFireRecoveryDwellSeconds: Double
    public let liveFireMinimumPoseCoverage: Double
    public let liveFireMaximumPoseGapSeconds: Double

    public init(
        version: String = VersionCatalog.current.analysisConfigurationVersion,
        lowConfidenceThreshold: Double = 0.25,
        mediumConfidenceThreshold: Double = 0.45,
        highConfidenceThreshold: Double = 0.70,
        maximumInterpolationGapSeconds: Double = 0.12,
        smoothingAlpha: Double = 0.60,
        readyStabilityThreshold: Double = 0.18,
        readyStabilityWindowSeconds: Double = 0.30,
        movementStartThreshold: Double = 0.55,
        movementStartConfirmationWindowSeconds: Double = 0.10,
        activeMovementThreshold: Double = 0.22,
        settleThreshold: Double = 0.18,
        settleWindowSeconds: Double = 0.20,
        resetBaselineDistanceThreshold: Double = 0.20,
        resetStabilityWindowSeconds: Double = 0.20,
        plausibleRepDurationMinimumSeconds: Double = 0.35,
        plausibleRepDurationMaximumSeconds: Double = 8.00,
        minimumSignalJointCount: Int = 3,
        maximumPoseSignalGapSeconds: Double = 0.35,
        minimumHeadMetricCoverage: Double = 0.80,
        minimumShoulderMetricCoverage: Double = 0.80,
        minimumWristMetricCoverage: Double = 0.80,
        maximumMetricGapSeconds: Double = 0.12,
        nearZeroPathLengthThreshold: Double = 0.000_001,
        primaryWristJointID: PoseJointID? = nil,
        comparisonPhaseSampleCount: Int = 21,
        minimumComparisonJointCoverage: Double = 0.80,
        minimumUsableComparisonJoints: Int = 3,
        comparisonJointWeights: [PoseJointID: Double] = [
            .nose: 0.25,
            .leftShoulder: 0.25,
            .rightShoulder: 0.25,
            .leftWrist: 0.25,
            .rightWrist: 0.25
        ],
        similarityErrorScale: Double = 1.0,
        minimumRepsForSessionConsistency: Int = 3,
        minimumRepsForOutlierDetection: Int = 5,
        outlierMedianAbsoluteDeviationMultiplier: Double = 3.5,
        zeroDispersionThreshold: Double = 0.000_001,
        liveFireAudioImpulseThreshold: Double = 0.65,
        liveFireAudioHighConfidenceThreshold: Double = 0.90,
        liveFireAudioMediumConfidenceThreshold: Double = 0.75,
        liveFireMinimumEventSpacingSeconds: Double = 0.18,
        liveFireDebounceWindowSeconds: Double = 0.08,
        liveFirePreEventWindowSeconds: Double = 0.20,
        liveFirePostEventWindowSeconds: Double = 1.20,
        liveFireRecoveryTolerance: Double = 0.035,
        liveFireRecoveryDwellSeconds: Double = 0.12,
        liveFireMinimumPoseCoverage: Double = 0.70,
        liveFireMaximumPoseGapSeconds: Double = 0.18
    ) {
        self.version = version
        self.lowConfidenceThreshold = lowConfidenceThreshold
        self.mediumConfidenceThreshold = mediumConfidenceThreshold
        self.highConfidenceThreshold = highConfidenceThreshold
        self.maximumInterpolationGapSeconds = maximumInterpolationGapSeconds
        self.smoothingAlpha = smoothingAlpha
        self.readyStabilityThreshold = readyStabilityThreshold
        self.readyStabilityWindowSeconds = readyStabilityWindowSeconds
        self.movementStartThreshold = movementStartThreshold
        self.movementStartConfirmationWindowSeconds = movementStartConfirmationWindowSeconds
        self.activeMovementThreshold = activeMovementThreshold
        self.settleThreshold = settleThreshold
        self.settleWindowSeconds = settleWindowSeconds
        self.resetBaselineDistanceThreshold = resetBaselineDistanceThreshold
        self.resetStabilityWindowSeconds = resetStabilityWindowSeconds
        self.plausibleRepDurationMinimumSeconds = plausibleRepDurationMinimumSeconds
        self.plausibleRepDurationMaximumSeconds = plausibleRepDurationMaximumSeconds
        self.minimumSignalJointCount = minimumSignalJointCount
        self.maximumPoseSignalGapSeconds = maximumPoseSignalGapSeconds
        self.minimumHeadMetricCoverage = minimumHeadMetricCoverage
        self.minimumShoulderMetricCoverage = minimumShoulderMetricCoverage
        self.minimumWristMetricCoverage = minimumWristMetricCoverage
        self.maximumMetricGapSeconds = maximumMetricGapSeconds
        self.nearZeroPathLengthThreshold = nearZeroPathLengthThreshold
        self.primaryWristJointID = primaryWristJointID
        self.comparisonPhaseSampleCount = comparisonPhaseSampleCount
        self.minimumComparisonJointCoverage = minimumComparisonJointCoverage
        self.minimumUsableComparisonJoints = minimumUsableComparisonJoints
        self.comparisonJointWeights = comparisonJointWeights
        self.similarityErrorScale = similarityErrorScale
        self.minimumRepsForSessionConsistency = minimumRepsForSessionConsistency
        self.minimumRepsForOutlierDetection = minimumRepsForOutlierDetection
        self.outlierMedianAbsoluteDeviationMultiplier = outlierMedianAbsoluteDeviationMultiplier
        self.zeroDispersionThreshold = zeroDispersionThreshold
        self.liveFireAudioImpulseThreshold = liveFireAudioImpulseThreshold
        self.liveFireAudioHighConfidenceThreshold = liveFireAudioHighConfidenceThreshold
        self.liveFireAudioMediumConfidenceThreshold = liveFireAudioMediumConfidenceThreshold
        self.liveFireMinimumEventSpacingSeconds = liveFireMinimumEventSpacingSeconds
        self.liveFireDebounceWindowSeconds = liveFireDebounceWindowSeconds
        self.liveFirePreEventWindowSeconds = liveFirePreEventWindowSeconds
        self.liveFirePostEventWindowSeconds = liveFirePostEventWindowSeconds
        self.liveFireRecoveryTolerance = liveFireRecoveryTolerance
        self.liveFireRecoveryDwellSeconds = liveFireRecoveryDwellSeconds
        self.liveFireMinimumPoseCoverage = liveFireMinimumPoseCoverage
        self.liveFireMaximumPoseGapSeconds = liveFireMaximumPoseGapSeconds
    }

    public static let provisionalSegmentationV1 = AnalysisConfiguration()
}
