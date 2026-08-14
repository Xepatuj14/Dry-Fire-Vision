import DryFireVisionCore
import DryFireVisionTestFixtures
import XCTest

final class RepSegmenterTests: XCTestCase {
    func testGood10ProducesExactlyTenValidSegments() throws {
        let result = try segment(.good10)

        XCTAssertEqual(result.segments.count, 10)
        XCTAssertTrue(result.segments.allSatisfy { $0.validity == .valid })
    }

    func testSyntheticGoldensMatchExpectedBoundaries() throws {
        for fixtureID in [SyntheticSegmentationFixtureID.good10, .falseStart, .pauseMidRep, .noReset, .noReps, .irregularTiming] {
            let result = try segment(fixtureID)
            let expected = try XCTUnwrap(SegmentationGoldenFixtures.expected[fixtureID])

            XCTAssertEqual(result.segments.count, expected.expectedValidRepCount, fixtureID.rawValue)
            XCTAssertEqual(result.rejectedSegments.count, expected.expectedRejectedRepCount, fixtureID.rawValue)
            XCTAssertEqual(result.configurationVersion, expected.configurationVersion)

            for (segment, expectedSegment) in zip(result.segments, expected.expectedSegments) {
                XCTAssertEqual(segment.startTimestampSeconds, expectedSegment.startTimestampSeconds, accuracy: SegmentationGoldenFixtures.timestampTolerance, fixtureID.rawValue)
                XCTAssertEqual(segment.completeTimestampSeconds, expectedSegment.completeTimestampSeconds, accuracy: SegmentationGoldenFixtures.timestampTolerance, fixtureID.rawValue)
                XCTAssertEqual(segment.validity, expectedSegment.validity, fixtureID.rawValue)
            }
        }
    }

    func testTooLongFixtureProducesInvalidRejectedSegment() throws {
        let result = try segment(.tooLong)

        XCTAssertEqual(result.segments.count, 0)
        XCTAssertEqual(result.rejectedSegments.count, 1)
        XCTAssertEqual(result.rejectedSegments.first?.validity, .invalid)
        XCTAssertEqual(result.rejectedSegments.first?.diagnosticReason, .durationAboveMaximum)
        XCTAssertEqual(result.status, .degraded)
    }

    func testPoseGapDegradesWithoutFabricatingBoundaries() throws {
        let result = try segment(.poseGap)

        XCTAssertEqual(result.segments.count, 0)
        XCTAssertEqual(result.status, .degraded)
        XCTAssertTrue(result.failureReasons.contains(.poseSignalUnavailable))
    }

    func testRepeatSegmentationIsDeterministic() throws {
        let first = try segment(.good10)
        let second = try segment(.good10)

        XCTAssertEqual(first, second)
    }

    func testRealFixtureIDsAreReservedForFutureRecordedMedia() {
        XCTAssertEqual(FutureRecordedSegmentationFixtureID.allCases.map(\.rawValue), [
            "DF_FRONT_GOOD_10",
            "DF_45_GOOD_10",
            "DF_SIDE_GOOD_10",
            "DF_FAST_SLOW_MIX",
            "DF_ONE_OUTLIER",
            "DF_LOW_LIGHT",
            "DF_WRIST_OCCLUSION_SHORT",
            "DF_WRIST_OCCLUSION_LONG",
            "DF_LEAVES_FRAME",
            "DF_TWO_PEOPLE",
            "DF_CAMERA_MOVED",
            "DF_PAUSE_MID_REP",
            "DF_FALSE_START",
            "DF_NO_REPS"
        ])
    }

    private func segment(_ fixtureID: SyntheticSegmentationFixtureID) throws -> SegmentationResult {
        try RepSegmenter(configuration: .fixtureTestConfiguration)
            .segment(SyntheticPoseFixtures.segmentationRecording(fixtureID: fixtureID))
    }
}
