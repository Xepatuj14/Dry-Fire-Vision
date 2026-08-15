import DryFireVisionTestFixtures
import XCTest
@testable import DryFireVisionCore

final class CalibrationEvaluatorTests: XCTestCase {
    func testValidFullBodyPoseCanBecomeCalibrationEligible() {
        var evaluator = makeEvaluator()

        let evaluation = evaluator.evaluate(poseFrames: [SyntheticPoseFixtures.centeredFullBodyPerson()])

        if case .holdStill = evaluation.state {
            XCTAssertNotNil(evaluation.selectedPoseFrame)
        } else {
            XCTFail("Expected holdStill state, got \(evaluation.state)")
        }
    }

    func testNoPersonProducesSearchingState() {
        var evaluator = makeEvaluator()

        let evaluation = evaluator.evaluate(poseFrames: [])

        XCTAssertEqual(evaluation.state, .searchingForPerson)
    }

    func testMultiplePeopleBlocksReadiness() {
        var evaluator = makeEvaluator()

        let evaluation = evaluator.evaluate(poseFrames: SyntheticPoseFixtures.twoPersonResult())

        XCTAssertEqual(evaluation.state, .multiplePeople)
    }

    func testMissingRequiredJointBlocksReadiness() {
        var evaluator = makeEvaluator()

        let evaluation = evaluator.evaluate(poseFrames: [SyntheticPoseFixtures.missingWrist()])

        XCTAssertEqual(evaluation.state, .adjust(.keepWristsVisible))
    }

    func testLowConfidenceRequiredJointBlocksReadiness() {
        var evaluator = makeEvaluator()

        let evaluation = evaluator.evaluate(poseFrames: [SyntheticPoseFixtures.lowConfidenceWrist()])

        XCTAssertEqual(evaluation.state, .adjust(.keepWristsVisible))
    }

    func testBodyTooSmallProducesMoveCloser() {
        var evaluator = makeEvaluator()

        let evaluation = evaluator.evaluate(poseFrames: [SyntheticPoseFixtures.tooSmallPerson()])

        XCTAssertEqual(evaluation.state, .adjust(.moveCloser))
    }

    func testCroppedBodyProducesAdjustment() {
        var evaluator = makeEvaluator()

        let evaluation = evaluator.evaluate(poseFrames: [SyntheticPoseFixtures.croppedBody()])

        XCTAssertEqual(evaluation.state, .adjust(.moveRight))
    }

    func testStableSequenceProducesReadyBaseline() {
        var evaluator = makeEvaluator(stabilityWindowSeconds: 0.3, minimumBaselineSamples: 3)
        var finalEvaluation: CalibrationEvaluation?

        for frame in SyntheticPoseFixtures.stablePoseSequence(sampleCount: 4, interval: 0.1) {
            finalEvaluation = evaluator.evaluate(poseFrames: [frame])
        }

        guard case .ready(let result) = finalEvaluation?.state else {
            XCTFail("Expected ready state, got \(String(describing: finalEvaluation?.state))")
            return
        }

        XCTAssertEqual(result.normalizationScaleSource, .shoulderWidth)
        XCTAssertEqual(result.baselinePose.durationSeconds, 0.3, accuracy: 0.0001)
        XCTAssertGreaterThan(result.normalizationScale, 0.04)
    }

    func testExactCadenceCompletesCalibrationFromContinuousStability() {
        var evaluator = makeEvaluator(stabilityWindowSeconds: 1.0, minimumBaselineSamples: 4)
        var finalEvaluation: CalibrationEvaluation?

        for frame in stableFrames(timestamps: [0.0, 0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9, 1.0]) {
            finalEvaluation = evaluator.evaluate(poseFrames: [frame])
        }

        if case .ready = finalEvaluation?.state {
            XCTAssertTrue(true)
        } else {
            XCTFail("Expected ready state for exact 0.1s cadence, got \(String(describing: finalEvaluation?.state))")
        }
    }

    func testSlowerCadenceDoesNotStallAroundNinetyPercent() {
        var evaluator = makeEvaluator(stabilityWindowSeconds: 1.0, minimumBaselineSamples: 4)
        var finalEvaluation: CalibrationEvaluation?

        for frame in stableFrames(timestamps: [0.0, 0.133, 0.266, 0.399, 0.532, 0.665, 0.798, 0.931]) {
            finalEvaluation = evaluator.evaluate(poseFrames: [frame])
        }

        if case .holdStill(let progress) = finalEvaluation?.state {
            XCTAssertEqual(progress, 0.931, accuracy: 0.0001)
        } else {
            XCTFail("Expected holdStill state before the stability window elapsed, got \(String(describing: finalEvaluation?.state))")
        }

        finalEvaluation = evaluator.evaluate(poseFrames: [offsetPose(timestampSeconds: 1.064, xOffset: 0.008)])

        if case .ready = finalEvaluation?.state {
            XCTAssertTrue(true)
        } else {
            XCTFail("Expected ready state for slower cadence without a 90% stall, got \(String(describing: finalEvaluation?.state))")
        }
    }

    func testJitteredCadenceCompletesCalibrationFromElapsedStableTime() {
        var evaluator = makeEvaluator(stabilityWindowSeconds: 1.0, minimumBaselineSamples: 4)
        var finalEvaluation: CalibrationEvaluation?

        for frame in stableFrames(timestamps: [0.0, 0.11, 0.24, 0.36, 0.49, 0.61, 0.75, 0.88, 1.02]) {
            finalEvaluation = evaluator.evaluate(poseFrames: [frame])
        }

        if case .ready = finalEvaluation?.state {
            XCTAssertTrue(true)
        } else {
            XCTFail("Expected ready state for jittered cadence, got \(String(describing: finalEvaluation?.state))")
        }
    }

    func testMinorJitterWithinThresholdDoesNotPreventBaseline() {
        var evaluator = makeEvaluator(stabilityWindowSeconds: 0.3, stabilityMovementThreshold: 0.02, minimumBaselineSamples: 3)
        var finalEvaluation: CalibrationEvaluation?

        for frame in SyntheticPoseFixtures.stablePoseSequence(sampleCount: 4, interval: 0.1) {
            finalEvaluation = evaluator.evaluate(poseFrames: [frame])
        }

        if case .ready = finalEvaluation?.state {
            XCTAssertTrue(true)
        } else {
            XCTFail("Expected ready state for minor jitter")
        }
    }

    func testMeaningfulMovementResetsHoldStillProgress() {
        var evaluator = makeEvaluator(stabilityWindowSeconds: 0.3, stabilityMovementThreshold: 0.02, minimumBaselineSamples: 3)
        var finalEvaluation: CalibrationEvaluation?

        for frame in SyntheticPoseFixtures.movingPoseSequence(sampleCount: 4, interval: 0.1) {
            finalEvaluation = evaluator.evaluate(poseFrames: [frame])
        }

        XCTAssertEqual(finalEvaluation?.state, .holdStill(progress: 0))
    }

    func testMovementResetAllowsCompletionAfterNewStablePeriod() {
        var evaluator = makeEvaluator(stabilityWindowSeconds: 0.3, stabilityMovementThreshold: 0.02, minimumBaselineSamples: 3)
        var finalEvaluation: CalibrationEvaluation?

        for frame in [
            offsetPose(timestampSeconds: 0.0, xOffset: 0),
            offsetPose(timestampSeconds: 0.1, xOffset: 0.03),
            offsetPose(timestampSeconds: 0.2, xOffset: 0.03),
            offsetPose(timestampSeconds: 0.3, xOffset: 0.03),
            offsetPose(timestampSeconds: 0.4, xOffset: 0.03),
            offsetPose(timestampSeconds: 0.5, xOffset: 0.03)
        ] {
            finalEvaluation = evaluator.evaluate(poseFrames: [frame])
        }

        if case .ready = finalEvaluation?.state {
            XCTAssertTrue(true)
        } else {
            XCTFail("Expected ready state after movement reset and new stable period, got \(String(describing: finalEvaluation?.state))")
        }
    }

    func testInvalidShoulderWidthBlocksNormalization() {
        var joints = SyntheticPoseFixtures.centeredFullBodyPerson().joints
        joints[.rightShoulder] = JointSample(jointID: .rightShoulder, x: 0.401, y: 0.28, confidence: 0.9)
        var evaluator = makeEvaluator()

        let evaluation = evaluator.evaluate(poseFrames: [PoseFrame(timestampSeconds: 0, joints: joints)])

        XCTAssertEqual(evaluation.state, .adjust(.keepShouldersVisible))
    }

    func testInsufficientBaselineSamplesCannotCreateBaseline() {
        var evaluator = makeEvaluator(stabilityWindowSeconds: 0.1, minimumBaselineSamples: 4)
        var finalEvaluation: CalibrationEvaluation?

        for frame in SyntheticPoseFixtures.stablePoseSequence(sampleCount: 2, interval: 0.1) {
            finalEvaluation = evaluator.evaluate(poseFrames: [frame])
        }

        XCTAssertEqual(finalEvaluation?.state, .capturingBaseline)
    }

    private func makeEvaluator(
        stabilityWindowSeconds: Double = 1,
        stabilityMovementThreshold: Double = 0.025,
        minimumBaselineSamples: Int = 4
    ) -> CalibrationEvaluator {
        CalibrationEvaluator(
            configuration: CalibrationConfiguration(
                stabilityWindowSeconds: stabilityWindowSeconds,
                stabilityMovementThreshold: stabilityMovementThreshold,
                minimumBaselineSamples: minimumBaselineSamples
            )
        )
    }

    private func stableFrames(timestamps: [Double]) -> [PoseFrame] {
        timestamps.enumerated().map { index, timestamp in
            offsetPose(timestampSeconds: timestamp, xOffset: Double(index) * 0.001)
        }
    }

    private func offsetPose(timestampSeconds: Double, xOffset: Double) -> PoseFrame {
        let base = SyntheticPoseFixtures.centeredFullBodyPerson(timestampSeconds: timestamp)
        let shifted = Dictionary(uniqueKeysWithValues: base.joints.map { jointID, sample in
            (
                jointID,
                JointSample(
                    jointID: jointID,
                    x: sample.x + xOffset,
                    y: sample.y,
                    confidence: sample.confidence
                )
            )
        })

        return PoseFrame(timestampSeconds: timestampSeconds, joints: shifted)
    }
}
