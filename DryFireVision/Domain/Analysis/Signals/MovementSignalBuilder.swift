import Foundation

public struct MovementSignalBuilder: Sendable {
    public static let defaultJointIDs: [PoseJointID] = [
        .nose,
        .leftShoulder,
        .rightShoulder,
        .leftWrist,
        .rightWrist
    ]

    public let configuration: AnalysisConfiguration
    public let jointIDs: [PoseJointID]

    public init(configuration: AnalysisConfiguration, jointIDs: [PoseJointID] = Self.defaultJointIDs) {
        self.configuration = configuration
        self.jointIDs = jointIDs
    }

    public func build(from recording: PoseRecording) -> [MovementSignalSample] {
        let confidenceFilter = PoseConfidenceFilter(configuration: configuration)
        let smoother = ExponentialPoseSmoother(alpha: configuration.smoothingAlpha)
        let scale = max(recording.calibrationResult.normalizationScale, 0.0001)
        var previousTimestamp: Double?
        var previousSmoothed: [PoseJointID: PoseSignalPoint] = [:]
        var smoothed: [PoseJointID: PoseSignalPoint] = [:]
        var samples: [MovementSignalSample] = []

        for frame in recording.poseFrames {
            let filtered = confidenceFilter.filteredPoints(from: frame, jointIDs: jointIDs)
            smoothed = Dictionary(uniqueKeysWithValues: filtered.map { jointID, point in
                (jointID, smoother.smooth(current: point, previous: smoothed[jointID]))
            })

            let baselineDistance = averageBaselineDistance(
                smoothed: smoothed,
                baseline: recording.calibrationResult.baselinePose.joints,
                scale: scale
            )

            guard filtered.count >= configuration.minimumSignalJointCount else {
                samples.append(MovementSignalSample(
                    timestampSeconds: frame.timestampSeconds,
                    velocity: nil,
                    baselineDistance: baselineDistance,
                    contributingJointCount: filtered.count,
                    availability: .insufficientJointCoverage
                ))
                previousTimestamp = frame.timestampSeconds
                previousSmoothed = smoothed
                continue
            }

            guard let lastTimestamp = previousTimestamp else {
                samples.append(MovementSignalSample(
                    timestampSeconds: frame.timestampSeconds,
                    velocity: nil,
                    baselineDistance: baselineDistance,
                    contributingJointCount: filtered.count,
                    availability: .firstUsableSample
                ))
                previousTimestamp = frame.timestampSeconds
                previousSmoothed = smoothed
                continue
            }

            let elapsed = frame.timestampSeconds - lastTimestamp
            guard elapsed > 0 else {
                samples.append(MovementSignalSample(
                    timestampSeconds: frame.timestampSeconds,
                    velocity: nil,
                    baselineDistance: baselineDistance,
                    contributingJointCount: filtered.count,
                    availability: .invalidTimestampDelta
                ))
                previousTimestamp = frame.timestampSeconds
                previousSmoothed = smoothed
                continue
            }

            guard elapsed <= configuration.maximumPoseSignalGapSeconds else {
                samples.append(MovementSignalSample(
                    timestampSeconds: frame.timestampSeconds,
                    velocity: nil,
                    baselineDistance: baselineDistance,
                    contributingJointCount: filtered.count,
                    availability: .poseGapExceeded
                ))
                previousTimestamp = frame.timestampSeconds
                previousSmoothed = smoothed
                continue
            }

            let jointVelocities = jointIDs.compactMap { jointID -> Double? in
                guard let current = smoothed[jointID],
                      let previous = previousSmoothed[jointID] else {
                    return nil
                }
                let distance = hypot(current.x - previous.x, current.y - previous.y)
                return (distance / scale) / elapsed
            }

            guard jointVelocities.count >= configuration.minimumSignalJointCount else {
                samples.append(MovementSignalSample(
                    timestampSeconds: frame.timestampSeconds,
                    velocity: nil,
                    baselineDistance: baselineDistance,
                    contributingJointCount: jointVelocities.count,
                    availability: .insufficientJointCoverage
                ))
                previousTimestamp = frame.timestampSeconds
                previousSmoothed = smoothed
                continue
            }

            let velocity = jointVelocities.reduce(0, +) / Double(jointVelocities.count)
            samples.append(MovementSignalSample(
                timestampSeconds: frame.timestampSeconds,
                velocity: velocity,
                baselineDistance: baselineDistance,
                contributingJointCount: jointVelocities.count,
                availability: .available
            ))

            previousTimestamp = frame.timestampSeconds
            previousSmoothed = smoothed
        }

        return samples
    }

    private func averageBaselineDistance(
        smoothed: [PoseJointID: PoseSignalPoint],
        baseline: [PoseJointID: JointSample],
        scale: Double
    ) -> Double? {
        let distances = jointIDs.compactMap { jointID -> Double? in
            guard let current = smoothed[jointID],
                  let baseline = baseline[jointID],
                  baseline.confidence >= configuration.mediumConfidenceThreshold else {
                return nil
            }
            return hypot(current.x - baseline.x, current.y - baseline.y) / scale
        }

        guard distances.count >= configuration.minimumSignalJointCount else {
            return nil
        }

        return distances.reduce(0, +) / Double(distances.count)
    }
}
