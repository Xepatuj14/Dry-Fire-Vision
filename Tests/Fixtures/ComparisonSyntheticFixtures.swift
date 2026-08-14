import DryFireVisionCore
import Foundation

public enum SyntheticComparisonFixtureID: String, CaseIterable, Sendable {
    case identicalDuration = "DF_COMPARE_IDENTICAL_DURATION"
    case identicalShapeDifferentSpeed = "DF_COMPARE_IDENTICAL_SHAPE_DIFFERENT_SPEED"
    case smallDivergence = "DF_COMPARE_SMALL_DIVERGENCE"
    case largeDivergence = "DF_COMPARE_LARGE_DIVERGENCE"
    case missingJoint = "DF_COMPARE_MISSING_JOINT"
    case insufficientOverlap = "DF_COMPARE_INSUFFICIENT_OVERLAP"
    case irregularTimestamps = "DF_COMPARE_IRREGULAR_TIMESTAMPS"
}

public enum SyntheticSessionComparisonFixtureID: String, CaseIterable, Sendable {
    case identical10 = "DF_SESSION_IDENTICAL_10"
    case oneOutlier = "DF_SESSION_ONE_OUTLIER"
    case fastOutlier = "DF_SESSION_FAST_OUTLIER"
    case speedVariationSameShape = "DF_SESSION_SPEED_VARIATION_SAME_SHAPE"
    case insufficient = "DF_SESSION_INSUFFICIENT"
}

public struct ComparisonFixtureSession: Sendable {
    public let recording: PoseRecording
    public let analyzedReps: [AnalyzedRep]

    public init(recording: PoseRecording, analyzedReps: [AnalyzedRep]) {
        self.recording = recording
        self.analyzedReps = analyzedReps
    }
}

public enum ComparisonSyntheticFixtures {
    public static func pair(_ fixtureID: SyntheticComparisonFixtureID) -> ComparisonFixtureSession {
        switch fixtureID {
        case .identicalDuration:
            return session(shapes: [.base, .base], durations: [1.0, 1.0])
        case .identicalShapeDifferentSpeed:
            return session(shapes: [.base, .base], durations: [1.0, 1.6])
        case .smallDivergence:
            return session(shapes: [.base, .smallDivergence], durations: [1.0, 1.0])
        case .largeDivergence:
            return session(shapes: [.base, .largeDivergence], durations: [1.0, 1.0])
        case .missingJoint:
            return session(shapes: [.base, .missingNose], durations: [1.0, 1.0])
        case .insufficientOverlap:
            return session(shapes: [.base, .insufficientOverlap], durations: [1.0, 1.0])
        case .irregularTimestamps:
            return session(shapes: [.base, .base], durations: [1.0, 1.0], irregularSecondRep: true)
        }
    }

    public static func session(_ fixtureID: SyntheticSessionComparisonFixtureID) -> ComparisonFixtureSession {
        switch fixtureID {
        case .identical10:
            return session(shapes: Array(repeating: .base, count: 10), durations: Array(repeating: 1.0, count: 10))
        case .oneOutlier:
            return session(shapes: Array(repeating: .base, count: 9) + [.largeDivergence], durations: Array(repeating: 1.0, count: 10))
        case .fastOutlier:
            return session(shapes: Array(repeating: .base, count: 9) + [.largeDivergence], durations: Array(repeating: 1.0, count: 9) + [0.55])
        case .speedVariationSameShape:
            return session(shapes: Array(repeating: .base, count: 6), durations: [0.7, 0.9, 1.0, 1.2, 1.4, 1.6])
        case .insufficient:
            return session(shapes: [.base, .base], durations: [1.0, 1.0])
        }
    }

    private static func session(
        shapes: [ComparisonShape],
        durations: [Double],
        irregularSecondRep: Bool = false
    ) -> ComparisonFixtureSession {
        var frames: [PoseFrame] = []
        var analyzed: [AnalyzedRep] = []
        var start = 0.0
        let calibration = SyntheticPoseFixtures.calibrationResult()

        for index in shapes.indices {
            let shape = shapes[index]
            let duration = durations[index]
            let times: [Double]
            if irregularSecondRep && index == 1 {
                times = [start, start + duration * 0.18, start + duration * 0.63, start + duration]
            } else {
                times = [start, start + duration * 0.5, start + duration]
            }
            frames += times.map { time in
                frame(timestamp: time, phase: (time - start) / duration, shape: shape)
            }

            let id = UUID(uuid: (7, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, UInt8(index + 1)))
            let segment = RepSegment(
                id: id,
                sequenceIndex: index,
                startTimestampSeconds: start,
                activeMovementEndTimestampSeconds: nil,
                completeTimestampSeconds: start + duration,
                validity: .valid,
                confidenceStatus: .high,
                diagnosticReason: .none
            )
            let metrics = MovementMetricSet(
                duration: .available(
                    key: .totalRepDuration,
                    value: duration,
                    confidence: .high,
                    configurationVersion: AnalysisConfiguration.comparisonTestConfiguration.version
                ),
                headDisplacement: .available(key: .headDisplacement, value: 0, confidence: .high, configurationVersion: AnalysisConfiguration.comparisonTestConfiguration.version),
                shoulderDisplacement: .available(key: .shoulderDisplacement, value: 0, confidence: .high, configurationVersion: AnalysisConfiguration.comparisonTestConfiguration.version),
                primaryWristPathLength: .available(key: .primaryWristPathLength, value: 0, confidence: .high, configurationVersion: AnalysisConfiguration.comparisonTestConfiguration.version),
                wristPathDirectness: .available(key: .wristPathDirectness, value: 1, confidence: .high, configurationVersion: AnalysisConfiguration.comparisonTestConfiguration.version),
                configurationVersion: AnalysisConfiguration.comparisonTestConfiguration.version
            )
            analyzed.append(AnalyzedRep(
                id: id,
                sequenceIndex: index,
                segment: segment,
                metrics: metrics,
                metricDiagnostics: [],
                sourceRecordingID: UUID(uuid: (8, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1))
            ))
            start += duration + 0.25
        }

        let recording = PoseRecording(
            id: UUID(uuid: (8, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1)),
            startTimestampSeconds: 0,
            endTimestampSeconds: frames.last?.timestampSeconds ?? 0,
            poseFrames: frames.sorted { $0.timestampSeconds < $1.timestampSeconds },
            calibrationResult: calibration,
            metadata: PoseRecordingMetadata(acceptedPoseFrameCount: frames.count)
        )
        return ComparisonFixtureSession(recording: recording, analyzedReps: analyzed)
    }

    private static func frame(timestamp: Double, phase: Double, shape: ComparisonShape) -> PoseFrame {
        let base = SyntheticPoseFixtures.centeredFullBodyPerson(timestampSeconds: timestamp)
        var joints = base.joints
        let divergence = shape.divergence
        joints[.nose] = moved(joints[.nose], xOffset: 0.02 * phase + divergence.head, yOffset: 0)
        joints[.leftShoulder] = moved(joints[.leftShoulder], xOffset: 0.015 * phase + divergence.leftShoulder, yOffset: 0)
        joints[.rightShoulder] = moved(joints[.rightShoulder], xOffset: 0.015 * phase + divergence.rightShoulder, yOffset: 0)
        joints[.rightWrist] = moved(joints[.rightWrist], xOffset: 0.08 * phase + divergence.wrist, yOffset: 0)

        if shape == .missingNose {
            joints.removeValue(forKey: .nose)
        }
        if shape == .insufficientOverlap {
            joints.removeValue(forKey: .nose)
            joints.removeValue(forKey: .leftShoulder)
            joints.removeValue(forKey: .rightShoulder)
            joints.removeValue(forKey: .rightWrist)
        }

        return PoseFrame(timestampSeconds: timestamp, joints: joints)
    }

    private static func moved(_ sample: JointSample?, xOffset: Double, yOffset: Double) -> JointSample? {
        guard let sample else {
            return nil
        }
        return JointSample(jointID: sample.jointID, x: sample.x + xOffset, y: sample.y + yOffset, confidence: sample.confidence)
    }
}

private enum ComparisonShape: Equatable {
    case base
    case smallDivergence
    case largeDivergence
    case missingNose
    case insufficientOverlap

    var divergence: (head: Double, leftShoulder: Double, rightShoulder: Double, wrist: Double) {
        switch self {
        case .base, .missingNose, .insufficientOverlap:
            return (0, 0, 0, 0)
        case .smallDivergence:
            return (0, 0, 0, 0.02)
        case .largeDivergence:
            return (0.12, 0.12, 0.12, 0.18)
        }
    }
}

public extension AnalysisConfiguration {
    static let comparisonTestConfiguration = AnalysisConfiguration(
        maximumInterpolationGapSeconds: 2.0,
        primaryWristJointID: .rightWrist,
        comparisonPhaseSampleCount: 5,
        minimumComparisonJointCoverage: 0.80,
        minimumUsableComparisonJoints: 3,
        comparisonJointWeights: [
            .nose: 0.25,
            .leftShoulder: 0.25,
            .rightShoulder: 0.25,
            .rightWrist: 0.25
        ],
        similarityErrorScale: 1.0,
        minimumRepsForSessionConsistency: 3,
        minimumRepsForOutlierDetection: 5,
        outlierMedianAbsoluteDeviationMultiplier: 3.5,
        zeroDispersionThreshold: 0.000_001
    )
}
