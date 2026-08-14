import Foundation

public struct RepComparisonResult: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let repAID: UUID
    public let repBID: UUID
    public let availability: ComparisonAvailability
    public let reason: ComparisonUnavailableReason
    public let jointResults: [JointComparisonResult]
    public let aggregateError: Double?
    public let internalSimilarity: Double?
    public let confidence: ConfidenceStatus
    public let usableJointCoverage: Double
    public let analysisVersion: String
    public let configurationVersion: String

    public init(
        id: UUID,
        repAID: UUID,
        repBID: UUID,
        availability: ComparisonAvailability,
        reason: ComparisonUnavailableReason,
        jointResults: [JointComparisonResult],
        aggregateError: Double?,
        internalSimilarity: Double?,
        confidence: ConfidenceStatus,
        usableJointCoverage: Double,
        analysisVersion: String = VersionCatalog.current.analysisVersion,
        configurationVersion: String
    ) {
        self.id = id
        self.repAID = repAID
        self.repBID = repBID
        self.availability = availability
        self.reason = reason
        self.jointResults = jointResults
        self.aggregateError = aggregateError?.isFinite == true ? aggregateError : nil
        self.internalSimilarity = internalSimilarity?.isFinite == true ? internalSimilarity : nil
        self.confidence = confidence
        self.usableJointCoverage = usableJointCoverage
        self.analysisVersion = analysisVersion
        self.configurationVersion = configurationVersion
    }
}
