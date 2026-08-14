import DryFireVisionCore
import Foundation

public enum SyntheticMetricFixtureID: String, CaseIterable, Sendable {
    case stationaryHead = "DF_METRIC_STATIONARY_HEAD"
    case headMove = "DF_METRIC_HEAD_MOVE"
    case shoulderMove = "DF_METRIC_SHOULDER_MOVE"
    case wristStraight = "DF_METRIC_WRIST_STRAIGHT"
    case wristCurved = "DF_METRIC_WRIST_CURVED"
    case wristZeroPath = "DF_METRIC_WRIST_ZERO_PATH"
    case missingHead = "DF_METRIC_MISSING_HEAD"
    case shortWristGap = "DF_METRIC_SHORT_WRIST_GAP"
    case longWristGap = "DF_METRIC_LONG_WRIST_GAP"
    case irregularTime = "DF_METRIC_IRREGULAR_TIME"
}

public enum MetricSyntheticFixtures {
    public static func recording(fixtureID: SyntheticMetricFixtureID) -> PoseRecording {
        let frames: [PoseFrame]
        switch fixtureID {
        case .stationaryHead:
            frames = frames(headOffsets: [0, 0, 0], shoulderOffsets: [0, 0, 0], wristOffsets: [(0, 0), (0.02, 0), (0.04, 0)])
        case .headMove:
            frames = frames(headOffsets: [0, 0.02, 0.04], shoulderOffsets: [0, 0, 0], wristOffsets: [(0, 0), (0.02, 0), (0.04, 0)])
        case .shoulderMove:
            frames = frames(headOffsets: [0, 0, 0], shoulderOffsets: [0, 0.03, 0.06], wristOffsets: [(0, 0), (0.02, 0), (0.04, 0)])
        case .wristStraight:
            frames = frames(headOffsets: [0, 0, 0], shoulderOffsets: [0, 0, 0], wristOffsets: [(0, 0), (0.05, 0), (0.10, 0)])
        case .wristCurved:
            frames = frames(headOffsets: [0, 0, 0], shoulderOffsets: [0, 0, 0], wristOffsets: [(0, 0), (0.06, 0), (0.06, 0.08)])
        case .wristZeroPath:
            frames = frames(headOffsets: [0, 0, 0], shoulderOffsets: [0, 0, 0], wristOffsets: [(0, 0), (0, 0), (0, 0)])
        case .missingHead:
            frames = frames(headOffsets: [0, 0, 0], shoulderOffsets: [0, 0, 0], wristOffsets: [(0, 0), (0.02, 0), (0.04, 0)]).map {
                frameRemoving(.nose, from: $0)
            }
        case .shortWristGap:
            frames = [
                frame(timestamp: 0.0, wristOffset: (0, 0)),
                frameRemoving(.rightWrist, from: frame(timestamp: 0.05, wristOffset: (0.03, 0))),
                frame(timestamp: 0.10, wristOffset: (0.06, 0))
            ]
        case .longWristGap:
            frames = [
                frame(timestamp: 0.0, wristOffset: (0, 0)),
                frameRemoving(.rightWrist, from: frame(timestamp: 0.20, wristOffset: (0.03, 0))),
                frameRemoving(.rightWrist, from: frame(timestamp: 0.30, wristOffset: (0.06, 0))),
                frame(timestamp: 0.50, wristOffset: (0.10, 0))
            ]
        case .irregularTime:
            frames = [
                frame(timestamp: 0.00, wristOffset: (0, 0)),
                frame(timestamp: 0.13, wristOffset: (0.03, 0)),
                frame(timestamp: 0.37, wristOffset: (0.08, 0))
            ]
        }

        return PoseRecording(
            id: UUID(uuid: (2, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, UInt8(fixtureID.rawValue.count))),
            startTimestampSeconds: 0,
            endTimestampSeconds: frames.last?.timestampSeconds ?? 0,
            poseFrames: frames,
            calibrationResult: SyntheticPoseFixtures.calibrationResult(),
            metadata: PoseRecordingMetadata(acceptedPoseFrameCount: frames.count)
        )
    }

    public static func segment(for recording: PoseRecording) -> RepSegment {
        RepSegment(
            id: UUID(uuid: (3, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1)),
            sequenceIndex: 0,
            startTimestampSeconds: recording.poseFrames.first?.timestampSeconds ?? 0,
            activeMovementEndTimestampSeconds: nil,
            completeTimestampSeconds: recording.poseFrames.last?.timestampSeconds ?? 0,
            validity: .valid,
            confidenceStatus: .high,
            diagnosticReason: .none
        )
    }

    public static func segmentationResult(for recording: PoseRecording) -> SegmentationResult {
        SegmentationResult(
            segments: [segment(for: recording)],
            rejectedSegments: [],
            diagnostics: [],
            status: .complete,
            inputSampleCount: recording.poseFrames.count,
            analysisVersion: VersionCatalog.current.analysisVersion,
            configurationVersion: AnalysisConfiguration.metricTestConfiguration.version,
            failureReasons: []
        )
    }

    public static func recordingWithInvalidScale() -> PoseRecording {
        let recording = recording(fixtureID: .headMove)
        let calibration = CalibrationResult(
            baselinePose: recording.calibrationResult.baselinePose,
            normalizationScale: 0,
            normalizationScaleSource: .shoulderWidth,
            quality: recording.calibrationResult.quality
        )
        return PoseRecording(
            id: recording.id,
            startTimestampSeconds: recording.startTimestampSeconds,
            endTimestampSeconds: recording.endTimestampSeconds,
            poseFrames: recording.poseFrames,
            calibrationResult: calibration,
            metadata: recording.metadata
        )
    }

    private static func frames(
        headOffsets: [Double],
        shoulderOffsets: [Double],
        wristOffsets: [(Double, Double)]
    ) -> [PoseFrame] {
        let count = max(headOffsets.count, shoulderOffsets.count, wristOffsets.count)
        return (0..<count).map { index in
            frame(
                timestamp: Double(index) * 0.10,
                headOffset: headOffsets[min(index, headOffsets.count - 1)],
                shoulderOffset: shoulderOffsets[min(index, shoulderOffsets.count - 1)],
                wristOffset: wristOffsets[min(index, wristOffsets.count - 1)]
            )
        }
    }

    private static func frame(
        timestamp: Double,
        headOffset: Double = 0,
        shoulderOffset: Double = 0,
        wristOffset: (Double, Double) = (0, 0)
    ) -> PoseFrame {
        let base = SyntheticPoseFixtures.centeredFullBodyPerson(timestampSeconds: timestamp)
        var joints = base.joints
        joints[.nose] = moved(joints[.nose], xOffset: headOffset, yOffset: 0)
        joints[.leftShoulder] = moved(joints[.leftShoulder], xOffset: shoulderOffset, yOffset: 0)
        joints[.rightShoulder] = moved(joints[.rightShoulder], xOffset: shoulderOffset, yOffset: 0)
        joints[.rightWrist] = moved(joints[.rightWrist], xOffset: wristOffset.0, yOffset: wristOffset.1)
        return PoseFrame(timestampSeconds: timestamp, joints: joints)
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

    private static func frameRemoving(_ jointID: PoseJointID, from frame: PoseFrame) -> PoseFrame {
        var joints = frame.joints
        joints.removeValue(forKey: jointID)
        return PoseFrame(timestampSeconds: frame.timestampSeconds, joints: joints)
    }
}

public extension AnalysisConfiguration {
    static let metricTestConfiguration = AnalysisConfiguration(
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
        plausibleRepDurationMinimumSeconds: 0.30,
        plausibleRepDurationMaximumSeconds: 8.00,
        minimumSignalJointCount: 3,
        maximumPoseSignalGapSeconds: 0.35,
        minimumHeadMetricCoverage: 0.80,
        minimumShoulderMetricCoverage: 0.80,
        minimumWristMetricCoverage: 0.80,
        maximumMetricGapSeconds: 0.12,
        nearZeroPathLengthThreshold: 0.000_001,
        primaryWristJointID: .rightWrist
    )
}
