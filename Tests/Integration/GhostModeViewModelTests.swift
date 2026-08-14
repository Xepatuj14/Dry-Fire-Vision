import DryFireVisionCore
import DryFireVisionTestFixtures
import SwiftData
import XCTest

@MainActor
final class GhostModeViewModelTests: XCTestCase {
    func testPersistedGhostModeLoadsAfterRepositoryRecreation() async throws {
        let fixture = try GhostModePersistenceFixture()
        defer { fixture.cleanup() }
        let analysis = try await SessionAnalysisPipeline().analyze(SessionAnalysisFixtureFactory.analysisInput(.good10))
        let savedID = try await fixture.repository.save(analysis)
        let referenceID = try XCTUnwrap(analysis.representativeRepID)
        let repBID = try XCTUnwrap(analysis.analyzedReps.first { $0.id != referenceID }?.id)
        let viewModel = GhostModeViewModel(
            sessionID: savedID,
            referenceRepID: referenceID,
            sessionRepository: fixture.makeRepository(),
            poseAssetStore: fixture.poseAssetStore,
            builder: GhostComparisonBuilder(configuration: .resultsFixtureConfiguration)
        )

        viewModel.loadSelection()
        let selectionState = await waitForGhostState(viewModel)
        guard case .selectingRep(let selection) = selectionState else {
            return XCTFail("Expected selection, got \(selectionState)")
        }
        XCTAssertEqual(selection.reference.id, referenceID)
        XCTAssertFalse(selection.candidates.contains { $0.id == referenceID })
        XCTAssertTrue(selection.candidates.contains { $0.id == repBID && $0.isCompatible })

        viewModel.chooseCandidate(repID: repBID)
        let readyState = await waitForGhostState(viewModel)

        guard case .ready(let ready) = readyState else {
            return XCTFail("Expected ready Ghost Mode, got \(readyState)")
        }
        XCTAssertEqual(ready.playback.repAID, referenceID)
        XCTAssertEqual(ready.playback.repBID, repBID)
        XCTAssertEqual(ready.playback.timingMode, .normalizedPhase)
        XCTAssertNotNil(ready.currentPoseA)
        XCTAssertNotNil(ready.currentPoseB)
        XCTAssertEqual(ready.metrics.similarityText, "Movement Comparison Available")
        XCTAssertNotEqual(ready.metrics.durationDifferenceText, "Unavailable")
    }

    func testRepresentativeRepIsSuggestedWhenReferenceDiffers() async throws {
        let fixture = try GhostModePersistenceFixture()
        defer { fixture.cleanup() }
        let analysis = try await SessionAnalysisPipeline().analyze(SessionAnalysisFixtureFactory.analysisInput(.fastestIsOutlier))
        let savedID = try await fixture.repository.save(analysis)
        let referenceID = try XCTUnwrap(analysis.fastestRepID)
        let representativeID = try XCTUnwrap(analysis.representativeRepID)
        let viewModel = GhostModeViewModel(
            sessionID: savedID,
            referenceRepID: referenceID,
            sessionRepository: fixture.makeRepository(),
            poseAssetStore: fixture.poseAssetStore,
            builder: GhostComparisonBuilder(configuration: .resultsFixtureConfiguration)
        )

        viewModel.loadSelection()
        let state = await waitForGhostState(viewModel)

        guard case .selectingRep(let selection) = state else {
            return XCTFail("Expected selection, got \(state)")
        }
        XCTAssertTrue(selection.candidates.contains { $0.id == representativeID && $0.isRepresentativeSuggestion })
        XCTAssertFalse(selection.reference.classificationLabels.contains("Representative Rep"))
    }

    func testMissingPoseAssetMarksCandidateUnavailableWithoutDeletingMetrics() async throws {
        let fixture = try GhostModePersistenceFixture()
        defer { fixture.cleanup() }
        let analysis = try await SessionAnalysisPipeline().analyze(SessionAnalysisFixtureFactory.analysisInput(.good10))
        let savedID = try await fixture.repository.save(analysis)
        let referenceID = try XCTUnwrap(analysis.representativeRepID)
        let repBID = try XCTUnwrap(analysis.analyzedReps.first { $0.id != referenceID }?.id)
        let reference = try XCTUnwrap(try await fixture.repository.poseAssetReference(sessionID: savedID, repID: repBID))
        try await fixture.poseAssetStore.delete(storageLocation: reference.storageLocation)
        let viewModel = GhostModeViewModel(
            sessionID: savedID,
            referenceRepID: referenceID,
            sessionRepository: fixture.makeRepository(),
            poseAssetStore: fixture.poseAssetStore,
            builder: GhostComparisonBuilder(configuration: .resultsFixtureConfiguration)
        )

        viewModel.loadSelection()
        let state = await waitForGhostState(viewModel)

        guard case .selectingRep(let selection) = state else {
            return XCTFail("Expected selection, got \(state)")
        }
        let candidate = try XCTUnwrap(selection.candidates.first { $0.id == repBID })
        XCTAssertFalse(candidate.isCompatible)
        XCTAssertEqual(candidate.compatibilityText, "Missing pose data")
        let snapshot = try await fixture.makeRepository().session(id: savedID)
        XCTAssertEqual(snapshot.analysis?.validRepCount, analysis.validRepCount)
    }

    func testCorruptPoseAssetFailsGracefullyDuringPreparation() async throws {
        let fixture = try GhostModePersistenceFixture()
        defer { fixture.cleanup() }
        let analysis = try await SessionAnalysisPipeline().analyze(SessionAnalysisFixtureFactory.analysisInput(.good10))
        let savedID = try await fixture.repository.save(analysis)
        let referenceID = try XCTUnwrap(analysis.representativeRepID)
        let repBID = try XCTUnwrap(analysis.analyzedReps.first { $0.id != referenceID }?.id)
        let reference = try XCTUnwrap(try await fixture.repository.poseAssetReference(sessionID: savedID, repID: repBID))
        try fixture.overwritePoseAsset(reference.storageLocation, contents: "not-json")
        let viewModel = GhostModeViewModel(
            sessionID: savedID,
            referenceRepID: referenceID,
            sessionRepository: fixture.makeRepository(),
            poseAssetStore: fixture.poseAssetStore,
            builder: GhostComparisonBuilder(configuration: .resultsFixtureConfiguration)
        )

        viewModel.loadSelection()
        let selectionState = await waitForGhostState(viewModel)
        guard case .selectingRep(let selection) = selectionState else {
            return XCTFail("Expected selection, got \(selectionState)")
        }
        XCTAssertTrue(selection.candidates.contains { $0.id == repBID && $0.isCompatible })

        viewModel.chooseCandidate(repID: repBID)
        let state = await waitForGhostState(viewModel)

        guard case .insufficientData(let unavailable) = state else {
            return XCTFail("Expected corrupt asset insufficient-data state, got \(state)")
        }
        XCTAssertEqual(unavailable.message, "One saved pose asset could not be decoded.")
    }

    func testPlaybackControlsUpdateBothCurrentPosesWithoutChangingMetrics() async throws {
        let fixture = try GhostModePersistenceFixture()
        defer { fixture.cleanup() }
        let analysis = try await SessionAnalysisPipeline().analyze(SessionAnalysisFixtureFactory.analysisInput(.good10))
        let savedID = try await fixture.repository.save(analysis)
        let referenceID = try XCTUnwrap(analysis.representativeRepID)
        let repBID = try XCTUnwrap(analysis.analyzedReps.first { $0.id != referenceID }?.id)
        let viewModel = GhostModeViewModel(
            sessionID: savedID,
            referenceRepID: referenceID,
            sessionRepository: fixture.makeRepository(),
            poseAssetStore: fixture.poseAssetStore,
            builder: GhostComparisonBuilder(configuration: .resultsFixtureConfiguration)
        )

        viewModel.loadSelection()
        _ = await waitForGhostState(viewModel)
        viewModel.chooseCandidate(repID: repBID)
        let initialState = await waitForGhostState(viewModel)
        guard case .ready(let initialReady) = initialState else {
            return XCTFail("Expected ready state, got \(initialState)")
        }

        viewModel.setPlaybackSpeed(.half)
        viewModel.scrub(to: 0.5)
        let scrubbedState = await waitForGhostState(viewModel)

        guard case .ready(let scrubbedReady) = scrubbedState else {
            return XCTFail("Expected scrubbed ready state, got \(scrubbedState)")
        }
        XCTAssertEqual(scrubbedReady.playback.currentPhase, 0.5, accuracy: 0.0001)
        XCTAssertNotNil(scrubbedReady.currentPoseA)
        XCTAssertNotNil(scrubbedReady.currentPoseB)
        XCTAssertEqual(scrubbedReady.metrics.repADurationText, initialReady.metrics.repADurationText)
        XCTAssertEqual(scrubbedReady.metrics.repBDurationText, initialReady.metrics.repBDurationText)
    }
}

@MainActor
private func waitForGhostState(
    _ viewModel: GhostModeViewModel,
    file: StaticString = #filePath,
    line: UInt = #line
) async -> GhostModeViewState {
    for _ in 0..<100 {
        switch viewModel.state {
        case .loading, .preparingComparison:
            await Task.yield()
        case .selectingRep, .ready, .incompatible, .insufficientData, .failed:
            return viewModel.state
        }
    }
    XCTFail("Ghost Mode did not reach an expected state", file: file, line: line)
    return viewModel.state
}

private struct GhostModePersistenceFixture {
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
            .appendingPathComponent("DryFireVisionGhostModeTests-\(UUID().uuidString)", isDirectory: true)
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
