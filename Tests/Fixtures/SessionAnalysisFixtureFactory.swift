import DryFireVisionCore
import Foundation

public enum SessionAnalysisFixtureID: String, CaseIterable, Sendable {
    case good10 = "DF_RESULTS_GOOD_10"
    case oneOutlier = "DF_RESULTS_ONE_OUTLIER"
    case fastestIsOutlier = "DF_RESULTS_FASTEST_IS_OUTLIER"
    case degradedMetric = "DF_RESULTS_DEGRADED_METRIC"
    case partial = "DF_RESULTS_PARTIAL"
    case noValidReps = "DF_RESULTS_NO_VALID_REPS"
    case consistencyUnavailable = "DF_RESULTS_CONSISTENCY_UNAVAILABLE"
}

public enum SessionAnalysisFixtureFactory {
    public static func analysisInput(_ fixtureID: SessionAnalysisFixtureID) -> AnalysisInput {
        AnalysisInput(
            recording: recording(fixtureID),
            targetRepCount: 10,
            configuration: .resultsFixtureConfiguration
        )
    }

    public static func recording(_ fixtureID: SessionAnalysisFixtureID) -> PoseRecording {
        let frames: [PoseFrame]
        switch fixtureID {
        case .good10:
            frames = frames(repCount: 10)
        case .oneOutlier:
            frames = frames(repCount: 10, outlierIndices: [9])
        case .fastestIsOutlier:
            frames = frames(repCount: 10, outlierIndices: [9], fastIndices: [9])
        case .degradedMetric:
            frames = frames(repCount: 10, degradedMetricIndices: [4])
        case .partial:
            frames = frames(repCount: 7)
        case .noValidReps:
            frames = stableFrames(count: 32)
        case .consistencyUnavailable:
            frames = frames(repCount: 2)
        }

        return PoseRecording(
            id: recordingID(fixtureID),
            startTimestampSeconds: 0,
            endTimestampSeconds: frames.last?.timestampSeconds ?? 0,
            poseFrames: frames,
            calibrationResult: calibrationResult(),
            metadata: PoseRecordingMetadata(
                cameraPerspective: "fixture",
                captureOrientation: "portrait",
                nominalCaptureFPS: nil,
                effectivePoseFPS: nil,
                acceptedPoseFrameCount: frames.count
            )
        )
    }

    private static func frames(
        repCount: Int,
        outlierIndices: Set<Int> = [],
        fastIndices: Set<Int> = [],
        degradedMetricIndices: Set<Int> = []
    ) -> [PoseFrame] {
        var builder = FixtureFrameBuilder()
        builder.appendStable(count: 8)
        for index in 0..<repCount {
            builder.appendRep(
                isOutlier: outlierIndices.contains(index),
                isFast: fastIndices.contains(index),
                hasDegradedMetric: degradedMetricIndices.contains(index)
            )
        }
        return builder.frames
    }

    private static func stableFrames(count: Int) -> [PoseFrame] {
        var builder = FixtureFrameBuilder()
        builder.appendStable(count: count)
        return builder.frames
    }

    private static func recordingID(_ fixtureID: SessionAnalysisFixtureID) -> UUID {
        let suffix: UInt8
        switch fixtureID {
        case .good10:
            suffix = 80
        case .oneOutlier:
            suffix = 81
        case .fastestIsOutlier:
            suffix = 82
        case .degradedMetric:
            suffix = 83
        case .partial:
            suffix = 84
        case .noValidReps:
            suffix = 85
        case .consistencyUnavailable:
            suffix = 86
        }
        return UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 8, suffix))
    }

    private static func calibrationResult() -> CalibrationResult {
        let baseline = person(timestampSeconds: 0, signalOffset: 0)
        return CalibrationResult(
            baselinePose: BaselinePose(joints: baseline.joints, durationSeconds: 1),
            normalizationScale: 0.2,
            normalizationScaleSource: .shoulderWidth,
            quality: CalibrationQuality(requiredJointCoverage: 1, averageConfidence: 0.9, confidenceStatus: .high)
        )
    }

    fileprivate static func person(
        timestampSeconds: Double,
        signalOffset: Double,
        isOutlier: Bool = false,
        hasDegradedMetric: Bool = false
    ) -> PoseFrame {
        var joints: [PoseJointID: JointSample] = [
            .nose: JointSample(jointID: .nose, x: 0.50 + signalOffset, y: 0.14, confidence: 0.9),
            .leftShoulder: JointSample(jointID: .leftShoulder, x: 0.40 + signalOffset, y: 0.28, confidence: 0.9),
            .rightShoulder: JointSample(jointID: .rightShoulder, x: 0.60 + signalOffset, y: 0.28, confidence: 0.9),
            .leftElbow: JointSample(jointID: .leftElbow, x: 0.34 + signalOffset, y: 0.42, confidence: 0.9),
            .rightElbow: JointSample(jointID: .rightElbow, x: 0.66 + signalOffset, y: 0.42, confidence: 0.9),
            .leftWrist: JointSample(jointID: .leftWrist, x: 0.31 + signalOffset, y: 0.56, confidence: 0.9),
            .rightWrist: JointSample(jointID: .rightWrist, x: 0.69 + signalOffset, y: 0.56, confidence: 0.9),
            .leftHip: JointSample(jointID: .leftHip, x: 0.43 + signalOffset, y: 0.56, confidence: 0.9),
            .rightHip: JointSample(jointID: .rightHip, x: 0.57 + signalOffset, y: 0.56, confidence: 0.9),
            .leftKnee: JointSample(jointID: .leftKnee, x: 0.42 + signalOffset, y: 0.75, confidence: 0.9),
            .rightKnee: JointSample(jointID: .rightKnee, x: 0.58 + signalOffset, y: 0.75, confidence: 0.9),
            .leftAnkle: JointSample(jointID: .leftAnkle, x: 0.41 + signalOffset, y: 0.92, confidence: 0.9),
            .rightAnkle: JointSample(jointID: .rightAnkle, x: 0.59 + signalOffset, y: 0.92, confidence: 0.9)
        ]

        if isOutlier {
            joints[.nose] = moved(joints[.nose], xOffset: 0.10, yOffset: 0)
            joints[.leftShoulder] = moved(joints[.leftShoulder], xOffset: 0.08, yOffset: 0)
            joints[.rightShoulder] = moved(joints[.rightShoulder], xOffset: 0.08, yOffset: 0)
            joints[.rightWrist] = moved(joints[.rightWrist], xOffset: 0.14, yOffset: 0.08)
        }
        if hasDegradedMetric {
            joints.removeValue(forKey: .nose)
            joints.removeValue(forKey: .rightWrist)
        }

        return PoseFrame(timestampSeconds: timestampSeconds, joints: joints)
    }

    private static func moved(_ sample: JointSample?, xOffset: Double, yOffset: Double) -> JointSample? {
        guard let sample else {
            return nil
        }
        return JointSample(
            jointID: sample.jointID,
            x: sample.x + xOffset,
            y: sample.y + yOffset,
            confidence: sample.confidence
        )
    }
}

public extension AnalysisConfiguration {
    public static let resultsFixtureConfiguration = AnalysisConfiguration(
        smoothingAlpha: 1.0,
        readyStabilityThreshold: 0.18,
        readyStabilityWindowSeconds: 0.30,
        movementStartThreshold: 0.55,
        movementStartConfirmationWindowSeconds: 0.10,
        activeMovementThreshold: 0.22,
        settleThreshold: 0.18,
        settleWindowSeconds: 0.20,
        resetBaselineDistanceThreshold: 0.20,
        resetStabilityWindowSeconds: 0.20,
        plausibleRepDurationMinimumSeconds: 0.25,
        plausibleRepDurationMaximumSeconds: 8.00,
        minimumSignalJointCount: 3,
        maximumPoseSignalGapSeconds: 0.35,
        minimumHeadMetricCoverage: 0.80,
        minimumShoulderMetricCoverage: 0.80,
        minimumWristMetricCoverage: 0.80,
        maximumMetricGapSeconds: 0.12,
        nearZeroPathLengthThreshold: 0.000_001,
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

private struct FixtureFrameBuilder {
    private(set) var frames: [PoseFrame] = []
    private var timestamp: Double = 0
    private let interval: Double = 0.05

    mutating func appendStable(count: Int) {
        for _ in 0..<count {
            append(signalOffset: 0)
        }
    }

    mutating func appendRep(isOutlier: Bool, isFast: Bool, hasDegradedMetric: Bool) {
        let offsets = isFast
            ? [0.04, 0.08, 0.12, 0.12, 0.12, 0.12, 0.12, 0.08, 0.04, 0.00]
            : [0.04, 0.08, 0.12, 0.12, 0.12, 0.12, 0.12, 0.12, 0.08, 0.04, 0.00]
        for offset in offsets {
            append(signalOffset: offset, isOutlier: isOutlier, hasDegradedMetric: hasDegradedMetric)
        }
        appendStable(count: 5)
    }

    private mutating func append(
        signalOffset: Double,
        isOutlier: Bool = false,
        hasDegradedMetric: Bool = false
    ) {
        frames.append(SessionAnalysisFixtureFactory.person(
            timestampSeconds: timestamp,
            signalOffset: signalOffset,
            isOutlier: isOutlier,
            hasDegradedMetric: hasDegradedMetric
        ))
        timestamp += interval
    }
}
