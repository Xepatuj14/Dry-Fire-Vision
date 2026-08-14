import DryFireVisionCore
import Foundation

public struct GoldenSessionAnalysisExpectation: Equatable, Sendable {
    public let fixtureID: SessionAnalysisFixtureID
    public let status: SessionAnalysisStatus
    public let validRepCount: Int
    public let targetRepCount: Int
    public let representativeIndex: Int?
    public let fastestIndex: Int?
    public let outlierIndices: [Int]
    public let consistencyAvailable: Bool
    public let averageDurationAvailable: Bool
    public let expectedReasons: [SessionAnalysisReason]
    public let analysisVersion: String
    public let configurationVersion: String

    public init(
        fixtureID: SessionAnalysisFixtureID,
        status: SessionAnalysisStatus,
        validRepCount: Int,
        targetRepCount: Int = 10,
        representativeIndex: Int?,
        fastestIndex: Int?,
        outlierIndices: [Int],
        consistencyAvailable: Bool,
        averageDurationAvailable: Bool,
        expectedReasons: [SessionAnalysisReason],
        analysisVersion: String = VersionCatalog.current.analysisVersion,
        configurationVersion: String = AnalysisConfiguration.resultsFixtureConfiguration.version
    ) {
        self.fixtureID = fixtureID
        self.status = status
        self.validRepCount = validRepCount
        self.targetRepCount = targetRepCount
        self.representativeIndex = representativeIndex
        self.fastestIndex = fastestIndex
        self.outlierIndices = outlierIndices
        self.consistencyAvailable = consistencyAvailable
        self.averageDurationAvailable = averageDurationAvailable
        self.expectedReasons = expectedReasons
        self.analysisVersion = analysisVersion
        self.configurationVersion = configurationVersion
    }
}

public enum SessionAnalysisGoldenFixtures {
    public static let durationTolerance = 0.0001

    public static let expected: [SessionAnalysisFixtureID: GoldenSessionAnalysisExpectation] = [
        .good10: GoldenSessionAnalysisExpectation(
            fixtureID: .good10,
            status: .completed,
            validRepCount: 10,
            representativeIndex: 0,
            fastestIndex: 0,
            outlierIndices: [],
            consistencyAvailable: true,
            averageDurationAvailable: true,
            expectedReasons: [.none]
        ),
        .oneOutlier: GoldenSessionAnalysisExpectation(
            fixtureID: .oneOutlier,
            status: .completed,
            validRepCount: 10,
            representativeIndex: 0,
            fastestIndex: 0,
            outlierIndices: [9],
            consistencyAvailable: true,
            averageDurationAvailable: true,
            expectedReasons: [.none]
        ),
        .fastestIsOutlier: GoldenSessionAnalysisExpectation(
            fixtureID: .fastestIsOutlier,
            status: .completed,
            validRepCount: 10,
            representativeIndex: 0,
            fastestIndex: 9,
            outlierIndices: [9],
            consistencyAvailable: true,
            averageDurationAvailable: true,
            expectedReasons: [.none]
        ),
        .degradedMetric: GoldenSessionAnalysisExpectation(
            fixtureID: .degradedMetric,
            status: .degraded,
            validRepCount: 10,
            representativeIndex: 0,
            fastestIndex: 0,
            outlierIndices: [],
            consistencyAvailable: true,
            averageDurationAvailable: true,
            expectedReasons: [.metricUnavailable]
        ),
        .partial: GoldenSessionAnalysisExpectation(
            fixtureID: .partial,
            status: .degraded,
            validRepCount: 7,
            representativeIndex: 0,
            fastestIndex: 0,
            outlierIndices: [],
            consistencyAvailable: true,
            averageDurationAvailable: true,
            expectedReasons: [.fewerThanTargetReps]
        ),
        .noValidReps: GoldenSessionAnalysisExpectation(
            fixtureID: .noValidReps,
            status: .noValidReps,
            validRepCount: 0,
            representativeIndex: nil,
            fastestIndex: nil,
            outlierIndices: [],
            consistencyAvailable: false,
            averageDurationAvailable: false,
            expectedReasons: [.noValidReps, .fewerThanTargetReps, .metricUnavailable, .comparisonUnavailable]
        ),
        .consistencyUnavailable: GoldenSessionAnalysisExpectation(
            fixtureID: .consistencyUnavailable,
            status: .degraded,
            validRepCount: 2,
            representativeIndex: 0,
            fastestIndex: 0,
            outlierIndices: [],
            consistencyAvailable: false,
            averageDurationAvailable: true,
            expectedReasons: [.fewerThanTargetReps, .comparisonUnavailable]
        )
    ]
}
