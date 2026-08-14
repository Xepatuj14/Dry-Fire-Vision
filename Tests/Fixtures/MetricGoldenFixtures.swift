import DryFireVisionCore
import Foundation

public struct GoldenMetricExpectation: Equatable, Sendable {
    public let duration: Double?
    public let headDisplacement: Double?
    public let shoulderDisplacement: Double?
    public let wristPathLength: Double?
    public let wristPathDirectness: Double?
    public let expectedUnavailableKeys: [MovementMetricKey]
    public let analysisVersion: String
    public let configurationVersion: String

    public init(
        duration: Double?,
        headDisplacement: Double?,
        shoulderDisplacement: Double?,
        wristPathLength: Double?,
        wristPathDirectness: Double?,
        expectedUnavailableKeys: [MovementMetricKey] = [],
        analysisVersion: String = VersionCatalog.current.analysisVersion,
        configurationVersion: String = AnalysisConfiguration.metricTestConfiguration.version
    ) {
        self.duration = duration
        self.headDisplacement = headDisplacement
        self.shoulderDisplacement = shoulderDisplacement
        self.wristPathLength = wristPathLength
        self.wristPathDirectness = wristPathDirectness
        self.expectedUnavailableKeys = expectedUnavailableKeys
        self.analysisVersion = analysisVersion
        self.configurationVersion = configurationVersion
    }
}

public enum MetricGoldenFixtures {
    public static let valueTolerance = 0.0001

    public static let expected: [SyntheticMetricFixtureID: GoldenMetricExpectation] = [
        .stationaryHead: GoldenMetricExpectation(
            duration: 0.2,
            headDisplacement: 0,
            shoulderDisplacement: 0,
            wristPathLength: 0.2,
            wristPathDirectness: 1
        ),
        .headMove: GoldenMetricExpectation(
            duration: 0.2,
            headDisplacement: 0.2,
            shoulderDisplacement: 0,
            wristPathLength: 0.2,
            wristPathDirectness: 1
        ),
        .shoulderMove: GoldenMetricExpectation(
            duration: 0.2,
            headDisplacement: 0,
            shoulderDisplacement: 0.3,
            wristPathLength: 0.2,
            wristPathDirectness: 1
        ),
        .wristStraight: GoldenMetricExpectation(
            duration: 0.2,
            headDisplacement: 0,
            shoulderDisplacement: 0,
            wristPathLength: 0.5,
            wristPathDirectness: 1
        ),
        .wristCurved: GoldenMetricExpectation(
            duration: 0.2,
            headDisplacement: 0,
            shoulderDisplacement: 0,
            wristPathLength: 0.7,
            wristPathDirectness: 5.0 / 7.0
        ),
        .wristZeroPath: GoldenMetricExpectation(
            duration: 0.2,
            headDisplacement: 0,
            shoulderDisplacement: 0,
            wristPathLength: 0,
            wristPathDirectness: nil,
            expectedUnavailableKeys: [.wristPathDirectness]
        ),
        .missingHead: GoldenMetricExpectation(
            duration: 0.2,
            headDisplacement: nil,
            shoulderDisplacement: 0,
            wristPathLength: 0.2,
            wristPathDirectness: 1,
            expectedUnavailableKeys: [.headDisplacement]
        ),
        .shortWristGap: GoldenMetricExpectation(
            duration: 0.1,
            headDisplacement: 0,
            shoulderDisplacement: 0,
            wristPathLength: 0.3,
            wristPathDirectness: 1
        ),
        .longWristGap: GoldenMetricExpectation(
            duration: 0.5,
            headDisplacement: 0,
            shoulderDisplacement: 0,
            wristPathLength: nil,
            wristPathDirectness: nil,
            expectedUnavailableKeys: [.primaryWristPathLength, .wristPathDirectness]
        ),
        .irregularTime: GoldenMetricExpectation(
            duration: 0.37,
            headDisplacement: 0,
            shoulderDisplacement: 0,
            wristPathLength: 0.4,
            wristPathDirectness: 1
        )
    ]
}
