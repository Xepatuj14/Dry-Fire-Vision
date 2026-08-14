import Foundation

public struct TrajectoryAnalyzer: Sendable {
    public let configuration: AnalysisConfiguration
    public let preprocessor: MetricPosePreprocessor

    public init(configuration: AnalysisConfiguration) {
        self.configuration = configuration
        self.preprocessor = MetricPosePreprocessor(configuration: configuration)
    }

    public func primaryWristMetrics(
        samples: [PoseFrame],
        calibration: CalibrationResult
    ) -> (pathLength: MovementMetricResult, directness: MovementMetricResult, diagnostics: [MetricDiagnostic]) {
        guard let primaryWrist = configuration.primaryWristJointID else {
            let path = unavailable(.primaryWristPathLength, reason: .primaryWristUnavailable)
            let directness = unavailable(.wristPathDirectness, reason: .primaryWristUnavailable)
            return (path, directness, [
                diagnostic(key: .primaryWristPathLength, trajectory: nil, result: path, normalizationScaleValid: true),
                diagnostic(key: .wristPathDirectness, trajectory: nil, result: directness, normalizationScaleValid: true)
            ])
        }

        guard calibration.normalizationScale.isFinite, calibration.normalizationScale > 0 else {
            let path = unavailable(.primaryWristPathLength, reason: .invalidCalibrationScale)
            let directness = unavailable(.wristPathDirectness, reason: .invalidCalibrationScale)
            return (path, directness, [
                diagnostic(key: .primaryWristPathLength, trajectory: nil, result: path, normalizationScaleValid: false),
                diagnostic(key: .wristPathDirectness, trajectory: nil, result: directness, normalizationScaleValid: false)
            ])
        }

        let trajectory = preprocessor.trajectory(for: primaryWrist, samples: samples, calibration: calibration)
        guard !trajectory.hasExcessiveGap else {
            let path = unavailable(.primaryWristPathLength, confidence: .medium, reason: .excessivePoseGap)
            let directness = unavailable(.wristPathDirectness, confidence: .medium, reason: .excessivePoseGap)
            return (path, directness, [
                diagnostic(key: .primaryWristPathLength, trajectory: trajectory, result: path, normalizationScaleValid: true),
                diagnostic(key: .wristPathDirectness, trajectory: trajectory, result: directness, normalizationScaleValid: true)
            ])
        }

        guard trajectory.coverage >= configuration.minimumWristMetricCoverage else {
            let path = unavailable(.primaryWristPathLength, reason: .insufficientTrajectory)
            let directness = unavailable(.wristPathDirectness, reason: .insufficientTrajectory)
            return (path, directness, [
                diagnostic(key: .primaryWristPathLength, trajectory: trajectory, result: path, normalizationScaleValid: true),
                diagnostic(key: .wristPathDirectness, trajectory: trajectory, result: directness, normalizationScaleValid: true)
            ])
        }

        guard let pathLength = MetricMath.pathLength(trajectory.positions), pathLength.isFinite else {
            let path = unavailable(.primaryWristPathLength, reason: .nonFiniteInput)
            let directness = unavailable(.wristPathDirectness, reason: .nonFiniteInput)
            return (path, directness, [
                diagnostic(key: .primaryWristPathLength, trajectory: trajectory, result: path, normalizationScaleValid: true),
                diagnostic(key: .wristPathDirectness, trajectory: trajectory, result: directness, normalizationScaleValid: true)
            ])
        }

        let confidence = confidence(for: trajectory)
        let pathResult = MovementMetricResult.available(
            key: .primaryWristPathLength,
            value: pathLength,
            confidence: confidence,
            configurationVersion: configuration.version
        )

        guard pathLength > configuration.nearZeroPathLengthThreshold else {
            let directness = unavailable(.wristPathDirectness, confidence: confidence, reason: .nearZeroPathLength)
            return (pathResult, directness, [
                diagnostic(key: .primaryWristPathLength, trajectory: trajectory, result: pathResult, normalizationScaleValid: true),
                diagnostic(key: .wristPathDirectness, trajectory: trajectory, result: directness, normalizationScaleValid: true)
            ])
        }

        guard let start = trajectory.positions.first,
              let end = trajectory.positions.last else {
            let directness = unavailable(.wristPathDirectness, reason: .missingStartSample)
            return (pathResult, directness, [
                diagnostic(key: .primaryWristPathLength, trajectory: trajectory, result: pathResult, normalizationScaleValid: true),
                diagnostic(key: .wristPathDirectness, trajectory: trajectory, result: directness, normalizationScaleValid: true)
            ])
        }

        guard let straightLine = MetricMath.euclideanDistance(x1: start.x, y1: start.y, x2: end.x, y2: end.y) else {
            let directness = unavailable(.wristPathDirectness, reason: .nonFiniteInput)
            return (pathResult, directness, [
                diagnostic(key: .primaryWristPathLength, trajectory: trajectory, result: pathResult, normalizationScaleValid: true),
                diagnostic(key: .wristPathDirectness, trajectory: trajectory, result: directness, normalizationScaleValid: true)
            ])
        }

        let directnessValue = min(1, max(0, straightLine / pathLength))
        let directnessResult = MovementMetricResult.available(
            key: .wristPathDirectness,
            value: directnessValue,
            confidence: confidence,
            configurationVersion: configuration.version
        )

        return (pathResult, directnessResult, [
            diagnostic(key: .primaryWristPathLength, trajectory: trajectory, result: pathResult, normalizationScaleValid: true),
            diagnostic(key: .wristPathDirectness, trajectory: trajectory, result: directnessResult, normalizationScaleValid: true)
        ])
    }

    private func confidence(for trajectory: JointTrajectory) -> ConfidenceStatus {
        let average = trajectory.averageConfidence ?? 0
        if trajectory.coverage >= 0.95,
           average >= configuration.highConfidenceThreshold,
           trajectory.interpolationCount == 0 {
            return .high
        }
        if trajectory.coverage >= configuration.minimumWristMetricCoverage,
           average >= configuration.mediumConfidenceThreshold {
            return .medium
        }
        return .low
    }

    private func unavailable(
        _ key: MovementMetricKey,
        confidence: ConfidenceStatus = .low,
        reason: MetricUnavailableReason
    ) -> MovementMetricResult {
        .unavailable(
            key: key,
            confidence: confidence,
            reason: reason,
            configurationVersion: configuration.version
        )
    }

    private func diagnostic(
        key: MovementMetricKey,
        trajectory: JointTrajectory?,
        result: MovementMetricResult,
        normalizationScaleValid: Bool
    ) -> MetricDiagnostic {
        MetricDiagnostic(
            metricKey: key,
            requiredCoverage: configuration.minimumWristMetricCoverage,
            actualCoverage: trajectory?.coverage ?? 0,
            averageJointConfidence: trajectory?.averageConfidence,
            normalizationScaleValid: normalizationScaleValid,
            interpolationCount: trajectory?.interpolationCount ?? 0,
            confidence: result.confidence,
            availability: result.availability,
            reason: result.reason,
            configurationVersion: configuration.version
        )
    }
}
