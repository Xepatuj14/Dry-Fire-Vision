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

    func testNormalCompletionBeforeRepWindowKeepsActualDuration() {
        let configuration = stateMachineTestConfiguration(maximumRepDuration: 2.0)
        let result = MovementStateMachine(configuration: configuration).process(samples: normalRepSignals())

        XCTAssertEqual(result.segments.count, 1)
        XCTAssertEqual(result.rejectedSegments.count, 0)
        XCTAssertEqual(result.segments.first?.validity, .valid)
        XCTAssertEqual(result.segments.first?.durationSeconds ?? 0, 0.60, accuracy: 0.0001)
        XCTAssertFalse(result.failureReasons.contains(.repWindowExceeded))
    }

    func testRepWindowExceededRejectsActiveRepAndReturnsToResetting() {
        let configuration = stateMachineTestConfiguration(maximumRepDuration: 0.50)
        let result = MovementStateMachine(configuration: configuration).process(samples: timedOutRepSignals())

        XCTAssertEqual(result.segments.count, 0)
        XCTAssertEqual(result.rejectedSegments.count, 1)
        XCTAssertEqual(result.rejectedSegments.first?.validity, .invalid)
        XCTAssertEqual(result.rejectedSegments.first?.diagnosticReason, .repWindowExceeded)
        XCTAssertTrue(result.failureReasons.contains(.repWindowExceeded))
        XCTAssertTrue(result.diagnostics.contains { $0.event == .repWindowExceeded })
        XCTAssertTrue(result.diagnostics.containsTransition(from: .moving, to: .resetting))
    }

    func testRepWindowDoesNotStartWhileReady() {
        let configuration = stateMachineTestConfiguration(maximumRepDuration: 0.50)
        let result = MovementStateMachine(configuration: configuration).process(samples: readyOnlySignals(durationSeconds: 15))

        XCTAssertEqual(result.segments.count, 0)
        XCTAssertEqual(result.rejectedSegments.count, 0)
        XCTAssertFalse(result.failureReasons.contains(.repWindowExceeded))
        XCTAssertTrue(result.diagnostics.containsTransition(from: .waitingForStable, to: .ready))
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

private func normalRepSignals() -> [MovementSignalSample] {
    [
        signal(0.00, velocity: nil, baselineDistance: nil, availability: .firstUsableSample),
        signal(0.10, velocity: 0.02),
        signal(0.20, velocity: 0.02),
        signal(0.30, velocity: 0.02),
        signal(0.40, velocity: 0.70),
        signal(0.50, velocity: 0.72),
        signal(0.60, velocity: 0.40),
        signal(0.70, velocity: 0.30),
        signal(0.80, velocity: 0.10),
        signal(0.90, velocity: 0.10),
        signal(1.00, velocity: 0.10),
        signal(1.10, velocity: 0.10),
        signal(1.20, velocity: 0.05)
    ]
}

private func timedOutRepSignals() -> [MovementSignalSample] {
    [
        signal(0.00, velocity: nil, baselineDistance: nil, availability: .firstUsableSample),
        signal(0.10, velocity: 0.02),
        signal(0.20, velocity: 0.02),
        signal(0.30, velocity: 0.02),
        signal(0.40, velocity: 0.70),
        signal(0.50, velocity: 0.72),
        signal(0.60, velocity: 0.72),
        signal(0.70, velocity: 0.72),
        signal(0.80, velocity: 0.72),
        signal(0.90, velocity: 0.72),
        signal(1.00, velocity: 0.05),
        signal(1.10, velocity: 0.05),
        signal(1.20, velocity: 0.05)
    ]
}

private func readyOnlySignals(durationSeconds: Double) -> [MovementSignalSample] {
    var samples = [signal(0, velocity: nil, baselineDistance: nil, availability: .firstUsableSample)]
    var timestamp = 0.1
    while timestamp <= durationSeconds {
        samples.append(signal(timestamp, velocity: 0.02))
        timestamp += 0.1
    }
    return samples
}

private func signal(
    _ timestamp: Double,
    velocity: Double?,
    baselineDistance: Double? = 0.01,
    availability: MovementSignalAvailability = .available
) -> MovementSignalSample {
    MovementSignalSample(
        timestampSeconds: timestamp,
        velocity: velocity,
        baselineDistance: baselineDistance,
        contributingJointCount: 3,
        availability: availability
    )
}

private func stateMachineTestConfiguration(maximumRepDuration: Double) -> AnalysisConfiguration {
    AnalysisConfiguration(
        smoothingAlpha: 1.0,
        readyStabilityThreshold: 0.18,
        readyStabilityWindowSeconds: 0.30,
        movementStartThreshold: 0.55,
        movementStartConfirmationWindowSeconds: 0.10,
        activeMovementThreshold: 0.22,
        settleThreshold: 0.18,
        settleWindowSeconds: 0.20,
        resetBaselineDistanceThreshold: 0.20,
        resetStabilityWindowSeconds: 0.20,
        plausibleRepDurationMinimumSeconds: 0.30,
        plausibleRepDurationMaximumSeconds: maximumRepDuration,
        minimumSignalJointCount: 3,
        maximumPoseSignalGapSeconds: 0.35
    )
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
