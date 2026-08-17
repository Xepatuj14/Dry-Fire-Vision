import DryFireVisionCore
import DryFireVisionTestFixtures
import XCTest

final class SessionAnalysisPipelineTests: XCTestCase {
    func testResultsFixtureGoldensProduceCompleteSessionAnalysis() async throws {
        for fixtureID in SessionAnalysisFixtureID.allCases {
            let analysis = try await SessionAnalysisPipeline().analyze(SessionAnalysisFixtureFactory.analysisInput(fixtureID))
            let expected = try XCTUnwrap(SessionAnalysisGoldenFixtures.expected[fixtureID], fixtureID.rawValue)

            XCTAssertEqual(analysis.status, expected.status, fixtureID.rawValue)
            XCTAssertEqual(analysis.validRepCount, expected.validRepCount, fixtureID.rawValue)
            XCTAssertEqual(analysis.targetRepCount, expected.targetRepCount, fixtureID.rawValue)
            XCTAssertEqual(analysis.analysisVersion, expected.analysisVersion, fixtureID.rawValue)
            XCTAssertEqual(analysis.analysisConfigurationVersion, expected.configurationVersion, fixtureID.rawValue)
            XCTAssertEqual(analysis.averageValidRepDurationSeconds != nil, expected.averageDurationAvailable, fixtureID.rawValue)
            XCTAssertEqual(analysis.movementConsistency.availability == .available, expected.consistencyAvailable, fixtureID.rawValue)
            XCTAssertTrue(expected.expectedReasons.allSatisfy { analysis.reasons.contains($0) }, fixtureID.rawValue)

            assertRepID(analysis.representativeRepID, equalsIndex: expected.representativeIndex, in: analysis, fixtureID: fixtureID)
            assertRepID(analysis.fastestRepID, equalsIndex: expected.fastestIndex, in: analysis, fixtureID: fixtureID)
            XCTAssertEqual(
                analysis.movementOutlierRepIDs,
                expected.outlierIndices.map { analysis.analyzedReps[$0].id },
                fixtureID.rawValue
            )
            XCTAssertTrue(analysis.analyzedReps.allSatisfy { rep in
                [
                    rep.metrics.duration.value,
                    rep.metrics.headDisplacement.value,
                    rep.metrics.shoulderDisplacement.value,
                    rep.metrics.primaryWristPathLength.value,
                    rep.metrics.wristPathDirectness.value
                ].allSatisfy { $0?.isFinite ?? true }
            }, fixtureID.rawValue)
        }
    }

    func testFullPipelineRepeatabilityIsDeterministic() async throws {
        let input = SessionAnalysisFixtureFactory.analysisInput(.oneOutlier)
        let analyzer = SessionAnalysisPipeline()

        let first = try await analyzer.analyze(input)
        let second = try await analyzer.analyze(input)

        XCTAssertEqual(first, second)
    }

    func testStandardDryFireSessionConfigurationProducesMovementConsistency() async throws {
        let configuration = DryFireSessionConfiguration()
        let input = AnalysisInput(
            recording: SessionAnalysisFixtureFactory.recording(.good10),
            targetRepCount: configuration.targetRepCount,
            configuration: configuration.analysisConfiguration
        )

        let analysis = try await SessionAnalysisPipeline().analyze(input)

        XCTAssertEqual(analysis.movementConsistency.availability, .available)
        XCTAssertEqual(analysis.movementConsistency.reason, .none)
    }

    func testInvalidCalibrationFailsConservatively() async {
        let recording = recordingWithInvalidScale(SessionAnalysisFixtureFactory.recording(.good10))
        let input = AnalysisInput(recording: recording, configuration: .resultsFixtureConfiguration)

        await XCTAssertThrowsErrorAsync({
            try await SessionAnalysisPipeline().analyze(input)
        }) { error in
            XCTAssertEqual(error as? SessionAnalysisError, .unusableCalibration)
        }
    }

    func testZeroPoseSamplesFailWithInsufficientPoseData() async {
        let source = SessionAnalysisFixtureFactory.recording(.good10)
        let recording = PoseRecording(
            id: source.id,
            startTimestampSeconds: 0,
            endTimestampSeconds: 0,
            poseFrames: [],
            calibrationResult: source.calibrationResult,
            metadata: source.metadata
        )
        let input = AnalysisInput(recording: recording, configuration: .resultsFixtureConfiguration)

        await XCTAssertThrowsErrorAsync({
            try await SessionAnalysisPipeline().analyze(input)
        }) { error in
            XCTAssertEqual(error as? SessionAnalysisError, .insufficientPoseData)
        }
    }

    func testNoValidRepsReturnsResultsCompatibleAnalysis() async throws {
        let analysis = try await SessionAnalysisPipeline().analyze(SessionAnalysisFixtureFactory.analysisInput(.noValidReps))

        XCTAssertEqual(analysis.status, .noValidReps)
        XCTAssertTrue(analysis.analyzedReps.isEmpty)
        XCTAssertNil(analysis.representativeRepID)
        XCTAssertNil(analysis.fastestRepID)
        XCTAssertNil(analysis.averageValidRepDurationSeconds)
    }

    func testInvalidConfigurationFailsExplicitly() async {
        let invalid = AnalysisConfiguration(
            primaryWristJointID: .rightWrist,
            comparisonPhaseSampleCount: 0
        )
        let input = AnalysisInput(recording: SessionAnalysisFixtureFactory.recording(.good10), configuration: invalid)

        await XCTAssertThrowsErrorAsync({
            try await SessionAnalysisPipeline().analyze(input)
        }) { error in
            XCTAssertEqual(error as? SessionAnalysisError, .invalidAnalysisConfiguration)
        }
    }

    private func assertRepID(
        _ actual: UUID?,
        equalsIndex index: Int?,
        in analysis: SessionAnalysis,
        fixtureID: SessionAnalysisFixtureID
    ) {
        if let index {
            XCTAssertEqual(actual, analysis.analyzedReps[index].id, fixtureID.rawValue)
        } else {
            XCTAssertNil(actual, fixtureID.rawValue)
        }
    }

    private func recordingWithInvalidScale(_ recording: PoseRecording) -> PoseRecording {
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
}

private func XCTAssertThrowsErrorAsync<T>(
    _ expression: () async throws -> T,
    _ errorHandler: (Error) -> Void,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        _ = try await expression()
        XCTFail("Expected error", file: file, line: line)
    } catch {
        errorHandler(error)
    }
}
