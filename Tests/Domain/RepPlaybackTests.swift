import CoreGraphics
import XCTest
@testable import DryFireVisionCore

final class RepPlaybackTests: XCTestCase {
    func testPlaybackUsesRepRelativeTimeAndInterpolatesWithinBoundedGap() {
        let lookup = RepPoseSampleLookup(maximumInterpolationGapSeconds: 0.20)
        let samples = [
            sample(source: 10.0, repTime: 0.0, x: 0.20),
            sample(source: 10.10, repTime: 0.10, x: 0.40)
        ]

        let midpoint = lookup.sample(at: 0.05, in: samples)

        XCTAssertEqual(midpoint?.repTimeSeconds, 0.05, accuracy: 0.0001)
        XCTAssertEqual(midpoint?.sourceTimestampSeconds, 10.05, accuracy: 0.0001)
        XCTAssertEqual(midpoint?.joints[.rightWrist]?.x, 0.30, accuracy: 0.0001)
        XCTAssertEqual(midpoint?.joints[.rightWrist]?.isInterpolated, true)
    }

    func testLookupDoesNotBridgeLargeGapsOrFabricateMissingJoints() {
        let lookup = RepPoseSampleLookup(maximumInterpolationGapSeconds: 0.05)
        let lower = RepPlaybackPoseSample(
            sourceTimestampSeconds: 10,
            repTimeSeconds: 0,
            joints: [.rightWrist: RepPlaybackJoint(jointID: .rightWrist, x: 0.1, y: 0.2, confidence: 0.9)]
        )
        let upper = RepPlaybackPoseSample(
            sourceTimestampSeconds: 10.2,
            repTimeSeconds: 0.2,
            joints: [.leftWrist: RepPlaybackJoint(jointID: .leftWrist, x: 0.8, y: 0.2, confidence: 0.9)]
        )

        let result = lookup.sample(at: 0.11, in: [lower, upper])

        XCTAssertEqual(result, upper)
        XCTAssertNil(result?.joints[.rightWrist]?.isInterpolated == true ? result?.joints[.rightWrist] : nil)
    }

    func testAdvanceSpeedAffectsPlaybackOnly() {
        var playback = RepPlaybackModel(
            repID: UUID(),
            sessionStartTimestampSeconds: 5,
            sessionEndTimestampSeconds: 6,
            orderedPoseSamples: [sample(source: 5, repTime: 0, x: 0.2)]
        )

        playback.speed = .half
        playback.play()
        playback.advance(by: 0.4)

        XCTAssertEqual(playback.currentTimeSeconds, 0.2, accuracy: 0.0001)
        XCTAssertEqual(playback.sessionStartTimestampSeconds, 5)
        XCTAssertEqual(playback.sessionEndTimestampSeconds, 6)
        XCTAssertEqual(playback.durationSeconds, 1)
    }

    func testPauseStopsProgressionAndResumeContinues() {
        var playback = RepPlaybackModel(
            repID: UUID(),
            sessionStartTimestampSeconds: 0,
            sessionEndTimestampSeconds: 1,
            orderedPoseSamples: [sample(source: 0, repTime: 0, x: 0.2)]
        )

        playback.play()
        playback.advance(by: 0.2)
        playback.pause()
        playback.advance(by: 0.5)
        playback.play()
        playback.advance(by: 0.2)

        XCTAssertEqual(playback.currentTimeSeconds, 0.4, accuracy: 0.0001)
    }

    func testCoordinateMappingAspectFitAndMirroring() {
        let mapper = PosePlaybackDisplayMapper(sourceAspectRatio: 1, contentMode: .aspectFit, isMirrored: true)

        let origin = mapper.displayPoint(x: 0, y: 0, in: CGSize(width: 200, height: 100))
        let farCorner = mapper.displayPoint(x: 1, y: 1, in: CGSize(width: 200, height: 100))
        let center = mapper.displayPoint(x: 0.5, y: 0.5, in: CGSize(width: 200, height: 100))

        XCTAssertEqual(origin.x, 150, accuracy: 0.0001)
        XCTAssertEqual(origin.y, 0, accuracy: 0.0001)
        XCTAssertEqual(farCorner.x, 50, accuracy: 0.0001)
        XCTAssertEqual(farCorner.y, 100, accuracy: 0.0001)
        XCTAssertEqual(center.x, 100, accuracy: 0.0001)
        XCTAssertEqual(center.y, 50, accuracy: 0.0001)
    }

    func testSkeletonOmitsMissingJointAndDoesNotMutateInput() {
        let original = RepPlaybackPoseSample(
            sourceTimestampSeconds: 0,
            repTimeSeconds: 0,
            joints: [
                .leftShoulder: RepPlaybackJoint(jointID: .leftShoulder, x: 0.2, y: 0.2, confidence: 0.9),
                .leftElbow: RepPlaybackJoint(jointID: .leftElbow, x: 0.2, y: 0.4, confidence: 0.9),
                .rightShoulder: RepPlaybackJoint(jointID: .rightShoulder, x: 0.8, y: 0.2, confidence: 0.9)
            ]
        )

        let segments = PosePlaybackRenderer.skeletonSegments(for: original, in: CGSize(width: 100, height: 100), mapper: PosePlaybackDisplayMapper(sourceAspectRatio: 1))

        XCTAssertTrue(segments.contains { $0.startJointID == .leftShoulder && $0.endJointID == .leftElbow })
        XCTAssertFalse(segments.contains { $0.startJointID == .leftElbow && $0.endJointID == .leftWrist })
        XCTAssertEqual(original.joints.count, 3)
    }

    func testProgressiveTrajectoryPreservesChronologicalSource() {
        let samples = [
            sample(source: 0, repTime: 0, x: 0.1),
            sample(source: 0.1, repTime: 0.1, x: 0.2),
            sample(source: 0.2, repTime: 0.2, x: 0.3)
        ]
        let before = samples

        let path = PosePlaybackRenderer.trajectory(
            jointID: .rightWrist,
            samples: samples,
            through: 0.1,
            in: CGSize(width: 100, height: 100),
            mapper: PosePlaybackDisplayMapper(sourceAspectRatio: 1)
        )

        XCTAssertEqual(path.count, 2)
        XCTAssertLessThan(path[0].x, path[1].x)
        XCTAssertEqual(samples, before)
    }

    private func sample(source: Double, repTime: Double, x: Double) -> RepPlaybackPoseSample {
        RepPlaybackPoseSample(
            sourceTimestampSeconds: source,
            repTimeSeconds: repTime,
            joints: [
                .rightWrist: RepPlaybackJoint(jointID: .rightWrist, x: x, y: 0.5, confidence: 0.9),
                .rightElbow: RepPlaybackJoint(jointID: .rightElbow, x: x - 0.05, y: 0.4, confidence: 0.9),
                .rightShoulder: RepPlaybackJoint(jointID: .rightShoulder, x: x - 0.10, y: 0.3, confidence: 0.9)
            ]
        )
    }
}
