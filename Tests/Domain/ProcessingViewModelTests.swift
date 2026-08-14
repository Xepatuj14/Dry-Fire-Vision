import DryFireVisionTestFixtures
import XCTest
@testable import DryFireVisionCore

@MainActor
final class ProcessingViewModelTests: XCTestCase {
    func testSuccessfulProcessingShowsPersistedAnalysisInsteadOfTransientAnalysis() async throws {
        let transient = try await SessionAnalysisPipeline().analyze(SessionAnalysisFixtureFactory.analysisInput(.good10))
        let persisted = copyAnalysis(transient, sourceRecording: nil)
        let analyzer = StubSessionAnalyzer(result: .success(transient))
        let repository = RecordingSessionRepository(fetchedAnalysis: persisted)
        let viewModel = ProcessingViewModel(
            sessionAnalyzer: analyzer,
            sessionRepository: repository,
            input: SessionAnalysisFixtureFactory.analysisInput(.good10)
        )

        viewModel.startAnalysisIfNeeded()
        let state = await waitForTerminalState(viewModel)

        guard case .complete(let analysis) = state else {
            return XCTFail("Expected complete state, got \(state)")
        }
        XCTAssertNil(analysis.sourceRecording)
        XCTAssertEqual(analysis.sessionID, transient.sessionID)
        XCTAssertEqual(await repository.saveCallCount, 1)
        XCTAssertEqual(viewModel.diagnostic?.persistedSessionID, transient.sessionID)
        XCTAssertNil(viewModel.diagnostic?.failureCategory)
    }

    func testPersistenceFailurePreservesInMemoryAnalysisForRetry() async throws {
        let transient = try await SessionAnalysisPipeline().analyze(SessionAnalysisFixtureFactory.analysisInput(.partial))
        let analyzer = StubSessionAnalyzer(result: .success(transient))
        let repository = RecordingSessionRepository(saveResults: [.failure(PersistenceError.sessionSaveFailed)])
        let viewModel = ProcessingViewModel(
            sessionAnalyzer: analyzer,
            sessionRepository: repository,
            input: SessionAnalysisFixtureFactory.analysisInput(.partial)
        )

        viewModel.startAnalysisIfNeeded()
        let state = await waitForTerminalState(viewModel)

        guard case .persistenceFailed(let failure) = state else {
            return XCTFail("Expected persistence failure, got \(state)")
        }
        XCTAssertEqual(failure.analysis, transient)
        XCTAssertEqual(await repository.saveCallCount, 1)
        XCTAssertEqual(viewModel.diagnostic?.failureCategory, .persistence)
        XCTAssertNil(viewModel.diagnostic?.persistedSessionID)
    }

    func testRetryPersistenceSavesPreservedAnalysisAndShowsFetchedResults() async throws {
        let transient = try await SessionAnalysisPipeline().analyze(SessionAnalysisFixtureFactory.analysisInput(.partial))
        let persisted = copyAnalysis(transient, sourceRecording: nil)
        let analyzer = StubSessionAnalyzer(result: .success(transient))
        let repository = RecordingSessionRepository(
            saveResults: [
                .failure(PersistenceError.sessionSaveFailed),
                .success(transient.sessionID)
            ],
            fetchedAnalysis: persisted
        )
        let viewModel = ProcessingViewModel(
            sessionAnalyzer: analyzer,
            sessionRepository: repository,
            input: SessionAnalysisFixtureFactory.analysisInput(.partial)
        )

        viewModel.startAnalysisIfNeeded()
        _ = await waitForTerminalState(viewModel)
        viewModel.retryPersistence()
        let state = await waitForTerminalState(viewModel)

        guard case .degraded(let analysis) = state else {
            return XCTFail("Expected degraded state after retry, got \(state)")
        }
        XCTAssertNil(analysis.sourceRecording)
        XCTAssertEqual(await repository.saveCallCount, 2)
        XCTAssertEqual(await analyzer.analyzeCallCount, 1)
        XCTAssertEqual(viewModel.diagnostic?.persistedSessionID, transient.sessionID)
    }

    func testAnalysisFailureDoesNotAttemptToPersist() async {
        let analyzer = StubSessionAnalyzer(result: .failure(SessionAnalysisError.insufficientPoseData))
        let repository = RecordingSessionRepository()
        let viewModel = ProcessingViewModel(
            sessionAnalyzer: analyzer,
            sessionRepository: repository,
            input: AnalysisInput(recording: nil)
        )

        viewModel.startAnalysisIfNeeded()
        let state = await waitForTerminalState(viewModel)

        guard case .failed(let failure) = state else {
            return XCTFail("Expected failed state, got \(state)")
        }
        XCTAssertEqual(failure.reason, .insufficientPoseData)
        XCTAssertEqual(await repository.saveCallCount, 0)
        XCTAssertNil(viewModel.diagnostic)
    }

    func testDuplicateStartDoesNotAnalyzeOrSaveTwice() async throws {
        let transient = try await SessionAnalysisPipeline().analyze(SessionAnalysisFixtureFactory.analysisInput(.good10))
        let persisted = copyAnalysis(transient, sourceRecording: nil)
        let analyzer = StubSessionAnalyzer(result: .success(transient))
        let repository = RecordingSessionRepository(fetchedAnalysis: persisted)
        let viewModel = ProcessingViewModel(
            sessionAnalyzer: analyzer,
            sessionRepository: repository,
            input: SessionAnalysisFixtureFactory.analysisInput(.good10)
        )

        viewModel.startAnalysisIfNeeded()
        viewModel.startAnalysisIfNeeded()
        _ = await waitForTerminalState(viewModel)

        XCTAssertEqual(await analyzer.analyzeCallCount, 1)
        XCTAssertEqual(await repository.saveCallCount, 1)
    }

    func testNoValidRepsStillPersistAndOpenDegradedResults() async throws {
        let transient = try await SessionAnalysisPipeline().analyze(SessionAnalysisFixtureFactory.analysisInput(.noValidReps))
        let persisted = copyAnalysis(transient, sourceRecording: nil)
        let analyzer = StubSessionAnalyzer(result: .success(transient))
        let repository = RecordingSessionRepository(fetchedAnalysis: persisted)
        let viewModel = ProcessingViewModel(
            sessionAnalyzer: analyzer,
            sessionRepository: repository,
            input: SessionAnalysisFixtureFactory.analysisInput(.noValidReps)
        )

        viewModel.startAnalysisIfNeeded()
        let state = await waitForTerminalState(viewModel)

        guard case .degraded(let analysis) = state else {
            return XCTFail("Expected degraded state, got \(state)")
        }
        XCTAssertEqual(analysis.status, .noValidReps)
        XCTAssertEqual(analysis.validRepCount, 0)
        XCTAssertEqual(await repository.saveCallCount, 1)
    }
}

private actor StubSessionAnalyzer: SessionAnalyzing {
    private let result: Result<SessionAnalysis, Error>
    private(set) var analyzeCallCount = 0

    init(result: Result<SessionAnalysis, Error>) {
        self.result = result
    }

    func analyze(_ input: AnalysisInput) async throws -> SessionAnalysis {
        analyzeCallCount += 1
        return try result.get()
    }
}

private actor RecordingSessionRepository: SessionRepository {
    private var saveResults: [Result<UUID, Error>]
    private let fetchedAnalysis: SessionAnalysis?
    private(set) var saveCallCount = 0

    init(
        saveResults: [Result<UUID, Error>] = [],
        fetchedAnalysis: SessionAnalysis? = nil
    ) {
        self.saveResults = saveResults
        self.fetchedAnalysis = fetchedAnalysis
    }

    func save(_ analysis: SessionAnalysis) async throws -> UUID {
        saveCallCount += 1
        if saveResults.isEmpty {
            return analysis.sessionID
        }
        return try saveResults.removeFirst().get()
    }

    func session(id: UUID) async throws -> TrainingSessionSnapshot {
        guard let fetchedAnalysis else {
            throw PersistenceError.sessionNotFound(id)
        }
        return TrainingSessionSnapshot(
            id: id,
            mode: fetchedAnalysis.mode,
            status: fetchedAnalysis.status,
            analysisVersion: fetchedAnalysis.analysisVersion,
            analysisConfigurationVersion: fetchedAnalysis.analysisConfigurationVersion,
            analysis: fetchedAnalysis,
            poseAssetAvailability: .available
        )
    }

    func poseAssetReference(sessionID: UUID, repID: UUID) async throws -> RepPoseAssetReference? {
        nil
    }

    func recentCompletedSessions(limit: Int) async throws -> [TrainingSessionSnapshot] {
        []
    }

    func deleteSession(id: UUID) async throws {}
}

@MainActor
private func waitForTerminalState(
    _ viewModel: ProcessingViewModel,
    file: StaticString = #filePath,
    line: UInt = #line
) async -> ProcessingViewState {
    for _ in 0..<30 {
        switch viewModel.state {
        case .complete, .degraded, .persistenceFailed, .failed:
            return viewModel.state
        case .preparing, .analyzing, .saving:
            await Task.yield()
        }
    }
    XCTFail("Processing did not reach a terminal state", file: file, line: line)
    return viewModel.state
}

private func copyAnalysis(
    _ analysis: SessionAnalysis,
    sourceRecording: PoseRecording?
) -> SessionAnalysis {
    SessionAnalysis(
        sessionID: analysis.sessionID,
        recordingID: analysis.recordingID,
        mode: analysis.mode,
        recordingStartTimestampSeconds: analysis.recordingStartTimestampSeconds,
        recordingEndTimestampSeconds: analysis.recordingEndTimestampSeconds,
        recordingMetadata: analysis.recordingMetadata,
        sourceRecording: sourceRecording,
        analysisVersion: analysis.analysisVersion,
        analysisConfigurationVersion: analysis.analysisConfigurationVersion,
        targetRepCount: analysis.targetRepCount,
        actualSegmentedRepCount: analysis.actualSegmentedRepCount,
        validRepCount: analysis.validRepCount,
        degradedRepCount: analysis.degradedRepCount,
        invalidRepCount: analysis.invalidRepCount,
        averageValidRepDurationSeconds: analysis.averageValidRepDurationSeconds,
        analyzedReps: analysis.analyzedReps,
        representativeRepID: analysis.representativeRepID,
        fastestRepID: analysis.fastestRepID,
        movementOutlierRepIDs: analysis.movementOutlierRepIDs,
        movementConsistency: analysis.movementConsistency,
        comparisonResult: analysis.comparisonResult,
        segmentationResult: analysis.segmentationResult,
        overallConfidence: analysis.overallConfidence,
        status: analysis.status,
        reasons: analysis.reasons,
        durationDiagnostics: analysis.durationDiagnostics
    )
}
