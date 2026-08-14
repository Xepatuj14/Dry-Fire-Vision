import Foundation

public struct MovementMetricResult: Codable, Equatable, Sendable {
    public let key: MovementMetricKey
    public let value: Double?
    public let availability: MetricAvailability
    public let confidence: ConfidenceStatus
    public let reason: MetricUnavailableReason
    public let analysisVersion: String
    public let configurationVersion: String

    public init(
        key: MovementMetricKey,
        value: Double?,
        availability: MetricAvailability,
        confidence: ConfidenceStatus,
        reason: MetricUnavailableReason,
        analysisVersion: String = VersionCatalog.current.analysisVersion,
        configurationVersion: String
    ) {
        if let value, value.isFinite {
            self.value = value
        } else {
            self.value = nil
        }
        self.key = key
        self.availability = availability
        self.confidence = confidence
        self.reason = reason
        self.analysisVersion = analysisVersion
        self.configurationVersion = configurationVersion
    }

    public static func available(
        key: MovementMetricKey,
        value: Double,
        confidence: ConfidenceStatus,
        configurationVersion: String
    ) -> MovementMetricResult {
        guard value.isFinite else {
            return unavailable(
                key: key,
                confidence: .low,
                reason: .nonFiniteInput,
                configurationVersion: configurationVersion
            )
        }

        return MovementMetricResult(
            key: key,
            value: value,
            availability: .available,
            confidence: confidence,
            reason: .none,
            configurationVersion: configurationVersion
        )
    }

    public static func unavailable(
        key: MovementMetricKey,
        confidence: ConfidenceStatus = .low,
        reason: MetricUnavailableReason,
        configurationVersion: String
    ) -> MovementMetricResult {
        MovementMetricResult(
            key: key,
            value: nil,
            availability: .unavailable,
            confidence: confidence,
            reason: reason,
            configurationVersion: configurationVersion
        )
    }
}
