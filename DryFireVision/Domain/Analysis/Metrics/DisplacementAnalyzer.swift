import Foundation

public struct DisplacementAnalyzer: Sendable {
    public let configuration: AnalysisConfiguration

    public init(configuration: AnalysisConfiguration) {
        self.configuration = configuration
    }

    public func headDisplacement(
        samples: [PoseFrame],
        calibration: CalibrationResult
    ) -> (MovementMetricResult, MetricDiagnostic) {
        displacement(
            key: .headDisplacement,
            jointIDs: [.nose],
            samples: samples,
            calibration: calibration,
            requiredCoverage: configuration.minimumHeadMetricCoverage
        )
    }

    public func shoulderDisplacement(
        samples: [PoseFrame],
        calibration: CalibrationResult
    ) -> (MovementMetricResult, MetricDiagnostic) {
        let midpointFrames = samples.compactMap { frame -> NormalizedJointPosition? in
            guard let left = frame.sample(for: .leftShoulder),
                  let right = frame.sample(for: .rightShoulder),
                  left.confidence >= configuration.mediumConfidenceThreshold,
                  right.confidence >= configuration.mediumConfidenceThreshold,
                  left.x.isFinite,
                  left.y.isFinite,
                  right.x.isFinite,
                  right.y.isFinite else {
                return nil
            }
            return NormalizedJointPosition(
                timestampSeconds: frame.timestampSeconds,
                x: (left.x + right.x) / 2,
                y: (left.y + right.y) / 2,
                confidence: min(left.confidence, right.confidence)
            )
        }

        let baseline = calibration.baselinePose.joints
        guard calibration.normalizationScale.isFinite, calibration.normalizationScale > 0 else {
            return unavailableDiagnostic(
                key: .shoulderDisplacement,
                requiredCoverage: configuration.minimumShoulderMetricCoverage,
                actualCoverage: 0,
                averageConfidence: nil,
                normalizationScaleValid: false,
                reason: .invalidCalibrationScale
            )
        }
        guard let leftBaseline = baseline[.leftShoulder],
              let rightBaseline = baseline[.rightShoulder],
              leftBaseline.confidence >= configuration.mediumConfidenceThreshold,
              rightBaseline.confidence >= configuration.mediumConfidenceThreshold else {
            return unavailableDiagnostic(
                key: .shoulderDisplacement,
                requiredCoverage: configuration.minimumShoulderMetricCoverage,
                actualCoverage: 0,
                averageConfidence: nil,
                normalizationScaleValid: true,
                reason: .insufficientJointCoverage
            )
        }

        let coverage = samples.isEmpty ? 0 : Double(midpointFrames.count) / Double(samples.count)
        let averageConfidence = midpointFrames.isEmpty ? nil : midpointFrames.map(\.confidence).reduce(0, +) / Double(midpointFrames.count)
        guard coverage >= configuration.minimumShoulderMetricCoverage else {
            return unavailableDiagnostic(
                key: .shoulderDisplacement,
                requiredCoverage: configuration.minimumShoulderMetricCoverage,
                actualCoverage: coverage,
                averageConfidence: averageConfidence,
                normalizationScaleValid: true,
                reason: .insufficientJointCoverage
            )
        }

        let baselineX = (leftBaseline.x + rightBaseline.x) / 2
        let baselineY = (leftBaseline.y + rightBaseline.y) / 2
        let maxDistance = midpointFrames.compactMap {
            MetricMath.euclideanDistance(x1: baselineX, y1: baselineY, x2: $0.x, y2: $0.y)
        }.max()

        guard let maxDistance, maxDistance.isFinite else {
            return unavailableDiagnostic(
                key: .shoulderDisplacement,
                requiredCoverage: configuration.minimumShoulderMetricCoverage,
                actualCoverage: coverage,
                averageConfidence: averageConfidence,
                normalizationScaleValid: true,
                reason: .nonFiniteInput
            )
        }

        let result = MovementMetricResult.available(
            key: .shoulderDisplacement,
            value: maxDistance / calibration.normalizationScale,
            confidence: confidence(forCoverage: coverage, averageConfidence: averageConfidence),
            configurationVersion: configuration.version
        )
        return (result, diagnostic(
            key: .shoulderDisplacement,
            requiredCoverage: configuration.minimumShoulderMetricCoverage,
            actualCoverage: coverage,
            averageConfidence: averageConfidence,
            normalizationScaleValid: true,
            interpolationCount: 0,
            result: result
        ))
    }

    private func displacement(
        key: MovementMetricKey,
        jointIDs: [PoseJointID],
        samples: [PoseFrame],
        calibration: CalibrationResult,
        requiredCoverage: Double
    ) -> (MovementMetricResult, MetricDiagnostic) {
        guard calibration.normalizationScale.isFinite, calibration.normalizationScale > 0 else {
            return unavailableDiagnostic(
                key: key,
                requiredCoverage: requiredCoverage,
                actualCoverage: 0,
                averageConfidence: nil,
                normalizationScaleValid: false,
                reason: .invalidCalibrationScale
            )
        }

        guard let jointID = jointIDs.first,
              let baseline = calibration.baselinePose.joints[jointID],
              baseline.confidence >= configuration.mediumConfidenceThreshold else {
            return unavailableDiagnostic(
                key: key,
                requiredCoverage: requiredCoverage,
                actualCoverage: 0,
                averageConfidence: nil,
                normalizationScaleValid: true,
                reason: .insufficientJointCoverage
            )
        }

        let valid = samples.compactMap { frame -> JointSample? in
            guard let sample = frame.sample(for: jointID),
                  sample.confidence >= configuration.mediumConfidenceThreshold,
                  sample.x.isFinite,
                  sample.y.isFinite else {
                return nil
            }
            return sample
        }
        let coverage = samples.isEmpty ? 0 : Double(valid.count) / Double(samples.count)
        let averageConfidence = valid.isEmpty ? nil : valid.map(\.confidence).reduce(0, +) / Double(valid.count)
        guard coverage >= requiredCoverage else {
            return unavailableDiagnostic(
                key: key,
                requiredCoverage: requiredCoverage,
                actualCoverage: coverage,
                averageConfidence: averageConfidence,
                normalizationScaleValid: true,
                reason: .insufficientJointCoverage
            )
        }

        let maxDistance = valid.compactMap {
            MetricMath.euclideanDistance(x1: baseline.x, y1: baseline.y, x2: $0.x, y2: $0.y)
        }.max()

        guard let maxDistance, maxDistance.isFinite else {
            return unavailableDiagnostic(
                key: key,
                requiredCoverage: requiredCoverage,
                actualCoverage: coverage,
                averageConfidence: averageConfidence,
                normalizationScaleValid: true,
                reason: .nonFiniteInput
            )
        }

        let result = MovementMetricResult.available(
            key: key,
            value: maxDistance / calibration.normalizationScale,
            confidence: confidence(forCoverage: coverage, averageConfidence: averageConfidence),
            configurationVersion: configuration.version
        )
        return (result, diagnostic(
            key: key,
            requiredCoverage: requiredCoverage,
            actualCoverage: coverage,
            averageConfidence: averageConfidence,
            normalizationScaleValid: true,
            interpolationCount: 0,
            result: result
        ))
    }

    private func confidence(forCoverage coverage: Double, averageConfidence: Double?) -> ConfidenceStatus {
        guard let averageConfidence else {
            return .low
        }
        if coverage >= 0.95 && averageConfidence >= configuration.highConfidenceThreshold {
            return .high
        }
        if coverage >= 0.80 && averageConfidence >= configuration.mediumConfidenceThreshold {
            return .medium
        }
        return .low
    }

    private func unavailableDiagnostic(
        key: MovementMetricKey,
        requiredCoverage: Double,
        actualCoverage: Double,
        averageConfidence: Double?,
        normalizationScaleValid: Bool,
        reason: MetricUnavailableReason
    ) -> (MovementMetricResult, MetricDiagnostic) {
        let result = MovementMetricResult.unavailable(
            key: key,
            reason: reason,
            configurationVersion: configuration.version
        )
        return (result, diagnostic(
            key: key,
            requiredCoverage: requiredCoverage,
            actualCoverage: actualCoverage,
            averageConfidence: averageConfidence,
            normalizationScaleValid: normalizationScaleValid,
            interpolationCount: 0,
            result: result
        ))
    }

    private func diagnostic(
        key: MovementMetricKey,
        requiredCoverage: Double,
        actualCoverage: Double,
        averageConfidence: Double?,
        normalizationScaleValid: Bool,
        interpolationCount: Int,
        result: MovementMetricResult
    ) -> MetricDiagnostic {
        MetricDiagnostic(
            metricKey: key,
            requiredCoverage: requiredCoverage,
            actualCoverage: actualCoverage,
            averageJointConfidence: averageConfidence,
            normalizationScaleValid: normalizationScaleValid,
            interpolationCount: interpolationCount,
            confidence: result.confidence,
            availability: result.availability,
            reason: result.reason,
            configurationVersion: configuration.version
        )
    }
}
