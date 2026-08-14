import DryFireVisionCore
import DryFireVisionTestFixtures
import SwiftData
import XCTest

@MainActor
final class RepReviewViewModelTests: XCTestCase {
    func testPersistedRepReviewLoadsPoseOnlyAfterRepositoryRecreation() async throws {
        let fixture = try RepReviewPersistenceFixture()
        defer { fixture.cleanup() }
        let analysis = try await SessionAnalysisPipeline().analyze(SessionAnalysisFixtureFactory.analysisInput(.good10))
        let savedID = try await fixture.repository.save(analysis)
        let reloadedRepository = fixture.makeRepository()
        let repID = try XCTUnwrap(analysis.representativeRepID)
        let viewModel = RepReviewViewModel(
            sessionID: savedID,
            repID: repID,
            sessionRepository: reloadedRepository,
            poseAssetStore: fixture.poseAssetStore
        )

        viewModel.load()
        let state = await waitForReviewState(viewModel)

        guard case .readyPoseOnly(let ready) = state else {
            return XCTFail("Expected pose-only review, got \(state)")
        }
        XCTAssertEqual(ready.metrics.repID, repID)
        XCTAssertEqual(ready.playback.repID, repID)
        XCTAssertFalse(ready.playback.orderedPoseSamples.isEmpty)
        XCTAssertEqual(ready.playback.currentTimeSeconds, 0)
        XCTAssertEqual(ready.primaryWristJointID, .rightWrist)
        let representativeDuration = try XCTUnwrap(SessionResultsViewModel(analysis: analysis).state.representativeRep?.durationText)
        XCTAssertEqual(ready.metrics.durationText, representativeDuration)
        XCTAssertNotNil(ready.videoUnavailableMessage)
    }

    func testPreviousNextNavigationUsesStableRepIDs() async throws {
        let fixture = try RepReviewPersistenceFixture()
        defer { fixture.cleanup() }
        let analysis = try await SessionAnalysisPipeline().analyze(SessionAnalysisFixtureFactory.analysisInput(.partial))
        let savedID = try await fixture.repository.save(analysis)
        let ordered = analysis.analyzedReps.sorted { $0.sequenceIndex < $1.sequenceIndex }
        let viewModel = RepReviewViewModel(
            sessionID: savedID,
            repID: ordered[1].id,
            sessionRepository: fixture.makeRepository(),
            poseAssetStore: fixture.poseAssetStore
        )

        viewModel.load()
        _ = await waitForReviewState(viewModel)
        viewModel.openNextRep()
        let nextState = await waitForReviewState(viewModel)

        guard case .readyPoseOnly(let ready) = nextState else {
            return XCTFail("Expected next pose-only review, got \(nextState)")
        }
        XCTAssertEqual(ready.metrics.repID, ordered[2].id)
        XCTAssertEqual(ready.metrics.repNumberText, "Rep \(ordered[2].sequenceIndex + 1)")
    }

    func testMissingPoseAssetKeepsMetricsAvailable() async throws {
        let fixture = try RepReviewPersistenceFixture()
        defer { fixture.cleanup() }
        let analysis = try await SessionAnalysisPipeline().analyze(SessionAnalysisFixtureFactory.analysisInput(.good10))
        let savedID = try await fixture.repository.save(analysis)
        let repID = try XCTUnwrap(analysis.representativeRepID)
        let reference = try XCTUnwrap(try await fixture.repository.poseAssetReference(sessionID: savedID, repID: repID))
        try await fixture.poseAssetStore.delete(storageLocation: reference.storageLocation)
        let viewModel = RepReviewViewModel(
            sessionID: savedID,
            repID: repID,
            sessionRepository: fixture.makeRepository(),
            poseAssetStore: fixture.poseAssetStore
        )

        viewModel.load()
        let state = await waitForReviewState(viewModel)

        guard case .poseUnavailable(let metrics, let reason) = state else {
            return XCTFail("Expected missing-pose degraded review, got \(state)")
        }
        XCTAssertEqual(reason, .missingPoseAsset)
        XCTAssertNotEqual(metrics.durationText, "Unavailable")
        XCTAssertEqual(metrics.repID, repID)
    }

    func testCorruptPoseAssetKeepsMetricsAvailable() async throws {
        let fixture = try RepReviewPersistenceFixture()
        defer { fixture.cleanup() }
        let analysis = try await SessionAnalysisPipeline().analyze(SessionAnalysisFixtureFactory.analysisInput(.good10))
        let savedID = try await fixture.repository.save(analysis)
        let repID = try XCTUnwrap(analysis.representativeRepID)
        let reference = try XCTUnwrap(try await fixture.repository.poseAssetReference(sessionID: savedID, repID: repID))
        try fixture.overwritePoseAsset(reference.storageLocation, contents: "not-json")
        let viewModel = RepReviewViewModel(
            sessionID: savedID,
            repID: repID,
            sessionRepository: fixture.makeRepository(),
            poseAssetStore: fixture.poseAssetStore
        )

        viewModel.load()
        let state = await waitForReviewState(viewModel)

        guard case .poseUnavailable(let metrics, let reason) = state else {
            return XCTFail("Expected corrupt-pose degraded review, got \(state)")
        }
        XCTAssertEqual(reason, .corruptPoseAsset)
        XCTAssertNotEqual(metrics.durationText, "Unavailable")
    }

    func testDegradedMetricDisplaysUnavailableWithoutBlockingPlayback() async throws {
        let fixture = try RepReviewPersistenceFixture()
        defer { fixture.cleanup() }
        let analysis = try await SessionAnalysisPipeline().analyze(SessionAnalysisFixtureFactory.analysisInput(.degradedMetric))
        let savedID = try await fixture.repository.save(analysis)
        let degradedRep = try XCTUnwrap(analysis.analyzedReps.first { $0.metrics.headDisplacement.availability == .unavailable })
        let viewModel = RepReviewViewModel(
            sessionID: savedID,
            repID: degradedRep.id,
            sessionRepository: fixture.makeRepository(),
            poseAssetStore: fixture.poseAssetStore
        )

        viewModel.load()
        let state = await waitForReviewState(viewModel)

        guard case .readyPoseOnly(let ready) = state else {
            return XCTFail("Expected degraded metric with playback, got \(state)")
        }
        XCTAssertEqual(ready.metrics.headDisplacementText, "Unavailable")
        XCTAssertFalse(ready.playback.orderedPoseSamples.isEmpty)
        XCTAssertEqual(ready.metrics.confidenceNote, "Some movement data unavailable.")
    }

    func testOutlierClassificationIsPreserved() async throws {
        let fixture = try RepReviewPersistenceFixture()
        defer { fixture.cleanup() }
        let analysis = try await SessionAnalysisPipeline().analyze(SessionAnalysisFixtureFactory.analysisInput(.fastestIsOutlier))
        let savedID = try await fixture.repository.save(analysis)
        let outlierID = try XCTUnwrap(analysis.movementOutlierRepIDs.first)
        let viewModel = RepReviewViewModel(
            sessionID: savedID,
            repID: outlierID,
            sessionRepository: fixture.makeRepository(),
            poseAssetStore: fixture.poseAssetStore
        )

        viewModel.load()
        let state = await waitForReviewState(viewModel)

        guard case .readyPoseOnly(let ready) = state else {
            return XCTFail("Expected outlier review, got \(state)")
        }
        XCTAssertTrue(ready.metrics.classificationLabels.contains("Movement Outlier"))
        XCTAssertTrue(ready.metrics.classificationLabels.contains("Fastest Rep"))
    }
}

@MainActor
private func waitForReviewState(
    _ viewModel: RepReviewViewModel,
    file: StaticString = #filePath,
    line: UInt = #line
) async -> RepReviewViewState {
    for _ in 0..<80 {
        switch viewModel.state {
        case .loading:
            await Task.yield()
        case .readyWithVideoAndPose, .readyPoseOnly, .readyMetricsOnly, .poseUnavailable, .playbackError, .failed:
            return viewModel.state
        }
    }
    XCTFail("Rep Review did not finish loading", file: file, line: line)
    return viewModel.state
}

private struct RepReviewPersistenceFixture {
    let modelContainer: ModelContainer
    let poseAssetStore: FilePoseAssetStore
    let rootURL: URL
    let repository: SwiftDataSessionRepository

    init() throws {
        let configuration = ModelConfiguration(
            schema: DryFireVisionPersistenceSchema.schema,
            isStoredInMemoryOnly: true
        )
        let modelContainer = try ModelContainer(
            for: DryFireVisionPersistenceSchema.schema,
            configurations: [configuration]
        )
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("DryFireVisionRepReviewTests-\(UUID().uuidString)", isDirectory: true)
        let poseAssetStore = FilePoseAssetStore(rootDirectory: rootURL)
        self.modelContainer = modelContainer
        self.poseAssetStore = poseAssetStore
        self.rootURL = rootURL
        self.repository = SwiftDataSessionRepository(modelContainer: modelContainer, poseAssetStore: poseAssetStore)
    }

    func makeRepository() -> SwiftDataSessionRepository {
        SwiftDataSessionRepository(modelContainer: modelContainer, poseAssetStore: poseAssetStore)
    }

    func overwritePoseAsset(_ storageLocation: String, contents: String) throws {
        let url = storageLocation.split(separator: "/").reduce(rootURL) { partial, component in
            partial.appendingPathComponent(String(component))
        }
        let data = try XCTUnwrap(contents.data(using: .utf8))
        try data.write(to: url, options: [.atomic])
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: rootURL)
    }
}
