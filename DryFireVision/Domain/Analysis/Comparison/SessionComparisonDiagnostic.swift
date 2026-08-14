import Foundation

public struct SessionComparisonDiagnostic: Codable, Equatable, Sendable {
    public let eligibleRepCount: Int
    public let medoidAggregateDistances: [UUID: Double]
    public let consistencyInputSimilarities: [Double]
    public let outlierCenterDistance: Double?
    public let outlierDispersion: Double?
    public let outlierThresholdDistance: Double?
    public let excludedRepReasons: [UUID: ComparisonUnavailableReason]
    public let analysisVersion: String
    public let configurationVersion: String

    public init(
        eligibleRepCount: Int,
        medoidAggregateDistances: [UUID: Double],
        consistencyInputSimilarities: [Double],
        outlierCenterDistance: Double?,
        outlierDispersion: Double?,
        outlierThresholdDistance: Double?,
        excludedRepReasons: [UUID: ComparisonUnavailableReason],
        analysisVersion: String = VersionCatalog.current.analysisVersion,
        configurationVersion: String
    ) {
        self.eligibleRepCount = eligibleRepCount
        self.medoidAggregateDistances = medoidAggregateDistances
        self.consistencyInputSimilarities = consistencyInputSimilarities
        self.outlierCenterDistance = outlierCenterDistance
        self.outlierDispersion = outlierDispersion
        self.outlierThresholdDistance = outlierThresholdDistance
        self.excludedRepReasons = excludedRepReasons
        self.analysisVersion = analysisVersion
        self.configurationVersion = configurationVersion
    }
}
