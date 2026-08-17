import Foundation

public enum ComparisonAvailability: String, Codable, Equatable, Sendable {
    case available
    case unavailable
}

public enum ComparisonUnavailableReason: String, Codable, Equatable, Sendable {
    case none
    case incompatibleAnalysisVersion
    case incompatibleCoordinateConvention
    case incompatibleJointSet
    case invalidRep
    case invalidNormalizationScale
    case missingPrimaryWristConfiguration
    case primaryWristUnavailable
    case insufficientJointCoverage
    case insufficientUsableJoints
    case insufficientEligibleReps
    case zeroDispersion
    case nonFiniteInput
}
