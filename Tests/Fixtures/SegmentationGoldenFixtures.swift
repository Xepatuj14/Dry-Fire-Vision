import DryFireVisionCore
import Foundation

public struct GoldenRepSegmentExpectation: Equatable, Sendable {
    public let startTimestampSeconds: Double
    public let completeTimestampSeconds: Double
    public let validity: RepValidity

    public init(startTimestampSeconds: Double, completeTimestampSeconds: Double, validity: RepValidity) {
        self.startTimestampSeconds = startTimestampSeconds
        self.completeTimestampSeconds = completeTimestampSeconds
        self.validity = validity
    }
}

public struct GoldenSegmentationExpectation: Equatable, Sendable {
    public let fixtureID: SyntheticSegmentationFixtureID
    public let expectedValidRepCount: Int
    public let expectedRejectedRepCount: Int
    public let expectedSegments: [GoldenRepSegmentExpectation]
    public let configurationVersion: String

    public init(
        fixtureID: SyntheticSegmentationFixtureID,
        expectedValidRepCount: Int,
        expectedRejectedRepCount: Int,
        expectedSegments: [GoldenRepSegmentExpectation],
        configurationVersion: String = AnalysisConfiguration.fixtureTestConfiguration.version
    ) {
        self.fixtureID = fixtureID
        self.expectedValidRepCount = expectedValidRepCount
        self.expectedRejectedRepCount = expectedRejectedRepCount
        self.expectedSegments = expectedSegments
        self.configurationVersion = configurationVersion
    }
}

public enum SegmentationGoldenFixtures {
    public static let timestampTolerance = 0.0001
    public static let signalTolerance = 0.0001

    public static let expected: [SyntheticSegmentationFixtureID: GoldenSegmentationExpectation] = [
        .good10: GoldenSegmentationExpectation(
            fixtureID: .good10,
            expectedValidRepCount: 10,
            expectedRejectedRepCount: 0,
            expectedSegments: (0..<10).map { index in
                let start = 0.40 + Double(index) * 0.80
                return GoldenRepSegmentExpectation(
                    startTimestampSeconds: start,
                    completeTimestampSeconds: start + 0.35,
                    validity: .valid
                )
            }
        ),
        .falseStart: GoldenSegmentationExpectation(
            fixtureID: .falseStart,
            expectedValidRepCount: 1,
            expectedRejectedRepCount: 0,
            expectedSegments: [
                GoldenRepSegmentExpectation(startTimestampSeconds: 0.60, completeTimestampSeconds: 0.95, validity: .valid)
            ]
        ),
        .pauseMidRep: GoldenSegmentationExpectation(
            fixtureID: .pauseMidRep,
            expectedValidRepCount: 1,
            expectedRejectedRepCount: 0,
            expectedSegments: [
                GoldenRepSegmentExpectation(startTimestampSeconds: 0.40, completeTimestampSeconds: 0.90, validity: .valid)
            ]
        ),
        .noReset: GoldenSegmentationExpectation(
            fixtureID: .noReset,
            expectedValidRepCount: 1,
            expectedRejectedRepCount: 0,
            expectedSegments: [
                GoldenRepSegmentExpectation(startTimestampSeconds: 0.40, completeTimestampSeconds: 0.75, validity: .valid)
            ]
        ),
        .noReps: GoldenSegmentationExpectation(
            fixtureID: .noReps,
            expectedValidRepCount: 0,
            expectedRejectedRepCount: 0,
            expectedSegments: []
        ),
        .irregularTiming: GoldenSegmentationExpectation(
            fixtureID: .irregularTiming,
            expectedValidRepCount: 1,
            expectedRejectedRepCount: 0,
            expectedSegments: [
                GoldenRepSegmentExpectation(startTimestampSeconds: 0.44, completeTimestampSeconds: 0.86, validity: .valid)
            ]
        )
    ]
}

public extension AnalysisConfiguration {
    static let fixtureTestConfiguration = AnalysisConfiguration(
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
        plausibleRepDurationMaximumSeconds: 8.00,
        minimumSignalJointCount: 3,
        maximumPoseSignalGapSeconds: 0.35
    )
}
