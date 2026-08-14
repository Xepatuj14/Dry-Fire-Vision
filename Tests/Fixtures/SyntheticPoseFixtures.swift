import DryFireVisionCore
import Foundation

public enum SyntheticPoseFixtures {
    public static func centeredFullBodyPerson(timestampSeconds: Double = 0, confidence: Double = 0.9) -> PoseFrame {
        PoseFrame(
            timestampSeconds: timestampSeconds,
            joints: [
                .nose: JointSample(jointID: .nose, x: 0.50, y: 0.14, confidence: confidence),
                .leftShoulder: JointSample(jointID: .leftShoulder, x: 0.40, y: 0.28, confidence: confidence),
                .rightShoulder: JointSample(jointID: .rightShoulder, x: 0.60, y: 0.28, confidence: confidence),
                .leftElbow: JointSample(jointID: .leftElbow, x: 0.34, y: 0.42, confidence: confidence),
                .rightElbow: JointSample(jointID: .rightElbow, x: 0.66, y: 0.42, confidence: confidence),
                .leftWrist: JointSample(jointID: .leftWrist, x: 0.31, y: 0.56, confidence: confidence),
                .rightWrist: JointSample(jointID: .rightWrist, x: 0.69, y: 0.56, confidence: confidence),
                .leftHip: JointSample(jointID: .leftHip, x: 0.43, y: 0.56, confidence: confidence),
                .rightHip: JointSample(jointID: .rightHip, x: 0.57, y: 0.56, confidence: confidence),
                .leftKnee: JointSample(jointID: .leftKnee, x: 0.42, y: 0.75, confidence: confidence),
                .rightKnee: JointSample(jointID: .rightKnee, x: 0.58, y: 0.75, confidence: confidence),
                .leftAnkle: JointSample(jointID: .leftAnkle, x: 0.41, y: 0.92, confidence: confidence),
                .rightAnkle: JointSample(jointID: .rightAnkle, x: 0.59, y: 0.92, confidence: confidence)
            ]
        )
    }

    public static func missingWrist(timestampSeconds: Double = 0) -> PoseFrame {
        var joints = centeredFullBodyPerson(timestampSeconds: timestampSeconds).joints
        joints.removeValue(forKey: .leftWrist)
        return PoseFrame(timestampSeconds: timestampSeconds, joints: joints)
    }

    public static func lowConfidenceWrist(timestampSeconds: Double = 0) -> PoseFrame {
        var joints = centeredFullBodyPerson(timestampSeconds: timestampSeconds).joints
        joints[.leftWrist] = JointSample(jointID: .leftWrist, x: 0.31, y: 0.56, confidence: 0.1)
        return PoseFrame(timestampSeconds: timestampSeconds, joints: joints)
    }

    public static func tooSmallPerson(timestampSeconds: Double = 0) -> PoseFrame {
        scaledPerson(timestampSeconds: timestampSeconds, centerX: 0.5, centerY: 0.5, scale: 0.35)
    }

    public static func croppedBody(timestampSeconds: Double = 0) -> PoseFrame {
        shiftedPerson(timestampSeconds: timestampSeconds, xOffset: -0.38, yOffset: 0)
    }

    public static func twoPersonResult(timestampSeconds: Double = 0) -> [PoseFrame] {
        [
            centeredFullBodyPerson(timestampSeconds: timestampSeconds),
            shiftedPerson(timestampSeconds: timestampSeconds, xOffset: 0.08, yOffset: 0)
        ]
    }

    public static func stablePoseSequence(sampleCount: Int, interval: Double) -> [PoseFrame] {
        (0..<sampleCount).map { index in
            shiftedPerson(timestampSeconds: Double(index) * interval, xOffset: Double(index) * 0.001, yOffset: 0)
        }
    }

    public static func movingPoseSequence(sampleCount: Int, interval: Double) -> [PoseFrame] {
        (0..<sampleCount).map { index in
            shiftedPerson(timestampSeconds: Double(index) * interval, xOffset: Double(index) * 0.04, yOffset: 0)
        }
    }

    public static func irregularCadenceRecordingFrames() -> [PoseFrame] {
        [0.000, 0.034, 0.067, 0.118, 0.151].map {
            centeredFullBodyPerson(timestampSeconds: $0)
        }
    }

    public static func droppedAnalysisIntervalFrames() -> [PoseFrame] {
        [0.000, 0.033, 0.066, 0.500, 0.533].map {
            centeredFullBodyPerson(timestampSeconds: $0)
        }
    }

    public static func lowConfidenceIntervalFrames() -> [PoseFrame] {
        [
            centeredFullBodyPerson(timestampSeconds: 0.0, confidence: 0.9),
            centeredFullBodyPerson(timestampSeconds: 0.1, confidence: 0.4),
            centeredFullBodyPerson(timestampSeconds: 0.2, confidence: 0.9)
        ]
    }

    public static func calibrationResult() -> CalibrationResult {
        let baselineFrame = centeredFullBodyPerson(timestampSeconds: 0)
        return CalibrationResult(
            baselinePose: BaselinePose(joints: baselineFrame.joints, durationSeconds: 1.0),
            normalizationScale: 0.2,
            normalizationScaleSource: .shoulderWidth,
            quality: CalibrationQuality(requiredJointCoverage: 1, averageConfidence: 0.9, confidenceStatus: .high)
        )
    }

    public static func completedStableRecording(
        id: UUID = UUID(uuidString: "00000000-0000-0000-0000-000000000001") ?? UUID()
    ) -> PoseRecording {
        let frames = irregularCadenceRecordingFrames()
        return PoseRecording(
            id: id,
            startTimestampSeconds: 10,
            endTimestampSeconds: 10 + (frames.last?.timestampSeconds ?? 0),
            poseFrames: frames,
            calibrationResult: calibrationResult(),
            metadata: PoseRecordingMetadata(
                nominalCaptureFPS: 60,
                effectivePoseFPS: 5 / 0.151,
                acceptedPoseFrameCount: frames.count
            )
        )
    }

    public static func segmentationRecording(fixtureID: SyntheticSegmentationFixtureID) -> PoseRecording {
        let frames: [PoseFrame]
        switch fixtureID {
        case .good10:
            frames = tenGoodRepetitionFrames()
        case .falseStart:
            frames = falseStartFrames()
        case .pauseMidRep:
            frames = pauseMidRepFrames()
        case .noReset:
            frames = noResetFrames()
        case .noReps:
            frames = stablePoseSequence(sampleCount: 30, interval: 0.05)
        case .tooShort:
            frames = oneGoodRepetitionFrames()
        case .tooLong:
            frames = tooLongFrames()
        case .irregularTiming:
            frames = irregularTimingRepetitionFrames()
        case .poseGap:
            frames = poseGapFrames()
        }

        return PoseRecording(
            id: fixtureID.recordingID,
            startTimestampSeconds: 0,
            endTimestampSeconds: frames.last?.timestampSeconds ?? 0,
            poseFrames: frames,
            calibrationResult: calibrationResult(),
            metadata: PoseRecordingMetadata(
                nominalCaptureFPS: nil,
                effectivePoseFPS: nil,
                acceptedPoseFrameCount: frames.count
            )
        )
    }

    public static func oneGoodRepetitionFrames() -> [PoseFrame] {
        var builder = SegmentationFrameBuilder()
        builder.appendStable(count: 8)
        builder.appendRep()
        return builder.frames
    }

    public static func tenGoodRepetitionFrames() -> [PoseFrame] {
        var builder = SegmentationFrameBuilder()
        builder.appendStable(count: 8)
        for _ in 0..<10 {
            builder.appendRep()
        }
        return builder.frames
    }

    public static func falseStartFrames() -> [PoseFrame] {
        var builder = SegmentationFrameBuilder()
        builder.appendStable(count: 8)
        builder.append(offset: 0.04)
        builder.append(offset: 0.00)
        builder.appendStable(count: 2)
        builder.appendRep()
        return builder.frames
    }

    public static func pauseMidRepFrames() -> [PoseFrame] {
        var builder = SegmentationFrameBuilder()
        builder.appendStable(count: 8)
        builder.append(offset: 0.04)
        builder.append(offset: 0.08)
        builder.append(offset: 0.12)
        builder.append(offset: 0.12)
        builder.append(offset: 0.16)
        builder.append(offset: 0.20)
        builder.append(offset: 0.20)
        builder.append(offset: 0.20)
        builder.append(offset: 0.20)
        builder.append(offset: 0.20)
        builder.append(offset: 0.20)
        builder.appendReturnToBaseline()
        builder.appendStable(count: 5)
        return builder.frames
    }

    public static func noResetFrames() -> [PoseFrame] {
        var builder = SegmentationFrameBuilder()
        builder.appendStable(count: 8)
        builder.appendRep(returnToBaseline: false)
        builder.append(offset: 0.16)
        builder.append(offset: 0.20)
        builder.append(offset: 0.24)
        builder.append(offset: 0.24)
        builder.append(offset: 0.24)
        builder.append(offset: 0.24)
        return builder.frames
    }

    public static func tooLongFrames() -> [PoseFrame] {
        var builder = SegmentationFrameBuilder()
        builder.appendStable(count: 8)
        builder.append(offset: 0.04)
        builder.append(offset: 0.08)
        builder.append(offset: 0.12)
        for index in 0..<185 {
            builder.append(offset: 0.12 + Double(index + 1) * 0.01)
        }
        return builder.frames
    }

    public static func irregularTimingRepetitionFrames() -> [PoseFrame] {
        let timesAndOffsets: [(Double, Double)] = [
            (0.00, 0.00), (0.07, 0.00), (0.13, 0.00), (0.21, 0.00), (0.29, 0.00), (0.36, 0.00),
            (0.44, 0.04), (0.51, 0.08), (0.58, 0.12), (0.67, 0.12), (0.76, 0.12), (0.86, 0.12),
            (0.95, 0.08), (1.03, 0.04), (1.12, 0.00), (1.21, 0.00), (1.31, 0.00), (1.40, 0.00)
        ]
        return timesAndOffsets.map { time, offset in
            shiftedPerson(timestampSeconds: time, xOffset: offset, yOffset: 0)
        }
    }

    public static func poseGapFrames() -> [PoseFrame] {
        [
            shiftedPerson(timestampSeconds: 0.00, xOffset: 0.00, yOffset: 0),
            shiftedPerson(timestampSeconds: 0.05, xOffset: 0.00, yOffset: 0),
            shiftedPerson(timestampSeconds: 0.10, xOffset: 0.00, yOffset: 0),
            shiftedPerson(timestampSeconds: 0.15, xOffset: 0.00, yOffset: 0),
            shiftedPerson(timestampSeconds: 0.20, xOffset: 0.00, yOffset: 0),
            shiftedPerson(timestampSeconds: 0.25, xOffset: 0.00, yOffset: 0),
            shiftedPerson(timestampSeconds: 0.30, xOffset: 0.00, yOffset: 0),
            shiftedPerson(timestampSeconds: 0.35, xOffset: 0.00, yOffset: 0),
            shiftedPerson(timestampSeconds: 0.40, xOffset: 0.04, yOffset: 0),
            shiftedPerson(timestampSeconds: 0.45, xOffset: 0.08, yOffset: 0),
            shiftedPerson(timestampSeconds: 0.90, xOffset: 0.12, yOffset: 0),
            shiftedPerson(timestampSeconds: 0.95, xOffset: 0.12, yOffset: 0),
            shiftedPerson(timestampSeconds: 1.00, xOffset: 0.12, yOffset: 0)
        ]
    }

    fileprivate static func shiftedPerson(timestampSeconds: Double, xOffset: Double, yOffset: Double) -> PoseFrame {
        let base = centeredFullBodyPerson(timestampSeconds: timestampSeconds)
        let shifted = Dictionary(uniqueKeysWithValues: base.joints.map { jointID, sample in
            (
                jointID,
                JointSample(
                    jointID: jointID,
                    x: sample.x + xOffset,
                    y: sample.y + yOffset,
                    confidence: sample.confidence
                )
            )
        })

        return PoseFrame(timestampSeconds: timestampSeconds, joints: shifted)
    }

    private static func scaledPerson(timestampSeconds: Double, centerX: Double, centerY: Double, scale: Double) -> PoseFrame {
        let base = centeredFullBodyPerson(timestampSeconds: timestampSeconds)
        let scaled = Dictionary(uniqueKeysWithValues: base.joints.map { jointID, sample in
            (
                jointID,
                JointSample(
                    jointID: jointID,
                    x: centerX + (sample.x - 0.5) * scale,
                    y: centerY + (sample.y - 0.5) * scale,
                    confidence: sample.confidence
                )
            )
        })

        return PoseFrame(timestampSeconds: timestampSeconds, joints: scaled)
    }
}

public enum SyntheticSegmentationFixtureID: String, CaseIterable, Sendable {
    case good10 = "DF_SYNTH_GOOD_10"
    case falseStart = "DF_SYNTH_FALSE_START"
    case pauseMidRep = "DF_SYNTH_PAUSE_MID_REP"
    case noReset = "DF_SYNTH_NO_RESET"
    case noReps = "DF_SYNTH_NO_REPS"
    case tooShort = "DF_SYNTH_TOO_SHORT"
    case tooLong = "DF_SYNTH_TOO_LONG"
    case irregularTiming = "DF_SYNTH_IRREGULAR_TIMING"
    case poseGap = "DF_SYNTH_POSE_GAP"

    var recordingID: UUID {
        switch self {
        case .good10:
            return UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 10))
        case .falseStart:
            return UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 11))
        case .pauseMidRep:
            return UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 12))
        case .noReset:
            return UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 13))
        case .noReps:
            return UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 14))
        case .tooShort:
            return UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 15))
        case .tooLong:
            return UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 16))
        case .irregularTiming:
            return UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 17))
        case .poseGap:
            return UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 18))
        }
    }
}

private struct SegmentationFrameBuilder {
    private(set) var frames: [PoseFrame] = []
    private var timestamp: Double = 0
    private let interval: Double = 0.05

    mutating func appendStable(count: Int) {
        for _ in 0..<count {
            append(offset: 0)
        }
    }

    mutating func appendRep(returnToBaseline: Bool = true) {
        append(offset: 0.04)
        append(offset: 0.08)
        append(offset: 0.12)
        append(offset: 0.12)
        append(offset: 0.12)
        append(offset: 0.12)
        append(offset: 0.12)
        append(offset: 0.12)
        if returnToBaseline {
            appendReturnToBaseline()
            appendStable(count: 5)
        }
    }

    mutating func appendReturnToBaseline() {
        append(offset: 0.08)
        append(offset: 0.04)
        append(offset: 0.00)
    }

    mutating func append(offset: Double) {
        frames.append(SyntheticPoseFixtures.shiftedPerson(timestampSeconds: timestamp, xOffset: offset, yOffset: 0))
        timestamp += interval
    }
}
