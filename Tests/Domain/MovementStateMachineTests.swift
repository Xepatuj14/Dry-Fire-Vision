import DryFireVisionCore
import DryFireVisionTestFixtures
import XCTest

final class MovementStateMachineTests: XCTestCase {
    func testStableAcquisitionTransitionsWaitingForStableToReady() {
        let result = segment(.noReps)

        XCTAssertTrue(result.diagnostics.containsTransition(from: .waitingForStable, to: .ready))
        XCTAssertEqual(result.segments.count, 0)
    }

    func testTransientJitterRejectsFalseStartAndCreatesNoExtraRep() {
        let result = segment(.falseStart)

        XCTAssertTrue(result.diagnostics.contains { $0.event == .falseStartRejected })
        XCTAssertEqual(result.segments.count, 1)
    }

    func testConfirmedMovementTransitionsReadyToMovingAndBackdatesStart() {
        let result = segment(.good10)

        XCTAssertTrue(result.diagnostics.containsTransition(from: .ready, to: .moving))
        XCTAssertEqual(result.segments.first?.startTimestampSeconds ?? 0, 0.40, accuracy: SegmentationGoldenFixtures.timestampTolerance)
    }

    func testMidRepPauseReturnsSettlingToMovingWithoutSplittingRep() {
        let result = segment(.pauseMidRep)

        XCTAssertTrue(result.diagnostics.containsTransition(from: .moving, to: .settling))
        XCTAssertTrue(result.diagnostics.containsTransition(from: .settling, to: .moving))
        XCTAssertEqual(result.segments.count, 1)
    }

    func testTrueCompletionRequiresFullSettleWindow() {
        let result = segment(.good10)

        XCTAssertTrue(result.diagnostics.containsTransition(from: .settling, to: .complete))
        XCTAssertEqual(result.segments.first?.completeTimestampSeconds ?? 0, 0.75, accuracy: SegmentationGoldenFixtures.timestampTolerance)
    }

    func testNoResetPreventsNextRepetition() {
        let result = segment(.noReset)

        XCTAssertEqual(result.segments.count, 1)
        XCTAssertFalse(result.diagnostics.containsTransition(from: .resetting, to: .ready))
    }

    func testValidResetAllowsNextReadyState() {
        let result = segment(.good10)

        XCTAssertTrue(result.diagnostics.containsTransition(from: .resetting, to: .ready))
        XCTAssertEqual(result.segments.count, 10)
    }

    func testImpossibleDurationIsInvalid() throws {
        let recording = SyntheticPoseFixtures.segmentationRecording(fixtureID: .tooShort)
        let configuration = AnalysisConfiguration.fixtureTestConfiguration.withMinimumDuration(0.50)
        let result = try RepSegmenter(configuration: configuration).segment(recording)

        XCTAssertEqual(result.segments.count, 0)
        XCTAssertEqual(result.rejectedSegments.count, 1)
        XCTAssertEqual(result.rejectedSegments.first?.validity, .invalid)
        XCTAssertEqual(result.rejectedSegments.first?.diagnosticReason, .durationBelowMinimum)
    }

    private func segment(_ fixtureID: SyntheticSegmentationFixtureID) -> SegmentationResult {
        let recording = SyntheticPoseFixtures.segmentationRecording(fixtureID: fixtureID)
        return (try? RepSegmenter(configuration: .fixtureTestConfiguration).segment(recording)) ?? SegmentationResult(
            segments: [],
            rejectedSegments: [],
            diagnostics: [],
            status: .failed,
            inputSampleCount: recording.poseFrames.count,
            analysisVersion: VersionCatalog.current.analysisVersion,
            configurationVersion: AnalysisConfiguration.fixtureTestConfiguration.version,
            failureReasons: [.insufficientPoseData]
        )
    }
}

private extension Array where Element == SegmentationDiagnostic {
    func containsTransition(from: MovementAnalysisState, to: MovementAnalysisState) -> Bool {
        contains { diagnostic in
            diagnostic.event == .stateTransition &&
                diagnostic.fromState == from &&
                diagnostic.toState == to
        }
    }
}

private extension AnalysisConfiguration {
    func withMinimumDuration(_ minimumDuration: Double) -> AnalysisConfiguration {
        AnalysisConfiguration(
            version: version,
            lowConfidenceThreshold: lowConfidenceThreshold,
            mediumConfidenceThreshold: mediumConfidenceThreshold,
            highConfidenceThreshold: highConfidenceThreshold,
            maximumInterpolationGapSeconds: maximumInterpolationGapSeconds,
            smoothingAlpha: smoothingAlpha,
            readyStabilityThreshold: readyStabilityThreshold,
            readyStabilityWindowSeconds: readyStabilityWindowSeconds,
            movementStartThreshold: movementStartThreshold,
            movementStartConfirmationWindowSeconds: movementStartConfirmationWindowSeconds,
            activeMovementThreshold: activeMovementThreshold,
            settleThreshold: settleThreshold,
            settleWindowSeconds: settleWindowSeconds,
            resetBaselineDistanceThreshold: resetBaselineDistanceThreshold,
            resetStabilityWindowSeconds: resetStabilityWindowSeconds,
            plausibleRepDurationMinimumSeconds: minimumDuration,
            plausibleRepDurationMaximumSeconds: plausibleRepDurationMaximumSeconds,
            minimumSignalJointCount: minimumSignalJointCount,
            maximumPoseSignalGapSeconds: maximumPoseSignalGapSeconds
        )
    }
}
