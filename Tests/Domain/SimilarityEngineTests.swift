import DryFireVisionCore
import DryFireVisionTestFixtures
import XCTest

final class SimilarityEngineTests: XCTestCase {
    func testSyntheticComparisonGoldens() throws {
        for fixtureID in SyntheticComparisonFixtureID.allCases {
            let comparison = try compare(fixtureID)
            let expected = ComparisonGoldenFixtures.pairSimilarities[fixtureID] ?? nil
            if let expected {
                XCTAssertEqual(comparison.availability, .available, fixtureID.rawValue)
                XCTAssertEqual(comparison.internalSimilarity ?? -1, expected, accuracy: ComparisonGoldenFixtures.tolerance, fixtureID.rawValue)
            } else {
                XCTAssertEqual(comparison.availability, .unavailable, fixtureID.rawValue)
            }
        }
    }

    func testIncreasingDivergenceDecreasesSimilarity() throws {
        let identical = try compare(.identicalDuration)
        let small = try compare(.smallDivergence)
        let large = try compare(.largeDivergence)

        XCTAssertGreaterThan(identical.internalSimilarity ?? 0, small.internalSimilarity ?? 0)
        XCTAssertGreaterThan(small.internalSimilarity ?? 0, large.internalSimilarity ?? 0)
    }

    func testComparisonIsSymmetricAndDeterministic() throws {
        let fixture = ComparisonSyntheticFixtures.pair(.smallDivergence)
        let normalizer = PhaseNormalizer(configuration: .comparisonTestConfiguration)
        let first = try XCTUnwrap(normalizer.align(analyzedRep: fixture.analyzedReps[0], recording: fixture.recording))
        let second = try XCTUnwrap(normalizer.align(analyzedRep: fixture.analyzedReps[1], recording: fixture.recording))
        let engine = SimilarityEngine(configuration: .comparisonTestConfiguration)

        let forward = engine.compare(first, second)
        let reverse = engine.compare(second, first)
        XCTAssertEqual(forward.aggregateError, reverse.aggregateError)
        XCTAssertEqual(forward.internalSimilarity, reverse.internalSimilarity)
        XCTAssertEqual(forward.jointResults.map(\.averageError), reverse.jointResults.map(\.averageError))
        XCTAssertEqual(forward, engine.compare(first, second))
    }

    func testMissingJointRenormalizesWeightsWhenEnoughJointsRemain() throws {
        let comparison = try compare(.missingJoint)

        XCTAssertEqual(comparison.availability, .available)
        XCTAssertEqual(comparison.jointResults.filter { $0.availability == .available }.count, 3)
        XCTAssertEqual(comparison.internalSimilarity ?? -1, 1, accuracy: ComparisonGoldenFixtures.tolerance)
        XCTAssertEqual(comparison.confidence, .high)
    }

    func testInsufficientOverlapIsUnavailableLowConfidence() throws {
        let comparison = try compare(.insufficientOverlap)

        XCTAssertEqual(comparison.availability, .unavailable)
        XCTAssertEqual(comparison.reason, .insufficientUsableJoints)
        XCTAssertEqual(comparison.confidence, .low)
    }

    func testSimilarityIsBoundedAndFinite() throws {
        for fixtureID in SyntheticComparisonFixtureID.allCases {
            let comparison = try compare(fixtureID)
            if let similarity = comparison.internalSimilarity {
                XCTAssertTrue(similarity.isFinite)
                XCTAssertGreaterThanOrEqual(similarity, 0)
                XCTAssertLessThanOrEqual(similarity, 1)
            }
        }
    }

    func testMixedAnalysisVersionsAreIncompatible() throws {
        let fixture = ComparisonSyntheticFixtures.pair(.identicalDuration)
        let normalizer = PhaseNormalizer(configuration: .comparisonTestConfiguration)
        let first = try XCTUnwrap(normalizer.align(analyzedRep: fixture.analyzedReps[0], recording: fixture.recording))
        let second = try XCTUnwrap(normalizer.align(analyzedRep: fixture.analyzedReps[1], recording: fixture.recording))
        let incompatible = PhaseAlignedRep(
            repID: second.repID,
            sequenceIndex: second.sequenceIndex,
            sourceRecordingID: second.sourceRecordingID,
            startTimestampSeconds: second.startTimestampSeconds,
            completeTimestampSeconds: second.completeTimestampSeconds,
            phaseGrid: second.phaseGrid,
            trajectories: second.trajectories,
            analysisVersion: "legacy",
            configurationVersion: second.configurationVersion
        )

        let result = SimilarityEngine(configuration: .comparisonTestConfiguration).compare(first, incompatible)

        XCTAssertEqual(result.availability, .unavailable)
        XCTAssertEqual(result.reason, .incompatibleAnalysisVersion)
    }

    private func compare(_ fixtureID: SyntheticComparisonFixtureID) throws -> RepComparisonResult {
        let fixture = ComparisonSyntheticFixtures.pair(fixtureID)
        let normalizer = PhaseNormalizer(configuration: .comparisonTestConfiguration)
        let first = try XCTUnwrap(normalizer.align(analyzedRep: fixture.analyzedReps[0], recording: fixture.recording))
        let second = try XCTUnwrap(normalizer.align(analyzedRep: fixture.analyzedReps[1], recording: fixture.recording))
        return SimilarityEngine(configuration: .comparisonTestConfiguration).compare(first, second)
    }
}
