import CoreGraphics
import DryFireVisionTestFixtures
import XCTest
@testable import DryFireVisionCore

final class GhostModePlaybackTests: XCTestCase {
    func testIdenticalRepComparisonUsesExistingSimilarityAndDoesNotMutateSource() async throws {
        let analysis = try await SessionAnalysisPipeline().analyze(SessionAnalysisFixtureFactory.analysisInput(.good10))
        let rep = try XCTUnwrap(analysis.analyzedReps.first)
        let payload = try XCTUnwrap(SessionAnalysisPersistenceMapper.posePayload(for: rep, analysis: analysis))
        let originalRep = rep
        let originalPayload = payload

        let result = GhostComparisonBuilder(configuration: .resultsFixtureConfiguration)
            .compare(repA: rep, payloadA: payload, repB: rep, payloadB: payload)

        guard case .success(let comparison) = result else {
            return XCTFail("Expected self-comparison to be available, got \(result)")
        }
        XCTAssertEqual(comparison.comparison.internalSimilarity ?? 0, 1, accuracy: 0.0001)
        XCTAssertEqual(rep, originalRep)
        XCTAssertEqual(payload, originalPayload)
    }

    func testNormalizedPhaseMapsStartMidpointAndCompletionForDifferentDurations() async throws {
        let analysis = try await SessionAnalysisPipeline().analyze(SessionAnalysisFixtureFactory.analysisInput(.fastestIsOutlier))
        let repA = analysis.analyzedReps[0]
        let repB = analysis.analyzedReps[9]
        let payloadA = try XCTUnwrap(SessionAnalysisPersistenceMapper.posePayload(for: repA, analysis: analysis))
        let payloadB = try XCTUnwrap(SessionAnalysisPersistenceMapper.posePayload(for: repB, analysis: analysis))
        let result = GhostComparisonBuilder(configuration: .resultsFixtureConfiguration)
            .compare(repA: repA, payloadA: payloadA, repB: repB, payloadB: payloadB)
        guard case .success(let comparison) = result else {
            return XCTFail("Expected comparison to be available, got \(result)")
        }
        let lookup = GhostPoseLookup()

        let startA = lookup.pose(at: 0, in: comparison.alignedRepA)
        let startB = lookup.pose(at: 0, in: comparison.alignedRepB)
        let middleA = lookup.pose(at: 0.5, in: comparison.alignedRepA)
        let middleB = lookup.pose(at: 0.5, in: comparison.alignedRepB)
        let endA = lookup.pose(at: 1, in: comparison.alignedRepA)
        let endB = lookup.pose(at: 1, in: comparison.alignedRepB)

        XCTAssertNotNil(startA)
        XCTAssertNotNil(startB)
        XCTAssertNotNil(middleA)
        XCTAssertNotNil(middleB)
        XCTAssertNotNil(endA)
        XCTAssertNotNil(endB)
        XCTAssertNotEqual(repA.segment.durationSeconds, repB.segment.durationSeconds)
        XCTAssertEqual(comparison.durationDifferenceSeconds, abs(repA.segment.durationSeconds - repB.segment.durationSeconds), accuracy: 0.0001)
    }

    func testGhostPlaybackSpeedAdvancesPhaseWithoutChangingDurations() async throws {
        let comparison = try await ghostComparison(.good10, lhsIndex: 0, rhsIndex: 1)
        var playback = GhostPlaybackModel(
            repAID: comparison.repA.id,
            repBID: comparison.repB.id,
            repADurationSeconds: comparison.repA.segment.durationSeconds,
            repBDurationSeconds: comparison.repB.segment.durationSeconds,
            alignedRepA: comparison.alignedRepA,
            alignedRepB: comparison.alignedRepB
        )

        playback.speed = .half
        playback.play()
        playback.advance(by: playback.comparisonDurationSeconds)

        XCTAssertEqual(playback.currentPhase, 0.5, accuracy: 0.0001)
        XCTAssertEqual(playback.repADurationSeconds, comparison.repA.segment.durationSeconds)
        XCTAssertEqual(playback.repBDurationSeconds, comparison.repB.segment.durationSeconds)
    }

    func testIncompatibleAnalysisVersionsAreBlocked() async throws {
        let analysis = try await SessionAnalysisPipeline().analyze(SessionAnalysisFixtureFactory.analysisInput(.good10))
        let repA = analysis.analyzedReps[0]
        let repB = repWithAnalysisVersion(analysis.analyzedReps[1], version: "0.9.0")
        let payloadA = try XCTUnwrap(SessionAnalysisPersistenceMapper.posePayload(for: repA, analysis: analysis))
        let payloadB = try XCTUnwrap(SessionAnalysisPersistenceMapper.posePayload(for: analysis.analyzedReps[1], analysis: analysis))

        let result = GhostComparisonBuilder(configuration: .resultsFixtureConfiguration)
            .compare(repA: repA, payloadA: payloadA, repB: repB, payloadB: payloadB)

        XCTAssertEqual(result, .failure(.incompatibleAnalysisVersion))
    }

    func testScrubUpdatesBothPoses() async throws {
        let comparison = try await ghostComparison(.good10, lhsIndex: 0, rhsIndex: 1)
        var playback = GhostPlaybackModel(
            repAID: comparison.repA.id,
            repBID: comparison.repB.id,
            repADurationSeconds: comparison.repA.segment.durationSeconds,
            repBDurationSeconds: comparison.repB.segment.durationSeconds,
            alignedRepA: comparison.alignedRepA,
            alignedRepB: comparison.alignedRepB
        )
        let lookup = GhostPoseLookup()

        playback.scrub(to: 0.5)

        XCTAssertEqual(playback.currentPhase, 0.5, accuracy: 0.0001)
        XCTAssertNotNil(lookup.pose(at: playback.currentPhase, in: playback.alignedRepA))
        XCTAssertNotNil(lookup.pose(at: playback.currentPhase, in: playback.alignedRepB))
    }

    func testCommonTransformKeepsIdenticalRepsOverlappingAndDivergentPathSeparated() async throws {
        let identical = try await ghostComparison(.good10, lhsIndex: 0, rhsIndex: 1)
        let mapper = GhostDisplayMapper(alignedRepA: identical.alignedRepA, alignedRepB: identical.alignedRepB)
        let lookup = GhostPoseLookup()
        let poseA = try XCTUnwrap(lookup.pose(at: 0.5, in: identical.alignedRepA))
        let poseB = try XCTUnwrap(lookup.pose(at: 0.5, in: identical.alignedRepB))
        let pointsA = GhostPlaybackRenderer.jointPoints(for: poseA, in: CGSize(width: 200, height: 200), mapper: mapper)
        let pointsB = GhostPlaybackRenderer.jointPoints(for: poseB, in: CGSize(width: 200, height: 200), mapper: mapper)

        XCTAssertEqual(pointsA[.rightWrist]?.x ?? -1, pointsB[.rightWrist]?.x ?? -2, accuracy: 0.0001)

        let divergent = try await ghostComparison(.oneOutlier, lhsIndex: 0, rhsIndex: 9)
        let divergentMapper = GhostDisplayMapper(alignedRepA: divergent.alignedRepA, alignedRepB: divergent.alignedRepB)
        let divergentA = try XCTUnwrap(lookup.pose(at: 0.5, in: divergent.alignedRepA))
        let divergentB = try XCTUnwrap(lookup.pose(at: 0.5, in: divergent.alignedRepB))
        let divergentPointsA = GhostPlaybackRenderer.jointPoints(for: divergentA, in: CGSize(width: 200, height: 200), mapper: divergentMapper)
        let divergentPointsB = GhostPlaybackRenderer.jointPoints(for: divergentB, in: CGSize(width: 200, height: 200), mapper: divergentMapper)

        XCTAssertNotEqual(divergentPointsA[.rightWrist]?.x, divergentPointsB[.rightWrist]?.x)
    }

    func testMissingJointDoesNotCreateFakeOverlaySegment() {
        let pose = GhostPlaybackPose(
            phase: 0.5,
            joints: [
                .rightShoulder: RepPlaybackJoint(jointID: .rightShoulder, x: 1, y: 1, confidence: 0.9),
                .rightElbow: RepPlaybackJoint(jointID: .rightElbow, x: 1, y: 2, confidence: 0.9)
            ]
        )
        let mapper = GhostDisplayMapper(bounds: CGRect(x: 0, y: 0, width: 2, height: 2))

        let segments = GhostPlaybackRenderer.skeletonSegments(for: pose, in: CGSize(width: 100, height: 100), mapper: mapper)

        XCTAssertTrue(segments.contains { $0.startJointID == .rightShoulder && $0.endJointID == .rightElbow })
        XCTAssertFalse(segments.contains { $0.startJointID == .rightElbow && $0.endJointID == .rightWrist })
    }

    private func ghostComparison(_ fixtureID: SessionAnalysisFixtureID, lhsIndex: Int, rhsIndex: Int) async throws -> GhostComparisonResult {
        let analysis = try await SessionAnalysisPipeline().analyze(SessionAnalysisFixtureFactory.analysisInput(fixtureID))
        let repA = analysis.analyzedReps[lhsIndex]
        let repB = analysis.analyzedReps[rhsIndex]
        let payloadA = try XCTUnwrap(SessionAnalysisPersistenceMapper.posePayload(for: repA, analysis: analysis))
        let payloadB = try XCTUnwrap(SessionAnalysisPersistenceMapper.posePayload(for: repB, analysis: analysis))
        let result = GhostComparisonBuilder(configuration: .resultsFixtureConfiguration)
            .compare(repA: repA, payloadA: payloadA, repB: repB, payloadB: payloadB)
        guard case .success(let comparison) = result else {
            throw NSError(domain: "GhostModePlaybackTests", code: 1)
        }
        return comparison
    }

    private func repWithAnalysisVersion(_ rep: AnalyzedRep, version: String) -> AnalyzedRep {
        let metrics = MovementMetricSet(
            duration: rep.metrics.duration,
            headDisplacement: rep.metrics.headDisplacement,
            shoulderDisplacement: rep.metrics.shoulderDisplacement,
            primaryWristPathLength: rep.metrics.primaryWristPathLength,
            wristPathDirectness: rep.metrics.wristPathDirectness,
            analysisVersion: version,
            configurationVersion: rep.metrics.configurationVersion
        )
        return AnalyzedRep(
            id: rep.id,
            sequenceIndex: rep.sequenceIndex,
            segment: rep.segment,
            metrics: metrics,
            metricDiagnostics: rep.metricDiagnostics,
            sourceRecordingID: rep.sourceRecordingID
        )
    }
}
