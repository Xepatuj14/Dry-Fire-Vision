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
}
