import DryFireVisionCore
import DryFireVisionTestFixtures
import XCTest

final class PhaseNormalizerTests: XCTestCase {
    func testRepStartAndCompletionMapToPhaseBounds() throws {
        let fixture = ComparisonSyntheticFixtures.pair(.identicalDuration)
        let aligned = try XCTUnwrap(PhaseNormalizer(configuration: .comparisonTestConfiguration).align(
            analyzedRep: fixture.analyzedReps[0],
            recording: fixture.recording
        ))

        XCTAssertEqual(aligned.phaseGrid.first, 0)
        XCTAssertEqual(aligned.phaseGrid.last, 1)
        XCTAssertEqual(aligned.phaseGrid.count, 5)
    }

    func testResamplingPreservesKnownLinearTrajectory() throws {
        let fixture = ComparisonSyntheticFixtures.pair(.identicalDuration)
        let aligned = try XCTUnwrap(PhaseNormalizer(configuration: .comparisonTestConfiguration).align(
            analyzedRep: fixture.analyzedReps[0],
            recording: fixture.recording
        ))
        let wrist = try XCTUnwrap(aligned.trajectories[.rightWrist])
        let values = wrist.compactMap { $0?.x }

        XCTAssertEqual(values.count, 5)
        XCTAssertEqual(values[0], 3.45, accuracy: ComparisonGoldenFixtures.tolerance)
        XCTAssertEqual(values[4], 3.85, accuracy: ComparisonGoldenFixtures.tolerance)
    }

    func testDifferentDurationIdenticalShapeAlignsOnPhase() throws {
        let fixture = ComparisonSyntheticFixtures.pair(.identicalShapeDifferentSpeed)
        let normalizer = PhaseNormalizer(configuration: .comparisonTestConfiguration)
        let first = try XCTUnwrap(normalizer.align(analyzedRep: fixture.analyzedReps[0], recording: fixture.recording))
        let second = try XCTUnwrap(normalizer.align(analyzedRep: fixture.analyzedReps[1], recording: fixture.recording))

        XCTAssertEqual(
            (first.trajectories[.rightWrist] ?? []).compactMap { $0?.x },
            (second.trajectories[.rightWrist] ?? []).compactMap { $0?.x }
        )
        XCTAssertEqual(
            (first.trajectories[.rightWrist] ?? []).compactMap { $0?.y },
            (second.trajectories[.rightWrist] ?? []).compactMap { $0?.y }
        )
        XCTAssertNotEqual(fixture.analyzedReps[0].metrics.duration.value, fixture.analyzedReps[1].metrics.duration.value)
    }

    func testSourceRecordingRemainsUnchanged() throws {
        let fixture = ComparisonSyntheticFixtures.pair(.irregularTimestamps)
        let originalFrames = fixture.recording.poseFrames

        _ = PhaseNormalizer(configuration: .comparisonTestConfiguration).align(
            analyzedRep: fixture.analyzedReps[1],
            recording: fixture.recording
        )

        XCTAssertEqual(fixture.recording.poseFrames, originalFrames)
    }
}
