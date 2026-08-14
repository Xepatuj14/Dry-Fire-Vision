import Foundation

public struct MetricDiagnostic: Codable, Equatable, Sendable {
    public let metricKey: MovementMetricKey
    public let requiredCoverage: Double
    public let actualCoverage: Double
    public let averageJointConfidence: Double?
    public let normalizationScaleValid: Bool
    public let interpolationCount: Int
    public let confidence: ConfidenceStatus
    public let availability: MetricAvailability
    public let reason: MetricUnavailableReason
    public let analysisVersion: String
    public let configurationVersion: String

    public init(
        metricKey: MovementMetricKey,
        requiredCoverage: Double,
        actualCoverage: Double,
        averageJointConfidence: Double?,
        normalizationScaleValid: Bool,
        interpolationCount: Int,
        confidence: ConfidenceStatus,
        availability: MetricAvailability,
        reason: MetricUnavailableReason,
        analysisVersion: String = VersionCatalog.current.analysisVersion,
        configurationVersion: String
    ) {
        self.metricKey = metricKey
        self.requiredCoverage = requiredCoverage
        self.actualCoverage = actualCoverage
        self.averageJointConfidence = averageJointConfidence
        self.normalizationScaleValid = normalizationScaleValid
        self.interpolationCount = interpolationCount
        self.confidence = confidence
        self.availability = availability
        self.reason = reason
        self.analysisVersion = analysisVersion
        self.configurationVersion = configurationVersion
    }
}
