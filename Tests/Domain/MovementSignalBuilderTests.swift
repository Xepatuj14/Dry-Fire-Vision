import DryFireVisionCore
import DryFireVisionTestFixtures
import XCTest

final class MovementSignalBuilderTests: XCTestCase {
    func testStationaryPoseProducesLowMovementSignal() {
        let recording = recording(from: SyntheticPoseFixtures.stablePoseSequence(sampleCount: 6, interval: 0.05))
        let samples = MovementSignalBuilder(configuration: .fixtureTestConfiguration).build(from: recording)
        let velocities = samples.compactMap(\.velocity)

        XCTAssertFalse(velocities.isEmpty)
        XCTAssertTrue(velocities.allSatisfy { $0 <= 0.03 })
    }

    func testKnownJointDisplacementUsesTimestampVelocity() {
        let frames = [
            offsetPose(timestampSeconds: 0.00, offset: 0.00),
            offsetPose(timestampSeconds: 0.10, offset: 0.02)
        ]
        let samples = MovementSignalBuilder(configuration: .fixtureTestConfiguration).build(from: recording(from: frames))

        XCTAssertEqual(samples.last?.velocity ?? 0, 1.0, accuracy: SegmentationGoldenFixtures.signalTolerance)
    }

    func testIrregularTimestampSpacingUsesElapsedTime() {
        let frames = [
            offsetPose(timestampSeconds: 0.00, offset: 0.00),
            offsetPose(timestampSeconds: 0.20, offset: 0.02)
        ]
        let samples = MovementSignalBuilder(configuration: .fixtureTestConfiguration).build(from: recording(from: frames))

        XCTAssertEqual(samples.last?.velocity ?? 0, 0.5, accuracy: SegmentationGoldenFixtures.signalTolerance)
    }

    func testMissingOneJointDoesNotInjectZeroCoordinateMovement() {
        var second = offsetPose(timestampSeconds: 0.10, offset: 0.02)
        var joints = second.joints
        joints.removeValue(forKey: .leftWrist)
        second = PoseFrame(timestampSeconds: second.timestampSeconds, joints: joints)

        let samples = MovementSignalBuilder(configuration: .fixtureTestConfiguration).build(from: recording(from: [
            offsetPose(timestampSeconds: 0.00, offset: 0.00),
            second
        ]))

        XCTAssertEqual(samples.last?.availability, .available)
        XCTAssertEqual(samples.last?.contributingJointCount, 4)
        XCTAssertEqual(samples.last?.velocity ?? 0, 1.0, accuracy: SegmentationGoldenFixtures.signalTolerance)
    }

    func testNoValidContributingJointsProducesUnavailableSignal() {
        let frames = [
            SyntheticPoseFixtures.centeredFullBodyPerson(timestampSeconds: 0.00, confidence: 0.1),
            SyntheticPoseFixtures.centeredFullBodyPerson(timestampSeconds: 0.10, confidence: 0.1)
        ]
        let samples = MovementSignalBuilder(configuration: .fixtureTestConfiguration).build(from: recording(from: frames))

        XCTAssertTrue(samples.allSatisfy { $0.availability == .insufficientJointCoverage })
        XCTAssertTrue(samples.allSatisfy { $0.velocity == nil })
    }

    func testCompositeAggregationIsDeterministic() {
        let recording = recording(from: SyntheticPoseFixtures.irregularTimingRepetitionFrames())
        let builder = MovementSignalBuilder(configuration: .fixtureTestConfiguration)

        XCTAssertEqual(builder.build(from: recording), builder.build(from: recording))
    }

    func testSmoothingReducesInjectedJitter() {
        let frames = [
            offsetPose(timestampSeconds: 0.00, offset: 0.00),
            offsetPose(timestampSeconds: 0.05, offset: 0.02),
            offsetPose(timestampSeconds: 0.10, offset: 0.00)
        ]
        let unsmoothed = MovementSignalBuilder(configuration: .fixtureTestConfiguration).build(from: recording(from: frames))
        let smoothedConfig = AnalysisConfiguration.fixtureTestConfiguration.withSmoothingAlpha(0.25)
        let smoothed = MovementSignalBuilder(configuration: smoothedConfig).build(from: recording(from: frames))

        XCTAssertLessThan(smoothed[1].velocity ?? 0, unsmoothed[1].velocity ?? 0)
        XCTAssertGreaterThan(smoothed[1].velocity ?? 0, 0)
    }

    private func recording(from frames: [PoseFrame]) -> PoseRecording {
        PoseRecording(
            id: UUID(uuid: (1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1)),
            startTimestampSeconds: 0,
            endTimestampSeconds: frames.last?.timestampSeconds ?? 0,
            poseFrames: frames,
            calibrationResult: SyntheticPoseFixtures.calibrationResult(),
            metadata: PoseRecordingMetadata(acceptedPoseFrameCount: frames.count)
        )
    }

    private func offsetPose(timestampSeconds: Double, offset: Double) -> PoseFrame {
        let base = SyntheticPoseFixtures.centeredFullBodyPerson(timestampSeconds: timestampSeconds)
        let joints = Dictionary(uniqueKeysWithValues: base.joints.map { jointID, sample in
            (
                jointID,
                JointSample(
                    jointID: jointID,
                    x: sample.x + offset,
                    y: sample.y,
                    confidence: sample.confidence
                )
            )
        })
        return PoseFrame(timestampSeconds: timestampSeconds, joints: joints)
    }
}

private extension AnalysisConfiguration {
    func withSmoothingAlpha(_ alpha: Double) -> AnalysisConfiguration {
        AnalysisConfiguration(
            version: version,
            lowConfidenceThreshold: lowConfidenceThreshold,
            mediumConfidenceThreshold: mediumConfidenceThreshold,
            highConfidenceThreshold: highConfidenceThreshold,
            maximumInterpolationGapSeconds: maximumInterpolationGapSeconds,
            smoothingAlpha: alpha,
            readyStabilityThreshold: readyStabilityThreshold,
            readyStabilityWindowSeconds: readyStabilityWindowSeconds,
            movementStartThreshold: movementStartThreshold,
            movementStartConfirmationWindowSeconds: movementStartConfirmationWindowSeconds,
            activeMovementThreshold: activeMovementThreshold,
            settleThreshold: settleThreshold,
            settleWindowSeconds: settleWindowSeconds,
            resetBaselineDistanceThreshold: resetBaselineDistanceThreshold,
            resetStabilityWindowSeconds: resetStabilityWindowSeconds,
            plausibleRepDurationMinimumSeconds: plausibleRepDurationMinimumSeconds,
            plausibleRepDurationMaximumSeconds: plausibleRepDurationMaximumSeconds,
            minimumSignalJointCount: minimumSignalJointCount,
            maximumPoseSignalGapSeconds: maximumPoseSignalGapSeconds
        )
    }
}
