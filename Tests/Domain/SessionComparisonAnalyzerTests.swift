import DryFireVisionCore
import DryFireVisionTestFixtures
import XCTest

final class SessionComparisonAnalyzerTests: XCTestCase {
    func testSyntheticSessionGoldens() {
        for fixtureID in SyntheticSessionComparisonFixtureID.allCases {
            let fixture = ComparisonSyntheticFixtures.session(fixtureID)
            let result = SessionComparisonAnalyzer(configuration: .comparisonTestConfiguration)
                .analyze(recording: fixture.recording, analyzedReps: fixture.analyzedReps)
            let expected = ComparisonGoldenFixtures.sessionExpectations[fixtureID]
            let expectedRepresentative: UUID?
            if let index = expected?.representativeIndex {
                expectedRepresentative = fixture.analyzedReps[index].id
            } else {
                expectedRepresentative = nil
            }
            let expectedFastest: UUID?
            if let index = expected?.fastestIndex {
                expectedFastest = fixture.analyzedReps[index].id
            } else {
                expectedFastest = nil
            }

            XCTAssertEqual(result.representativeRepID, expectedRepresentative, fixtureID.rawValue)
            XCTAssertEqual(result.fastestRepID, expectedFastest, fixtureID.rawValue)
            XCTAssertEqual(result.outlierRepIDs, (expected?.outlierIndices ?? []).map { fixture.analyzedReps[$0].id }, fixtureID.rawValue)
            if let consistency = expected?.consistency {
                XCTAssertEqual(result.consistency.internalValue ?? -1, consistency, accuracy: ComparisonGoldenFixtures.tolerance, fixtureID.rawValue)
            } else {
                XCTAssertEqual(result.consistency.availability, .unavailable, fixtureID.rawValue)
            }
        }
    }

    func testFastestRepCanAlsoBeMovementOutlier() {
        let fixture = ComparisonSyntheticFixtures.session(.fastOutlier)
        let result = SessionComparisonAnalyzer(configuration: .comparisonTestConfiguration)
            .analyze(recording: fixture.recording, analyzedReps: fixture.analyzedReps)

        XCTAssertEqual(result.fastestRepID, fixture.analyzedReps[9].id)
        XCTAssertTrue(result.outlierRepIDs.contains(fixture.analyzedReps[9].id))
    }

    func testIdenticalSessionCreatesNoFalseOutliersAndHighConsistency() {
        let fixture = ComparisonSyntheticFixtures.session(.identical10)
        let result = SessionComparisonAnalyzer(configuration: .comparisonTestConfiguration)
            .analyze(recording: fixture.recording, analyzedReps: fixture.analyzedReps)

        XCTAssertTrue(result.outlierRepIDs.isEmpty)
        XCTAssertEqual(result.consistency.internalValue ?? 0, 1, accuracy: ComparisonGoldenFixtures.tolerance)
        XCTAssertEqual(result.consistency.confidence, .high)
    }

    func testInvalidRepIsExcluded() {
        let fixture = ComparisonSyntheticFixtures.session(.identical10)
        var reps = fixture.analyzedReps
        let invalidSegment = RepSegment(
            id: reps[0].id,
            sequenceIndex: reps[0].sequenceIndex,
            startTimestampSeconds: reps[0].segment.startTimestampSeconds,
            activeMovementEndTimestampSeconds: nil,
            completeTimestampSeconds: reps[0].segment.completeTimestampSeconds,
            validity: .invalid,
            confidenceStatus: .low,
            diagnosticReason: .durationBelowMinimum
        )
        reps[0] = AnalyzedRep(
            id: reps[0].id,
            sequenceIndex: reps[0].sequenceIndex,
            segment: invalidSegment,
            metrics: reps[0].metrics,
            metricDiagnostics: reps[0].metricDiagnostics,
            sourceRecordingID: reps[0].sourceRecordingID
        )

        let result = SessionComparisonAnalyzer(configuration: .comparisonTestConfiguration)
            .analyze(recording: fixture.recording, analyzedReps: reps)

        XCTAssertFalse(result.eligibleRepIDs.contains(reps[0].id))
        XCTAssertEqual(result.diagnostics.excludedRepReasons[reps[0].id], .invalidRep)
    }

    func testRepeatSessionAnalysisIsDeterministic() {
        let fixture = ComparisonSyntheticFixtures.session(.oneOutlier)
        let analyzer = SessionComparisonAnalyzer(configuration: .comparisonTestConfiguration)

        XCTAssertEqual(
            analyzer.analyze(recording: fixture.recording, analyzedReps: fixture.analyzedReps),
            analyzer.analyze(recording: fixture.recording, analyzedReps: fixture.analyzedReps)
        )
    }

    func testMissingPrimaryWristConfigurationExcludesComparisons() {
        let fixture = ComparisonSyntheticFixtures.session(.identical10)
        let result = SessionComparisonAnalyzer(configuration: AnalysisConfiguration())
            .analyze(recording: fixture.recording, analyzedReps: fixture.analyzedReps)

        XCTAssertTrue(result.eligibleRepIDs.isEmpty)
        XCTAssertEqual(result.diagnostics.excludedRepReasons[fixture.analyzedReps[0].id], .primaryWristUnavailable)
        XCTAssertEqual(result.consistency.availability, .unavailable)
    }
}
