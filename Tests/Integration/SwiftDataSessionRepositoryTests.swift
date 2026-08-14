import DryFireVisionCore
import DryFireVisionTestFixtures
import SwiftData
import XCTest

final class SwiftDataSessionRepositoryTests: XCTestCase {
    func testEmptyStoreReturnsNoRecentSessions() async throws {
        let fixture = try PersistenceTestFixture()
        defer { fixture.cleanup() }

        let recent = try await fixture.repository.recentCompletedSessions(limit: 20)

        XCTAssertTrue(recent.isEmpty)
    }

    func testCompletedSessionRoundTripReconstructsResultsWithoutReanalysis() async throws {
        let fixture = try PersistenceTestFixture()
        defer { fixture.cleanup() }
        let analysis = try await SessionAnalysisPipeline().analyze(SessionAnalysisFixtureFactory.analysisInput(.good10))
        let originalState = SessionResultsViewModel(analysis: analysis).state

        let savedID = try await fixture.repository.save(analysis)
        let reloadedRepository = fixture.makeRepository()
        let snapshot = try await reloadedRepository.session(id: savedID)
        let reloadedAnalysis = try XCTUnwrap(snapshot.analysis)
        let reloadedState = SessionResultsViewModel(analysis: reloadedAnalysis).state

        XCTAssertEqual(savedID, analysis.sessionID)
        XCTAssertEqual(snapshot.poseAssetAvailability, .available)
        XCTAssertEqual(reloadedAnalysis.validRepCount, analysis.validRepCount)
        XCTAssertEqual(reloadedAnalysis.averageValidRepDurationSeconds, analysis.averageValidRepDurationSeconds)
        XCTAssertEqual(reloadedAnalysis.representativeRepID, analysis.representativeRepID)
        XCTAssertEqual(reloadedAnalysis.fastestRepID, analysis.fastestRepID)
        XCTAssertEqual(reloadedAnalysis.movementOutlierRepIDs, analysis.movementOutlierRepIDs)
        XCTAssertEqual(reloadedAnalysis.analysisVersion, analysis.analysisVersion)
        XCTAssertEqual(reloadedAnalysis.analysisConfigurationVersion, analysis.analysisConfigurationVersion)
        XCTAssertEqual(reloadedState.repCountText, originalState.repCountText)
        XCTAssertEqual(reloadedState.averageDurationText, originalState.averageDurationText)
        XCTAssertEqual(reloadedState.representativeRep?.repNumberText, originalState.representativeRep?.repNumberText)
        XCTAssertEqual(reloadedState.fastestRep?.repNumberText, originalState.fastestRep?.repNumberText)
    }

    func testUnavailableMetricRemainsNilAndUnavailableAfterRoundTrip() async throws {
        let fixture = try PersistenceTestFixture()
        defer { fixture.cleanup() }
        let analysis = try await SessionAnalysisPipeline().analyze(SessionAnalysisFixtureFactory.analysisInput(.degradedMetric))

        let savedID = try await fixture.repository.save(analysis)
        let snapshot = try await fixture.makeRepository().session(id: savedID)
        let reloaded = try XCTUnwrap(snapshot.analysis)

        XCTAssertTrue(reloaded.analyzedReps.contains { rep in
            rep.metrics.headDisplacement.availability == .unavailable &&
                rep.metrics.headDisplacement.value == nil
        })
        XCTAssertFalse(reloaded.analyzedReps.contains { $0.metrics.headDisplacement.value == 0 })
        XCTAssertEqual(SessionResultsViewModel(analysis: reloaded).state.displayState, .degraded)
    }

    func testRepresentativeFastestAndOutlierFlagsSurviveRoundTrip() async throws {
        let fixture = try PersistenceTestFixture()
        defer { fixture.cleanup() }
        let analysis = try await SessionAnalysisPipeline().analyze(SessionAnalysisFixtureFactory.analysisInput(.fastestIsOutlier))

        let savedID = try await fixture.repository.save(analysis)
        let reloaded = try XCTUnwrap(try await fixture.makeRepository().session(id: savedID).analysis)
        let state = SessionResultsViewModel(analysis: reloaded).state

        XCTAssertEqual(state.fastestRep?.repNumberText, "Rep 10")
        XCTAssertTrue(state.repRows[9].badges.contains("Fastest"))
        XCTAssertTrue(state.repRows[9].badges.contains("Outlier"))
    }

    func testPoseAssetReferenceResolvesAfterRepositoryRecreation() async throws {
        let fixture = try PersistenceTestFixture()
        defer { fixture.cleanup() }
        let analysis = try await SessionAnalysisPipeline().analyze(SessionAnalysisFixtureFactory.analysisInput(.partial))

        let savedID = try await fixture.repository.save(analysis)
        let poseAsset = try fixture.firstPoseAsset(sessionID: savedID)
        let payload = try await fixture.poseAssetStore.load(storageLocation: poseAsset.storageLocation)

        XCTAssertFalse(payload.frames.isEmpty)
        XCTAssertEqual(payload.encodingVersion, VersionCatalog.current.poseEncodingVersion)
        XCTAssertEqual(payload.coordinateConventionVersion, VersionCatalog.current.coordinateConventionVersion)
        XCTAssertEqual(payload.jointSetVersion, VersionCatalog.current.jointSetVersion)
    }

    func testMissingPoseAssetDoesNotInvalidateSavedResults() async throws {
        let fixture = try PersistenceTestFixture()
        defer { fixture.cleanup() }
        let analysis = try await SessionAnalysisPipeline().analyze(SessionAnalysisFixtureFactory.analysisInput(.good10))

        let savedID = try await fixture.repository.save(analysis)
        let poseAsset = try fixture.firstPoseAsset(sessionID: savedID)
        try await fixture.poseAssetStore.delete(storageLocation: poseAsset.storageLocation)
        let snapshot = try await fixture.makeRepository().session(id: savedID)

        XCTAssertEqual(snapshot.poseAssetAvailability, .missing)
        XCTAssertNotNil(snapshot.analysis)
        XCTAssertEqual(snapshot.analysis?.validRepCount, 10)
    }

    func testCorruptPosePayloadProducesTypedReadErrorWithoutDeletingSession() async throws {
        let fixture = try PersistenceTestFixture()
        defer { fixture.cleanup() }
        let analysis = try await SessionAnalysisPipeline().analyze(SessionAnalysisFixtureFactory.analysisInput(.good10))

        let savedID = try await fixture.repository.save(analysis)
        let poseAsset = try fixture.firstPoseAsset(sessionID: savedID)
        try fixture.overwritePoseAsset(poseAsset.storageLocation, contents: "not-json")

        await XCTAssertThrowsErrorAsync({
            try await fixture.poseAssetStore.load(storageLocation: poseAsset.storageLocation)
        }) { error in
            XCTAssertEqual(error as? PersistenceError, .poseAssetReadFailed)
        }
        let snapshot = try await fixture.makeRepository().session(id: savedID)
        XCTAssertEqual(snapshot.poseAssetAvailability, .corrupt)
        XCTAssertNotNil(snapshot.analysis)
    }

    func testDeleteCascadesRecordsAndPoseFilesAndIsIdempotent() async throws {
        let fixture = try PersistenceTestFixture()
        defer { fixture.cleanup() }
        let analysis = try await SessionAnalysisPipeline().analyze(SessionAnalysisFixtureFactory.analysisInput(.oneOutlier))

        let savedID = try await fixture.repository.save(analysis)
        let poseAsset = try fixture.firstPoseAsset(sessionID: savedID)

        try await fixture.repository.deleteSession(id: savedID)
        try await fixture.repository.deleteSession(id: savedID)

        XCTAssertFalse(await fixture.poseAssetStore.exists(storageLocation: poseAsset.storageLocation))
        await XCTAssertThrowsErrorAsync({
            try await fixture.repository.session(id: savedID)
        }) { error in
            XCTAssertEqual(error as? PersistenceError, .sessionNotFound(savedID))
        }
    }

    func testRecentCompletedSessionsReturnsNewestFirstAndExcludesFailed() async throws {
        let fixture = try PersistenceTestFixture()
        defer { fixture.cleanup() }
        let older = try await SessionAnalysisPipeline().analyze(SessionAnalysisFixtureFactory.analysisInput(.good10))
        let newer = try shiftedAnalysis(
            try await SessionAnalysisPipeline().analyze(SessionAnalysisFixtureFactory.analysisInput(.partial)),
            seconds: 100
        )

        _ = try await fixture.repository.save(older)
        _ = try await fixture.repository.save(newer)
        let recent = try await fixture.repository.recentCompletedSessions(limit: 20)

        XCTAssertEqual(recent.map(\.id), [newer.sessionID, older.sessionID])
    }

    func testInvalidRepresentativeReferenceFailsIntegrityCheck() async throws {
        let fixture = try PersistenceTestFixture()
        defer { fixture.cleanup() }
        let analysis = try await shiftedAnalysis(
            try await SessionAnalysisPipeline().analyze(SessionAnalysisFixtureFactory.analysisInput(.good10)),
            representativeRepID: UUID()
        )

        await XCTAssertThrowsErrorAsync({
            try await fixture.repository.save(analysis)
        }) { error in
            XCTAssertEqual(error as? PersistenceError, .integrityViolation(.representativeRepOutsideSession))
        }
    }

    @MainActor
    func testRealRecordingProcessingFlowPersistsAndDisplaysFetchedResults() async throws {
        let fixture = try PersistenceTestFixture()
        defer { fixture.cleanup() }
        let recording = SessionAnalysisFixtureFactory.recording(.good10)
        let input = AnalysisInput(
            recording: recording,
            targetRepCount: 10,
            configuration: .resultsFixtureConfiguration
        )
        let viewModel = ProcessingViewModel(
            sessionAnalyzer: SessionAnalysisPipeline(),
            sessionRepository: fixture.repository,
            input: input
        )

        viewModel.startAnalysisIfNeeded()
        let state = await waitForTerminalState(viewModel)

        guard case .complete(let analysis) = state else {
            return XCTFail("Expected completed persisted results, got \(state)")
        }
        XCTAssertEqual(analysis.sessionID, recording.id)
        XCTAssertEqual(analysis.recordingID, recording.id)
        XCTAssertNil(analysis.sourceRecording)
        XCTAssertEqual(SessionResultsViewModel(analysis: analysis).state.repCountText, "10 reps")
        let snapshot = try await fixture.makeRepository().session(id: recording.id)
        XCTAssertEqual(snapshot.poseAssetAvailability, .available)
        XCTAssertEqual(snapshot.analysis?.validRepCount, 10)
    }

    func testAnalyzeAndDeleteWithNoDurableVideoRecordsNotRecordedTruthfully() async throws {
        let fixture = try PersistenceTestFixture()
        defer { fixture.cleanup() }
        let analysis = try await SessionAnalysisPipeline().analyze(SessionAnalysisFixtureFactory.analysisInput(.good10))

        let savedID = try await fixture.repository.save(
            analysis,
            videoRetentionPreference: .analyzeAndDelete,
            rawVideo: nil
        )
        let snapshot = try await fixture.repository.session(id: savedID)

        XCTAssertEqual(snapshot.videoRetentionState, .notRecorded)
        XCTAssertEqual(snapshot.videoMediaAvailability, .notRecorded)
        XCTAssertEqual(snapshot.poseAssetAvailability, .available)
        XCTAssertEqual(snapshot.analysis?.validRepCount, 10)
    }

    func testAnalyzeAndDeleteDeletesOnlyAfterPersistingDerivedData() async throws {
        let fixture = try PersistenceTestFixture()
        defer { fixture.cleanup() }
        let analysis = try await SessionAnalysisPipeline().analyze(SessionAnalysisFixtureFactory.analysisInput(.good10))
        let rawVideo = try fixture.createRawVideo(sessionID: analysis.sessionID)

        let savedID = try await fixture.repository.save(
            analysis,
            videoRetentionPreference: .analyzeAndDelete,
            rawVideo: rawVideo
        )
        let snapshot = try await fixture.repository.session(id: savedID)

        XCTAssertEqual(snapshot.videoRetentionState, .deleted)
        XCTAssertEqual(snapshot.videoMediaAvailability, .videoDeletedByPreference)
        XCTAssertFalse(try await fixture.mediaAssetStore.exists(rawVideo))
        XCTAssertEqual(snapshot.poseAssetAvailability, .available)
        XCTAssertEqual(snapshot.analysis?.validRepCount, 10)
    }

    func testKeepVideoRetainsOwnedMedia() async throws {
        let fixture = try PersistenceTestFixture()
        defer { fixture.cleanup() }
        let analysis = try await SessionAnalysisPipeline().analyze(SessionAnalysisFixtureFactory.analysisInput(.partial))
        let rawVideo = try fixture.createRawVideo(sessionID: analysis.sessionID)

        let savedID = try await fixture.repository.save(
            analysis,
            videoRetentionPreference: .keep,
            rawVideo: rawVideo
        )
        let snapshot = try await fixture.repository.session(id: savedID)

        XCTAssertEqual(snapshot.videoRetentionState, .keep)
        XCTAssertEqual(snapshot.videoMediaAvailability, .videoAvailable)
        XCTAssertTrue(try await fixture.mediaAssetStore.exists(rawVideo))
    }

    func testMediaDeleteFailureMarksDeletionFailedAndMaintenanceRetries() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("DryFireVisionPersistenceTests-\(UUID().uuidString)", isDirectory: true)
        let mediaStore = FailingOnceMediaAssetStore(rootURL: rootURL)
        let fixture = try PersistenceTestFixture(rootURL: rootURL, mediaAssetStore: mediaStore)
        defer { fixture.cleanup() }
        let analysis = try await SessionAnalysisPipeline().analyze(SessionAnalysisFixtureFactory.analysisInput(.good10))
        let rawVideo = try fixture.createRawVideo(sessionID: analysis.sessionID)
        await mediaStore.failNextDelete()

        let savedID = try await fixture.repository.save(
            analysis,
            videoRetentionPreference: .analyzeAndDelete,
            rawVideo: rawVideo
        )
        var snapshot = try await fixture.repository.session(id: savedID)
        XCTAssertEqual(snapshot.videoRetentionState, .deletionFailed)
        XCTAssertEqual(snapshot.videoMediaAvailability, .videoDeletionFailed)
        XCTAssertTrue(try await fixture.mediaAssetStore.exists(rawVideo))

        _ = try await fixture.repository.performMaintenance()
        snapshot = try await fixture.repository.session(id: savedID)
        XCTAssertEqual(snapshot.videoRetentionState, .deleted)
        XCTAssertFalse(try await fixture.mediaAssetStore.exists(rawVideo))
    }

    func testPendingDeleteAlreadyAbsentReconcilesToDeletedDuringMaintenance() async throws {
        let fixture = try PersistenceTestFixture()
        defer { fixture.cleanup() }
        let analysis = try await SessionAnalysisPipeline().analyze(SessionAnalysisFixtureFactory.analysisInput(.good10))
        let rawVideo = try fixture.createRawVideo(sessionID: analysis.sessionID)
        _ = try await fixture.repository.save(analysis, videoRetentionPreference: .keep, rawVideo: rawVideo)
        try await fixture.mediaAssetStore.delete(rawVideo)
        try fixture.setVideoRetentionState(.pendingDelete, sessionID: analysis.sessionID, relativePath: rawVideo.relativePath)

        _ = try await fixture.repository.performMaintenance()
        let snapshot = try await fixture.repository.session(id: analysis.sessionID)

        XCTAssertEqual(snapshot.videoRetentionState, .deleted)
        XCTAssertEqual(snapshot.videoMediaAvailability, .videoDeletedByPreference)
    }

    func testMissingKeptMediaDegradesAvailabilityWithoutDeletingSession() async throws {
        let fixture = try PersistenceTestFixture()
        defer { fixture.cleanup() }
        let analysis = try await SessionAnalysisPipeline().analyze(SessionAnalysisFixtureFactory.analysisInput(.partial))
        let rawVideo = try fixture.createRawVideo(sessionID: analysis.sessionID)
        let savedID = try await fixture.repository.save(analysis, videoRetentionPreference: .keep, rawVideo: rawVideo)
        try await fixture.mediaAssetStore.delete(rawVideo)

        let snapshot = try await fixture.repository.session(id: savedID)

        XCTAssertEqual(snapshot.videoRetentionState, .keep)
        XCTAssertEqual(snapshot.videoMediaAvailability, .videoMissing)
        XCTAssertNotNil(snapshot.analysis)
    }

    func testMediaPathTraversalIsRejectedAndDoesNotDeleteUnrelatedFile() async throws {
        let fixture = try PersistenceTestFixture()
        defer { fixture.cleanup() }
        let sessionID = UUID()
        let unrelated = fixture.rootURL.appendingPathComponent("unrelated.mov")
        try Data("keep".utf8).write(to: unrelated)
        let malicious = AppOwnedMediaAssetReference(
            sessionID: sessionID,
            relativePath: "Media/Sessions/\(sessionID.uuidString)/../unrelated.mov"
        )

        await XCTAssertThrowsErrorAsync({
            try await fixture.mediaAssetStore.delete(malicious)
        }) { error in
            XCTAssertEqual(error as? PersistenceError, .integrityViolation(.invalidMediaAssetReference))
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: unrelated.path))
    }

    func testPoseAssetWriteFailureRetainsRawVideoAndDoesNotPersistSession() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("DryFireVisionPoseFailureTests-\(UUID().uuidString)", isDirectory: true)
        let fixture = try PersistenceTestFixture(
            rootURL: rootURL,
            poseAssetStore: FailingPoseAssetStore(),
            mediaAssetStore: FileMediaAssetStore(rootDirectory: rootURL)
        )
        defer { fixture.cleanup() }
        let analysis = try await SessionAnalysisPipeline().analyze(SessionAnalysisFixtureFactory.analysisInput(.good10))
        let rawVideo = try fixture.createRawVideo(sessionID: analysis.sessionID)

        await XCTAssertThrowsErrorAsync({
            try await fixture.repository.save(
                analysis,
                videoRetentionPreference: .analyzeAndDelete,
                rawVideo: rawVideo
            )
        }) { error in
            XCTAssertEqual(error as? PersistenceError, .poseAssetWriteFailed)
        }
        XCTAssertTrue(try await fixture.mediaAssetStore.exists(rawVideo))
        await XCTAssertThrowsErrorAsync({
            try await fixture.repository.session(id: analysis.sessionID)
        }) { error in
            XCTAssertEqual(error as? PersistenceError, .sessionNotFound(analysis.sessionID))
        }
    }

    func testPersistenceIntegrityFailureRetainsRawVideoAndDoesNotClaimDeletion() async throws {
        let fixture = try PersistenceTestFixture()
        defer { fixture.cleanup() }
        let analysis = try await shiftedAnalysis(
            try await SessionAnalysisPipeline().analyze(SessionAnalysisFixtureFactory.analysisInput(.good10)),
            representativeRepID: UUID()
        )
        let rawVideo = try fixture.createRawVideo(sessionID: analysis.sessionID)

        await XCTAssertThrowsErrorAsync({
            try await fixture.repository.save(
                analysis,
                videoRetentionPreference: .analyzeAndDelete,
                rawVideo: rawVideo
            )
        }) { error in
            XCTAssertEqual(error as? PersistenceError, .integrityViolation(.representativeRepOutsideSession))
        }
        XCTAssertTrue(try await fixture.mediaAssetStore.exists(rawVideo))
        await XCTAssertThrowsErrorAsync({
            try await fixture.repository.session(id: analysis.sessionID)
        }) { error in
            XCTAssertEqual(error as? PersistenceError, .sessionNotFound(analysis.sessionID))
        }
    }

    func testFullSessionDeleteIsSafeAfterAnalyzeAndDeleteAlreadyRemovedVideo() async throws {
        let fixture = try PersistenceTestFixture()
        defer { fixture.cleanup() }
        let analysis = try await SessionAnalysisPipeline().analyze(SessionAnalysisFixtureFactory.analysisInput(.oneOutlier))
        let rawVideo = try fixture.createRawVideo(sessionID: analysis.sessionID)
        let savedID = try await fixture.repository.save(
            analysis,
            videoRetentionPreference: .analyzeAndDelete,
            rawVideo: rawVideo
        )

        try await fixture.repository.deleteSession(id: savedID)
        try await fixture.repository.deleteSession(id: savedID)

        XCTAssertFalse(try await fixture.mediaAssetStore.exists(rawVideo))
        await XCTAssertThrowsErrorAsync({
            try await fixture.repository.session(id: savedID)
        }) { error in
            XCTAssertEqual(error as? PersistenceError, .sessionNotFound(savedID))
        }
    }

    func testMaintenanceConservativelyMarksStrandedCapturingAndProcessing() async throws {
        let fixture = try PersistenceTestFixture()
        defer { fixture.cleanup() }
        let capturingID = UUID()
        let processingID = UUID()
        try fixture.insertBareSession(id: capturingID, status: .capturing)
        try fixture.insertBareSession(id: processingID, status: .processing)

        let report = try await fixture.repository.performMaintenance()

        XCTAssertEqual(report.strandedCapturingSessions, 1)
        XCTAssertEqual(report.strandedProcessingSessions, 1)
        XCTAssertEqual(try fixture.persistedSessionStatus(capturingID), .cancelled)
        XCTAssertEqual(try fixture.persistedSessionStatus(processingID), .failed)
    }

    func testLiveFireSessionPersistsEventsAndRecoveryPoseAssetsSeparatelyFromDryFire() async throws {
        let fixture = try PersistenceTestFixture()
        defer { fixture.cleanup() }
        let liveAnalysis = LiveFireSessionAnalyzer().analyze(LiveFireSyntheticFixtures.input(.clean5))

        let savedID = try await fixture.repository.saveLiveFire(
            liveAnalysis,
            videoRetentionPreference: .keep,
            rawVideo: nil
        )
        let reloaded = try await fixture.repository.liveFireSession(id: savedID)
        let snapshot = try await fixture.repository.session(id: savedID)

        XCTAssertEqual(reloaded.acceptedEventCount, 5)
        XCTAssertEqual(reloaded.events.map(\.status), Array(repeating: .accepted, count: 5))
        XCTAssertEqual(reloaded.events.map(\.id), liveAnalysis.events.map(\.id))
        XCTAssertEqual(reloaded.recoveryConsistency.availability, liveAnalysis.recoveryConsistency.availability)
        XCTAssertEqual(
            try XCTUnwrap(reloaded.recoveryConsistency.internalValue),
            try XCTUnwrap(liveAnalysis.recoveryConsistency.internalValue),
            accuracy: 0.000_001
        )
        XCTAssertEqual(snapshot.mode, .liveFireBeta)
        XCTAssertEqual(snapshot.analysis?.mode, .liveFireBeta)
        XCTAssertNil(snapshot.analysis?.averageValidRepDurationSeconds)
        XCTAssertEqual(try fixture.poseAssetCount(sessionID: savedID, type: .recoveryWindow), 5)
    }

    private func shiftedAnalysis(
        _ analysis: SessionAnalysis,
        seconds: Double = 0,
        representativeRepID: UUID? = nil
    ) throws -> SessionAnalysis {
        SessionAnalysis(
            sessionID: analysis.sessionID,
            recordingID: analysis.recordingID,
            mode: analysis.mode,
            recordingStartTimestampSeconds: analysis.recordingStartTimestampSeconds.map { $0 + seconds },
            recordingEndTimestampSeconds: analysis.recordingEndTimestampSeconds.map { $0 + seconds },
            recordingMetadata: analysis.recordingMetadata,
            sourceRecording: analysis.sourceRecording,
            analysisVersion: analysis.analysisVersion,
            analysisConfigurationVersion: analysis.analysisConfigurationVersion,
            targetRepCount: analysis.targetRepCount,
            actualSegmentedRepCount: analysis.actualSegmentedRepCount,
            validRepCount: analysis.validRepCount,
            degradedRepCount: analysis.degradedRepCount,
            invalidRepCount: analysis.invalidRepCount,
            averageValidRepDurationSeconds: analysis.averageValidRepDurationSeconds,
            analyzedReps: analysis.analyzedReps,
            representativeRepID: representativeRepID ?? analysis.representativeRepID,
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
}

@MainActor
private func waitForTerminalState(
    _ viewModel: ProcessingViewModel,
    file: StaticString = #filePath,
    line: UInt = #line
) async -> ProcessingViewState {
    for _ in 0..<50 {
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

private struct PersistenceTestFixture {
    let modelContainer: ModelContainer
    let poseAssetStore: any PoseAssetStoring
    let mediaAssetStore: any MediaAssetStoring
    let rootURL: URL
    let repository: SwiftDataSessionRepository

    init(
        rootURL overrideRootURL: URL? = nil,
        poseAssetStore overridePoseAssetStore: (any PoseAssetStoring)? = nil,
        mediaAssetStore overrideMediaAssetStore: (any MediaAssetStoring)? = nil
    ) throws {
        let configuration = ModelConfiguration(
            schema: DryFireVisionPersistenceSchema.schema,
            isStoredInMemoryOnly: true
        )
        let modelContainer = try ModelContainer(
            for: DryFireVisionPersistenceSchema.schema,
            configurations: [configuration]
        )
        let rootURL = overrideRootURL ?? FileManager.default.temporaryDirectory
            .appendingPathComponent("DryFireVisionPersistenceTests-\(UUID().uuidString)", isDirectory: true)
        let poseAssetStore = overridePoseAssetStore ?? FilePoseAssetStore(rootDirectory: rootURL)
        let mediaAssetStore = overrideMediaAssetStore ?? FileMediaAssetStore(rootDirectory: rootURL)
        self.modelContainer = modelContainer
        self.poseAssetStore = poseAssetStore
        self.mediaAssetStore = mediaAssetStore
        self.rootURL = rootURL
        self.repository = SwiftDataSessionRepository(
            modelContainer: modelContainer,
            poseAssetStore: poseAssetStore,
            mediaAssetStore: mediaAssetStore
        )
    }

    func makeRepository() -> SwiftDataSessionRepository {
        SwiftDataSessionRepository(
            modelContainer: modelContainer,
            poseAssetStore: poseAssetStore,
            mediaAssetStore: mediaAssetStore
        )
    }

    func firstPoseAsset(sessionID: UUID) throws -> PersistedPoseAssetRecord {
        let context = ModelContext(modelContainer)
        let descriptor = FetchDescriptor<PersistedPoseAssetRecord>(
            predicate: #Predicate { $0.sessionID == sessionID },
            sortBy: [SortDescriptor(\.sampleCount, order: .reverse)]
        )
        return try XCTUnwrap(try context.fetch(descriptor).first)
    }

    func overwritePoseAsset(_ storageLocation: String, contents: String) throws {
        let url = storageLocation.split(separator: "/").reduce(rootURL) { partial, component in
            partial.appendingPathComponent(String(component))
        }
        let data = try XCTUnwrap(contents.data(using: .utf8))
        try data.write(to: url, options: [.atomic])
    }

    func createRawVideo(sessionID: UUID) throws -> AppOwnedMediaAssetReference {
        let relativePath = "Media/Sessions/\(sessionID.uuidString)/raw.mov"
        let url = relativePath.split(separator: "/").reduce(rootURL) { partial, component in
            partial.appendingPathComponent(String(component))
        }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = Data("raw-video-placeholder".utf8)
        try data.write(to: url, options: [.atomic])
        return AppOwnedMediaAssetReference(
            sessionID: sessionID,
            relativePath: relativePath,
            durationSeconds: 1,
            fileSizeBytes: data.count
        )
    }

    func setVideoRetentionState(
        _ state: VideoRetentionState,
        sessionID: UUID,
        relativePath: String?
    ) throws {
        let context = ModelContext(modelContainer)
        let session = try XCTUnwrap(try context.fetch(FetchDescriptor<PersistedTrainingSession>(
            predicate: #Predicate { $0.id == sessionID }
        )).first)
        session.videoRetentionState = state.rawValue
        let media = try XCTUnwrap(session.mediaAssets.first)
        media.retentionState = state.rawValue
        media.relativePath = relativePath
        try context.save()
    }

    func insertBareSession(id: UUID, status: SessionStatus) throws {
        let context = ModelContext(modelContainer)
        let session = PersistedTrainingSession(
            id: id,
            mode: PersistentSessionMode.dryFire.rawValue,
            status: status.rawValue,
            createdAt: Date(timeIntervalSince1970: 0),
            startedAt: nil,
            endedAt: nil,
            targetRepCount: 10,
            validRepCount: 0,
            degradedRepCount: 0,
            invalidRepCount: 0,
            actualSegmentedRepCount: 0,
            cameraPerspective: "unspecified",
            cameraPosition: nil,
            captureOrientation: "portrait",
            nominalCaptureFPS: nil,
            analysisCadenceFPS: nil,
            deviceModelIdentifier: nil,
            osVersion: nil,
            persistenceSchemaVersion: VersionCatalog.current.persistenceSchemaVersion,
            analysisVersion: VersionCatalog.current.analysisVersion,
            analysisConfigurationVersion: VersionCatalog.current.analysisConfigurationVersion,
            overallConfidence: ConfidenceStatus.low.rawValue,
            movementConsistency: nil,
            movementConsistencyAvailability: ComparisonAvailability.unavailable.rawValue,
            movementConsistencyConfidence: ConfidenceStatus.low.rawValue,
            movementConsistencyReason: ComparisonUnavailableReason.insufficientEligibleReps.rawValue,
            averageRepDuration: nil,
            representativeRepID: nil,
            fastestRepID: nil,
            videoRetentionState: VideoRetentionState.notRecorded.rawValue,
            analysisReasonsJSON: "[\"none\"]",
            durationAggregation: SessionDurationAggregation.arithmeticMeanOfValidReps.rawValue,
            durationEligibleRepCount: 0
        )
        context.insert(session)
        try context.save()
    }

    func persistedSessionStatus(_ id: UUID) throws -> SessionStatus {
        let context = ModelContext(modelContainer)
        let session = try XCTUnwrap(try context.fetch(FetchDescriptor<PersistedTrainingSession>(
            predicate: #Predicate { $0.id == id }
        )).first)
        return try XCTUnwrap(SessionStatus(rawValue: session.status))
    }

    func poseAssetCount(sessionID: UUID, type: PoseAssetType) throws -> Int {
        let context = ModelContext(modelContainer)
        let rawType = type.rawValue
        let descriptor = FetchDescriptor<PersistedPoseAssetRecord>(
            predicate: #Predicate { $0.sessionID == sessionID && $0.assetType == rawType }
        )
        return try context.fetch(descriptor).count
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: rootURL)
    }
}

private actor FailingPoseAssetStore: PoseAssetStoring {
    func save(
        _ payload: PoseAssetPayload,
        sessionID: UUID,
        repID: UUID?,
        assetType: PoseAssetType
    ) async throws -> SavedPoseAsset {
        throw PersistenceError.poseAssetWriteFailed
    }

    func load(storageLocation: String) async throws -> PoseAssetPayload {
        throw PersistenceError.poseAssetReadFailed
    }

    func exists(storageLocation: String) async -> Bool {
        false
    }

    func delete(storageLocation: String) async throws {}

    func deleteAllAssets(for sessionID: UUID) async throws {}
}

private actor FailingOnceMediaAssetStore: MediaAssetStoring {
    private let backing: FileMediaAssetStore
    private var shouldFailDelete = false

    init(rootURL: URL? = nil) {
        let root = rootURL ?? FileManager.default.temporaryDirectory
            .appendingPathComponent("DryFireVisionFailingMediaStore-\(UUID().uuidString)", isDirectory: true)
        self.backing = FileMediaAssetStore(rootDirectory: root)
    }

    func failNextDelete() {
        shouldFailDelete = true
    }

    func exists(_ media: AppOwnedMediaAssetReference) async throws -> Bool {
        try await backing.exists(media)
    }

    func delete(_ media: AppOwnedMediaAssetReference) async throws {
        if shouldFailDelete {
            shouldFailDelete = false
            throw PersistenceError.mediaDeleteFailed
        }
        try await backing.delete(media)
    }

    func deleteAllMedia(for sessionID: UUID) async throws {
        try await backing.deleteAllMedia(for: sessionID)
    }
}

private func XCTAssertThrowsErrorAsync<T>(
    _ expression: () async throws -> T,
    _ errorHandler: (Error) -> Void,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        _ = try await expression()
        XCTFail("Expected error", file: file, line: line)
    } catch {
        errorHandler(error)
    }
}
