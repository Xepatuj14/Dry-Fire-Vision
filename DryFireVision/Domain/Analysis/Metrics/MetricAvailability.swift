import Foundation

public enum MetricAvailability: String, Codable, Equatable, Sendable {
    case available
    case unavailable
}

public enum MetricUnavailableReason: String, Codable, Equatable, Sendable {
    case none
    case insufficientJointCoverage
    case lowJointConfidence
    case invalidCalibrationScale
    case invalidSegment
    case insufficientTrajectory
    case excessivePoseGap
    case missingStartSample
    case missingEndSample
    case nonFiniteInput
    case primaryWristUnavailable
    case nearZeroPathLength
}
