import DryFireVisionCore
import DryFireVisionTestFixtures
import XCTest

final class MovementMetricAnalyzerTests: XCTestCase {
    func testGoldenMetricFixturesMatchExpectedOutputs() throws {
        for fixtureID in SyntheticMetricFixtureID.allCases {
            let analyzed = try analyze(fixtureID)
            let expected = try XCTUnwrap(MetricGoldenFixtures.expected[fixtureID], fixtureID.rawValue)

            assertMetric(analyzed.metrics.duration, expected: expected.duration, fixtureID: fixtureID)
            assertMetric(analyzed.metrics.headDisplacement, expected: expected.headDisplacement, fixtureID: fixtureID)
            assertMetric(analyzed.metrics.shoulderDisplacement, expected: expected.shoulderDisplacement, fixtureID: fixtureID)
            assertMetric(analyzed.metrics.primaryWristPathLength, expected: expected.wristPathLength, fixtureID: fixtureID)
            assertMetric(analyzed.metrics.wristPathDirectness, expected: expected.wristPathDirectness, fixtureID: fixtureID)
            XCTAssertEqual(analyzed.metrics.analysisVersion, expected.analysisVersion)
            XCTAssertEqual(analyzed.metrics.configurationVersion, expected.configurationVersion)
        }
    }

    func testDurationUsesSegmentationBoundariesNotPoseCadence() throws {
        let analyzed = try analyze(.irregularTime)

        XCTAssertEqual(analyzed.metrics.duration.value ?? 0, 0.37, accuracy: MetricGoldenFixtures.valueTolerance)
    }

    func testHeadDisplacementUsesNormalizedBaselineRelativeDistance() throws {
        let analyzed = try analyze(.headMove)

        XCTAssertEqual(analyzed.metrics.headDisplacement.value ?? -1, 0.2, accuracy: MetricGoldenFixtures.valueTolerance)
        XCTAssertEqual(analyzed.metrics.headDisplacement.confidence, .high)
    }

    func testShoulderDisplacementUsesShoulderMidpoint() throws {
        let analyzed = try analyze(.shoulderMove)

        XCTAssertEqual(analyzed.metrics.shoulderDisplacement.value ?? -1, 0.3, accuracy: MetricGoldenFixtures.valueTolerance)
    }

    func testWristStraightPathHasDirectnessOne() throws {
        let analyzed = try analyze(.wristStraight)

        XCTAssertEqual(analyzed.metrics.primaryWristPathLength.value ?? -1, 0.5, accuracy: MetricGoldenFixtures.valueTolerance)
        XCTAssertEqual(analyzed.metrics.wristPathDirectness.value ?? -1, 1.0, accuracy: MetricGoldenFixtures.valueTolerance)
    }

    func testWristCurvedPathHasLongerPathThanStraightLine() throws {
        let analyzed = try analyze(.wristCurved)

        XCTAssertEqual(analyzed.metrics.primaryWristPathLength.value ?? -1, 0.7, accuracy: MetricGoldenFixtures.valueTolerance)
        XCTAssertEqual(analyzed.metrics.wristPathDirectness.value ?? -1, 5.0 / 7.0, accuracy: MetricGoldenFixtures.valueTolerance)
    }

    func testZeroWristPathDoesNotProduceDirectnessNaN() throws {
        let analyzed = try analyze(.wristZeroPath)

        XCTAssertEqual(analyzed.metrics.primaryWristPathLength.value ?? -1, 0, accuracy: MetricGoldenFixtures.valueTolerance)
        XCTAssertNil(analyzed.metrics.wristPathDirectness.value)
        XCTAssertEqual(analyzed.metrics.wristPathDirectness.reason, .nearZeroPathLength)
    }

    func testMissingHeadSuppressesOnlyHeadMetric() throws {
        let analyzed = try analyze(.missingHead)

        XCTAssertNil(analyzed.metrics.headDisplacement.value)
        XCTAssertEqual(analyzed.metrics.headDisplacement.availability, .unavailable)
        XCTAssertEqual(analyzed.metrics.duration.availability, .available)
        XCTAssertEqual(analyzed.metrics.shoulderDisplacement.availability, .available)
        XCTAssertEqual(analyzed.metrics.primaryWristPathLength.availability, .available)
    }

    func testInvalidNormalizationScaleSuppressesNormalizedMetricsButKeepsDuration() {
        let recording = MetricSyntheticFixtures.recordingWithInvalidScale()
        let segment = MetricSyntheticFixtures.segment(for: recording)
        let analyzed = RepMetricAnalyzer(configuration: .metricTestConfiguration)
            .analyze(segment: segment, recording: recording)

        XCTAssertEqual(analyzed.metrics.duration.availability, .available)
        XCTAssertEqual(analyzed.metrics.headDisplacement.reason, .invalidCalibrationScale)
        XCTAssertEqual(analyzed.metrics.shoulderDisplacement.reason, .invalidCalibrationScale)
        XCTAssertEqual(analyzed.metrics.primaryWristPathLength.reason, .invalidCalibrationScale)
        XCTAssertNil(analyzed.metrics.headDisplacement.value)
        XCTAssertNil(analyzed.metrics.primaryWristPathLength.value)
    }

    func testShortWristGapIsInterpolatedDeterministically() throws {
        let analyzed = try analyze(.shortWristGap)

        XCTAssertEqual(analyzed.metrics.primaryWristPathLength.value ?? -1, 0.3, accuracy: MetricGoldenFixtures.valueTolerance)
        XCTAssertTrue(analyzed.metricDiagnostics.contains { $0.metricKey == .primaryWristPathLength && $0.interpolationCount == 1 })
    }

    func testLongWristGapSuppressesWristMetrics() throws {
        let analyzed = try analyze(.longWristGap)

        XCTAssertNil(analyzed.metrics.primaryWristPathLength.value)
        XCTAssertEqual(analyzed.metrics.primaryWristPathLength.reason, .excessivePoseGap)
        XCTAssertEqual(analyzed.metrics.wristPathDirectness.reason, .excessivePoseGap)
    }

    func testMissingPrimaryWristSelectionDoesNotInferHandedness() {
        let recording = MetricSyntheticFixtures.recording(fixtureID: .wristStraight)
        let segment = MetricSyntheticFixtures.segment(for: recording)
        let analyzed = RepMetricAnalyzer(configuration: AnalysisConfiguration())
            .analyze(segment: segment, recording: recording)

        XCTAssertEqual(analyzed.metrics.primaryWristPathLength.reason, .primaryWristUnavailable)
        XCTAssertNil(analyzed.metrics.primaryWristPathLength.value)
    }

    func testPoorSegmentationConfidenceReducesDurationConfidence() {
        let recording = MetricSyntheticFixtures.recording(fixtureID: .wristStraight)
        let segment = RepSegment(
            id: UUID(uuid: (5, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1)),
            sequenceIndex: 0,
            startTimestampSeconds: 0,
            activeMovementEndTimestampSeconds: nil,
            completeTimestampSeconds: 0.2,
            validity: .valid,
            confidenceStatus: .medium,
            diagnosticReason: .none
        )
        let analyzed = RepMetricAnalyzer(configuration: .metricTestConfiguration)
            .analyze(segment: segment, recording: recording)

        XCTAssertEqual(analyzed.metrics.duration.confidence, .medium)
    }

    func testInvalidSegmentSuppressesDuration() {
        let recording = MetricSyntheticFixtures.recording(fixtureID: .wristStraight)
        let segment = RepSegment(
            id: UUID(uuid: (6, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1)),
            sequenceIndex: 0,
            startTimestampSeconds: 0,
            activeMovementEndTimestampSeconds: nil,
            completeTimestampSeconds: 0.2,
            validity: .invalid,
            confidenceStatus: .low,
            diagnosticReason: .durationBelowMinimum
        )
        let analyzed = RepMetricAnalyzer(configuration: .metricTestConfiguration)
            .analyze(segment: segment, recording: recording)

        XCTAssertEqual(analyzed.metrics.duration.availability, .unavailable)
        XCTAssertEqual(analyzed.metrics.duration.reason, .invalidSegment)
    }

    func testRepeatMetricAnalysisIsDeterministic() throws {
        let first = try analyze(.wristCurved)
        let second = try analyze(.wristCurved)

        XCTAssertEqual(first, second)
    }

    func testAllAvailableMetricValuesAreFinite() throws {
        for fixtureID in SyntheticMetricFixtureID.allCases {
            let metrics = try analyze(fixtureID).metrics
            for metric in [
                metrics.duration,
                metrics.headDisplacement,
                metrics.shoulderDisplacement,
                metrics.primaryWristPathLength,
                metrics.wristPathDirectness
            ] {
                if let value = metric.value {
                    XCTAssertTrue(value.isFinite, fixtureID.rawValue)
                }
            }
        }
    }

    private func analyze(_ fixtureID: SyntheticMetricFixtureID) throws -> AnalyzedRep {
        let recording = MetricSyntheticFixtures.recording(fixtureID: fixtureID)
        let segment = MetricSyntheticFixtures.segment(for: recording)
        return RepMetricAnalyzer(configuration: .metricTestConfiguration)
            .analyze(segment: segment, recording: recording)
    }

    private func assertMetric(
        _ metric: MovementMetricResult,
        expected: Double?,
        fixtureID: SyntheticMetricFixtureID
    ) {
        if let expected {
            XCTAssertEqual(metric.availability, .available, fixtureID.rawValue)
            guard let value = metric.value else {
                XCTFail("Expected metric value for \(fixtureID.rawValue)")
                return
            }
            XCTAssertEqual(value, expected, accuracy: MetricGoldenFixtures.valueTolerance, fixtureID.rawValue)
        } else {
            XCTAssertEqual(metric.availability, .unavailable, fixtureID.rawValue)
            XCTAssertNil(metric.value, fixtureID.rawValue)
        }
    }
}
