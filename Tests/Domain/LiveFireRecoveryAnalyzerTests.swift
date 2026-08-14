import DryFireVisionCore
import DryFireVisionTestFixtures
import XCTest

final class LiveFireRecoveryAnalyzerTests: XCTestCase {
    private let analyzer = LiveFireSessionAnalyzer()

    func testCleanFixtureProducesFiveAcceptedEvents() {
        let analysis = analyzer.analyze(LiveFireSyntheticFixtures.input(.clean5))

        XCTAssertEqual(analysis.acceptedEventCount, 5)
        XCTAssertEqual(analysis.events.filter { $0.recoveryDuration.availability == .available }.count, 5)
        XCTAssertTrue(analysis.events.allSatisfy { $0.peakVisibleDisplacement.value?.isFinite ?? true })
    }

    func testVariableRecoveryDurationsVaryPredictably() {
        let analysis = analyzer.analyze(LiveFireSyntheticFixtures.input(.variableRecovery))
        let durations = analysis.events.compactMap(\.recoveryDuration.value)

        XCTAssertGreaterThan(durations.last ?? 0, durations.first ?? 0)
    }

    func testBackgroundOnlyProducesNoConfidentRecoveryClaims() {
        let analysis = analyzer.analyze(LiveFireSyntheticFixtures.input(.backgroundOnly))

        XCTAssertEqual(analysis.acceptedEventCount, 0)
        XCTAssertTrue(analysis.events.allSatisfy { $0.recoveryDuration.availability == .unavailable })
    }

    func testPoseOcclusionSuppressesRecoveryMetric() {
        let analysis = analyzer.analyze(LiveFireSyntheticFixtures.input(.poseOccluded))

        XCTAssertEqual(analysis.events.first?.recoveryDuration.availability, .unavailable)
        XCTAssertEqual(analysis.events.first?.reason, .insufficientPoseCoverage)
    }

    func testInvalidNormalizationSuppressesRecoveryMetric() {
        let base = LiveFireSyntheticFixtures.input(.clean5)
        let analysis = analyzer.analyze(LiveFireSynchronizedInput(
            sessionID: base.sessionID,
            audioSamples: base.audioSamples,
            poseFrames: base.poseFrames,
            normalizationScale: 0
        ))

        XCTAssertEqual(analysis.events.first?.recoveryDuration.availability, .unavailable)
        XCTAssertEqual(analysis.events.first?.reason, .invalidNormalization)
    }
}
