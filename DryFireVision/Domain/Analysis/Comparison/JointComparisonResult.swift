import Foundation

public struct JointComparisonResult: Codable, Equatable, Sendable {
    public let jointID: PoseJointID
    public let availability: ComparisonAvailability
    public let averageError: Double?
    public let coverage: Double
    public let confidence: ConfidenceStatus
    public let reason: ComparisonUnavailableReason

    public init(
        jointID: PoseJointID,
        availability: ComparisonAvailability,
        averageError: Double?,
        coverage: Double,
        confidence: ConfidenceStatus,
        reason: ComparisonUnavailableReason
    ) {
        self.jointID = jointID
        self.availability = availability
        self.averageError = averageError?.isFinite == true ? averageError : nil
        self.coverage = coverage
        self.confidence = confidence
        self.reason = reason
    }
}
