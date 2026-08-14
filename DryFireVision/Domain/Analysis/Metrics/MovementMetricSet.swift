import Foundation

public struct MovementMetricSet: Codable, Equatable, Sendable {
    public let duration: MovementMetricResult
    public let headDisplacement: MovementMetricResult
    public let shoulderDisplacement: MovementMetricResult
    public let primaryWristPathLength: MovementMetricResult
    public let wristPathDirectness: MovementMetricResult
    public let aggregateConfidence: ConfidenceStatus
    public let analysisVersion: String
    public let configurationVersion: String

    public init(
        duration: MovementMetricResult,
        headDisplacement: MovementMetricResult,
        shoulderDisplacement: MovementMetricResult,
        primaryWristPathLength: MovementMetricResult,
        wristPathDirectness: MovementMetricResult,
        analysisVersion: String = VersionCatalog.current.analysisVersion,
        configurationVersion: String
    ) {
        self.duration = duration
        self.headDisplacement = headDisplacement
        self.shoulderDisplacement = shoulderDisplacement
        self.primaryWristPathLength = primaryWristPathLength
        self.wristPathDirectness = wristPathDirectness
        self.aggregateConfidence = Self.deriveAggregateConfidence([
            duration,
            headDisplacement,
            shoulderDisplacement,
            primaryWristPathLength,
            wristPathDirectness
        ])
        self.analysisVersion = analysisVersion
        self.configurationVersion = configurationVersion
    }

    private static func deriveAggregateConfidence(_ metrics: [MovementMetricResult]) -> ConfidenceStatus {
        let available = metrics.filter { $0.availability == .available }
        guard !available.isEmpty else {
            return .low
        }
        if available.contains(where: { $0.confidence == .low }) {
            return .low
        }
        if available.contains(where: { $0.confidence == .medium }) || available.count < metrics.count {
            return .medium
        }
        return .high
    }
}
