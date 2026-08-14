import Foundation

public struct MetricPosePreprocessor: Sendable {
    public let configuration: AnalysisConfiguration

    public init(configuration: AnalysisConfiguration) {
        self.configuration = configuration
    }

    public func trajectory(
        for jointID: PoseJointID,
        samples: [PoseFrame],
        calibration: CalibrationResult
    ) -> JointTrajectory {
        let scale = max(calibration.normalizationScale, 0.0001)
        let validPositions = samples.compactMap { frame -> NormalizedJointPosition? in
            guard let sample = frame.sample(for: jointID),
                  sample.confidence >= configuration.mediumConfidenceThreshold,
                  sample.x.isFinite,
                  sample.y.isFinite,
                  sample.confidence.isFinite else {
                return nil
            }

            return NormalizedJointPosition(
                timestampSeconds: frame.timestampSeconds,
                x: sample.x / scale,
                y: sample.y / scale,
                confidence: sample.confidence
            )
        }

        guard validPositions.count >= 2 else {
            return JointTrajectory(
                jointID: jointID,
                positions: validPositions,
                expectedSampleCount: samples.count,
                interpolationCount: 0,
                hasExcessiveGap: samples.count > validPositions.count
            )
        }

        var positions: [NormalizedJointPosition] = []
        var interpolationCount = 0
        var hasExcessiveGap = false

        for current in validPositions {
            if let previous = positions.last {
                let gap = current.timestampSeconds - previous.timestampSeconds
                let missingFrames = samples.filter {
                    $0.timestampSeconds > previous.timestampSeconds &&
                        $0.timestampSeconds < current.timestampSeconds
                }
                if !missingFrames.isEmpty {
                    if gap <= configuration.maximumInterpolationGapSeconds {
                        for frame in missingFrames {
                            appendInterpolatedPosition(
                                frameTimestamp: frame.timestampSeconds,
                                previous: previous,
                                current: current,
                                gap: gap,
                                positions: &positions,
                                interpolationCount: &interpolationCount
                            )
                        }
                    } else {
                        hasExcessiveGap = true
                    }
                } else if gap > configuration.maximumMetricGapSeconds {
                    hasExcessiveGap = true
                }
            }
            positions.append(current)
        }

        return JointTrajectory(
            jointID: jointID,
            positions: positions.sorted { $0.timestampSeconds < $1.timestampSeconds },
            expectedSampleCount: samples.count,
            interpolationCount: interpolationCount,
            hasExcessiveGap: hasExcessiveGap
        )
    }

    private func appendInterpolatedPosition(
        frameTimestamp: Double,
        previous: NormalizedJointPosition,
        current: NormalizedJointPosition,
        gap: Double,
        positions: inout [NormalizedJointPosition],
        interpolationCount: inout Int
    ) {
        let fraction = (frameTimestamp - previous.timestampSeconds) / gap
        guard fraction > 0, fraction < 1, fraction.isFinite else {
            return
        }
        positions.append(NormalizedJointPosition(
            timestampSeconds: frameTimestamp,
            x: previous.x + (current.x - previous.x) * fraction,
            y: previous.y + (current.y - previous.y) * fraction,
            confidence: min(previous.confidence, current.confidence),
            interpolated: true
        ))
        interpolationCount += 1
    }
}
