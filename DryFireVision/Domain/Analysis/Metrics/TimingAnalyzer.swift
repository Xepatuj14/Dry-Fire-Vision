import Foundation

public struct TimingAnalyzer: Sendable {
    public let configuration: AnalysisConfiguration

    public init(configuration: AnalysisConfiguration) {
        self.configuration = configuration
    }

    public func totalRepDuration(for segment: RepSegment) -> MovementMetricResult {
        guard segment.validity == .valid else {
            return .unavailable(
                key: .totalRepDuration,
                reason: .invalidSegment,
                configurationVersion: configuration.version
            )
        }

        let duration = segment.completeTimestampSeconds - segment.startTimestampSeconds
        guard duration.isFinite, duration >= 0 else {
            return .unavailable(
                key: .totalRepDuration,
                reason: .nonFiniteInput,
                configurationVersion: configuration.version
            )
        }

        return .available(
            key: .totalRepDuration,
            value: duration,
            confidence: segment.confidenceStatus,
            configurationVersion: configuration.version
        )
    }
}
