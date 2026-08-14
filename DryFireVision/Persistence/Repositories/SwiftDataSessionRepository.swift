import Foundation
import SwiftData

public actor SwiftDataSessionRepository: SessionRepository {
    private let modelContainer: ModelContainer
    private let poseAssetStore: any PoseAssetStoring
    private let mediaAssetStore: any MediaAssetStoring

    public init(
        modelContainer: ModelContainer,
        poseAssetStore: any PoseAssetStoring,
        mediaAssetStore: any MediaAssetStoring = UnimplementedMediaAssetStore()
    ) {
        self.modelContainer = modelContainer
        self.poseAssetStore = poseAssetStore
        self.mediaAssetStore = mediaAssetStore
    }

    public static func production() throws -> SwiftDataSessionRepository {
        SwiftDataSessionRepository(
            modelContainer: ModelContainer(for: DryFireVisionPersistenceSchema.schema),
            poseAssetStore: FilePoseAssetStore.applicationSupportStore(),
            mediaAssetStore: FileMediaAssetStore.applicationSupportStore()
        )
    }

    public func save(_ analysis: SessionAnalysis) async throws -> UUID {
        try await save(analysis, videoRetentionPreference: .keep, rawVideo: nil)
    }

    public func save(
        _ analysis: SessionAnalysis,
        videoRetentionPreference: VideoRetentionPreference,
        rawVideo: AppOwnedMediaAssetReference?
    ) async throws -> UUID {
        let context = ModelContext(modelContainer)
        do {
            try await validateRawVideoReference(rawVideo)
            try await deleteSession(id: analysis.sessionID)
            let savedPoseAssets = try await savePoseAssets(for: analysis)
            try await verifyPoseAssetsExist(savedPoseAssets)

            let session = try SessionAnalysisPersistenceMapper.makeSessionRecord(from: analysis)
            session.videoRetentionState = initialRetentionState(
                preference: videoRetentionPreference,
                rawVideo: rawVideo
            ).rawValue
            context.insert(session)

            for saved in savedPoseAssets {
                let record = SessionAnalysisPersistenceMapper.makePoseAssetRecord(from: saved)
                record.session = session
                session.poseAssets.append(record)
                context.insert(record)
            }

            if let calibration = try SessionAnalysisPersistenceMapper.makeCalibrationRecord(from: analysis) {
                calibration.session = session
                session.calibrationRecords.append(calibration)
                context.insert(calibration)
            }

            let poseAssetIDByRepID = Dictionary(uniqueKeysWithValues: savedPoseAssets.compactMap { asset in
                asset.repID.map { ($0, asset.id) }
            })
            for rep in analysis.analyzedReps {
                let record = try SessionAnalysisPersistenceMapper.makeRepRecord(
                    from: rep,
                    analysis: analysis,
                    poseAssetID: poseAssetIDByRepID[rep.id]
                )
                record.session = session
                session.reps.append(record)
                context.insert(record)
            }

            let media = PersistedMediaAssetReference(
                id: UUID(),
                sessionID: analysis.sessionID,
                mediaType: MediaAssetType.video.rawValue,
                relativePath: rawVideo?.relativePath,
                createdAt: session.createdAt,
                durationSeconds: rawVideo?.durationSeconds,
                fileSizeBytes: rawVideo?.fileSizeBytes,
                retentionState: session.videoRetentionState,
                checksum: rawVideo?.checksum
            )
            media.session = session
            session.mediaAssets.append(media)
            context.insert(media)

            try context.save()
            _ = try fetchPersistedSession(id: analysis.sessionID, in: context)
            if videoRetentionPreference == .analyzeAndDelete, rawVideo != nil {
                try await transitionPersistedMediaToPendingDelete(sessionID: analysis.sessionID)
                await attemptPendingDeletion(sessionID: analysis.sessionID)
            }
            return analysis.sessionID
        } catch let error as PersistenceError {
            throw error
        } catch {
            throw PersistenceError.databaseWriteFailed
        }
    }

    public func session(id: UUID) async throws -> TrainingSessionSnapshot {
        let context = ModelContext(modelContainer)
        do {
            let session = try fetchPersistedSession(id: id, in: context)
            let availability = await poseAvailability(for: session.poseAssets)
            let mediaAvailability = await videoAvailability(for: session)
            return SessionAnalysisPersistenceMapper.snapshot(
                from: session,
                poseAssetsAvailable: availability,
                videoMediaAvailability: mediaAvailability
            )
        } catch let error as PersistenceError {
            throw error
        } catch {
            throw PersistenceError.databaseReadFailed
        }
    }

    public func poseAssetReference(sessionID: UUID, repID: UUID) async throws -> RepPoseAssetReference? {
        let context = ModelContext(modelContainer)
        do {
            let session = try fetchPersistedSession(id: sessionID, in: context)
            guard let rep = session.reps.first(where: { $0.id == repID && $0.sessionID == sessionID }) else {
                throw PersistenceError.integrityViolation(.repOutsideSession)
            }
            guard let poseAssetID = rep.poseAssetID else {
                return nil
            }
            guard let asset = session.poseAssets.first(where: {
                $0.id == poseAssetID &&
                    $0.sessionID == sessionID &&
                    $0.repID == repID &&
                    $0.assetType == PoseAssetType.repTrajectory.rawValue
            }) else {
                throw PersistenceError.integrityViolation(.invalidPoseAssetReference)
            }
            return RepPoseAssetReference(
                id: asset.id,
                sessionID: asset.sessionID,
                repID: repID,
                storageLocation: asset.storageLocation,
                encodingVersion: asset.encodingVersion,
                sampleCount: asset.sampleCount,
                startTimestamp: asset.startTimestamp,
                endTimestamp: asset.endTimestamp,
                jointSetVersion: asset.jointSetVersion,
                coordinateConventionVersion: asset.coordinateConventionVersion,
                checksum: asset.checksum
            )
        } catch let error as PersistenceError {
            throw error
        } catch {
            throw PersistenceError.databaseReadFailed
        }
    }

    public func recentCompletedSessions(limit: Int) async throws -> [TrainingSessionSnapshot] {
        let context = ModelContext(modelContainer)
        do {
            let completedStatus = SessionStatus.completed.rawValue
            let degradedStatus = SessionStatus.degraded.rawValue
            var descriptor = FetchDescriptor<PersistedTrainingSession>(
                predicate: #Predicate {
                    $0.status == completedStatus || $0.status == degradedStatus
                },
                sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
            )
            descriptor.fetchLimit = max(0, limit)
            let sessions = try context.fetch(descriptor)
            var snapshots: [TrainingSessionSnapshot] = []
            for session in sessions {
                let availability = await poseAvailability(for: session.poseAssets)
                let mediaAvailability = await videoAvailability(for: session)
                snapshots.append(SessionAnalysisPersistenceMapper.snapshot(
                    from: session,
                    poseAssetsAvailable: availability,
                    videoMediaAvailability: mediaAvailability
                ))
            }
            return snapshots
        } catch {
            throw PersistenceError.databaseReadFailed
        }
    }

    public func deleteSession(id: UUID) async throws {
        let context = ModelContext(modelContainer)
        do {
            guard let session = try fetchPersistedSessionIfExists(id: id, in: context) else {
                try await poseAssetStore.deleteAllAssets(for: id)
                try await mediaAssetStore.deleteAllMedia(for: id)
                return
            }
            try await mediaAssetStore.deleteAllMedia(for: id)
            try await poseAssetStore.deleteAllAssets(for: id)
            context.delete(session)
            try context.save()
        } catch let error as PersistenceError {
            throw error
        } catch {
            throw PersistenceError.databaseWriteFailed
        }
    }

    public func saveLiveFire(
        _ analysis: LiveFireSessionAnalysis,
        videoRetentionPreference: VideoRetentionPreference,
        rawVideo: AppOwnedMediaAssetReference?
    ) async throws -> UUID {
        let context = ModelContext(modelContainer)
        do {
            try await validateRawVideoReference(rawVideo)
            try await deleteSession(id: analysis.sessionID)

            let session = makeLiveFireSessionRecord(from: analysis, rawVideo: rawVideo)
            session.videoRetentionState = initialRetentionState(preference: videoRetentionPreference, rawVideo: rawVideo).rawValue
            context.insert(session)

            var savedPoseAssetsByEventID: [UUID: SavedPoseAsset] = [:]
            for (eventID, payload) in analysis.recoveryPoseAssetsByEventID {
                let saved = try await poseAssetStore.save(payload, sessionID: analysis.sessionID, repID: eventID, assetType: .recoveryWindow)
                savedPoseAssetsByEventID[eventID] = saved
                let record = SessionAnalysisPersistenceMapper.makePoseAssetRecord(from: saved)
                record.session = session
                session.poseAssets.append(record)
                context.insert(record)
            }
            try await verifyPoseAssetsExist(Array(savedPoseAssetsByEventID.values))

            for event in analysis.events {
                let record = makeLiveEventRecord(from: event, analysis: analysis, poseAssetID: savedPoseAssetsByEventID[event.id]?.id)
                record.session = session
                session.liveEvents.append(record)
                context.insert(record)
            }

            let media = PersistedMediaAssetReference(
                id: UUID(),
                sessionID: analysis.sessionID,
                mediaType: MediaAssetType.video.rawValue,
                relativePath: rawVideo?.relativePath,
                createdAt: analysis.createdAt,
                durationSeconds: rawVideo?.durationSeconds,
                fileSizeBytes: rawVideo?.fileSizeBytes,
                retentionState: initialRetentionState(preference: videoRetentionPreference, rawVideo: rawVideo).rawValue,
                checksum: rawVideo?.checksum
            )
            media.session = session
            session.mediaAssets.append(media)
            context.insert(media)

            try context.save()
            _ = try fetchPersistedSession(id: analysis.sessionID, in: context)
            if videoRetentionPreference == .analyzeAndDelete, rawVideo != nil {
                try await transitionPersistedMediaToPendingDelete(sessionID: analysis.sessionID)
                await attemptPendingDeletion(sessionID: analysis.sessionID)
            }
            return analysis.sessionID
        } catch let error as PersistenceError {
            throw error
        } catch {
            throw PersistenceError.databaseWriteFailed
        }
    }

    public func liveFireSession(id: UUID) async throws -> LiveFireSessionAnalysis {
        let context = ModelContext(modelContainer)
        do {
            let session = try fetchPersistedSession(id: id, in: context)
            guard PersistentSessionMode(rawValue: session.mode) == .liveFire else {
                throw PersistenceError.integrityViolation(.unsupportedSessionMode)
            }
            return liveFireAnalysis(from: session)
        } catch let error as PersistenceError {
            throw error
        } catch {
            throw PersistenceError.databaseReadFailed
        }
    }

    public func performMaintenance(maxDeletions: Int = 10) async throws -> MaintenanceReport {
        let context = ModelContext(modelContainer)
        var report = MaintenanceReport()
        do {
            let sessions = try context.fetch(FetchDescriptor<PersistedTrainingSession>())
            for session in sessions {
                switch SessionStatus(rawValue: session.status) {
                case .capturing:
                    session.status = SessionStatus.cancelled.rawValue
                    report.strandedCapturingSessions += 1
                case .processing:
                    session.status = SessionStatus.failed.rawValue
                    report.strandedProcessingSessions += 1
                default:
                    break
                }

                guard report.mediaDeletionAttempts < maxDeletions else {
                    continue
                }
                if await repairMediaState(for: session) {
                    report.mediaDeletionAttempts += 1
                }
            }
            try context.save()
            return report
        } catch let error as PersistenceError {
            throw error
        } catch {
            throw PersistenceError.databaseWriteFailed
        }
    }

    private func savePoseAssets(for analysis: SessionAnalysis) async throws -> [SavedPoseAsset] {
        var saved: [SavedPoseAsset] = []
        for rep in analysis.analyzedReps {
            guard let payload = SessionAnalysisPersistenceMapper.posePayload(for: rep, analysis: analysis) else {
                continue
            }
            let asset = try await poseAssetStore.save(
                payload,
                sessionID: analysis.sessionID,
                repID: rep.id,
                assetType: .repTrajectory
            )
            saved.append(asset)
        }
        return saved
    }

    private func validateRawVideoReference(_ rawVideo: AppOwnedMediaAssetReference?) async throws {
        guard let rawVideo else {
            return
        }
        _ = try await mediaAssetStore.exists(rawVideo)
    }

    private func verifyPoseAssetsExist(_ assets: [SavedPoseAsset]) async throws {
        for asset in assets {
            guard await poseAssetStore.exists(storageLocation: asset.storageLocation) else {
                throw PersistenceError.integrityViolation(.missingPoseAssetFile)
            }
        }
    }

    private func poseAvailability(for assets: [PersistedPoseAssetRecord]) async -> PoseAssetAvailability {
        guard !assets.isEmpty else {
            return .unavailable
        }
        for asset in assets {
            guard await poseAssetStore.exists(storageLocation: asset.storageLocation) else {
                return .missing
            }
            do {
                _ = try await poseAssetStore.load(storageLocation: asset.storageLocation)
            } catch {
                return .corrupt
            }
        }
        return .available
    }

    private func initialRetentionState(
        preference: VideoRetentionPreference,
        rawVideo: AppOwnedMediaAssetReference?
    ) -> VideoRetentionState {
        guard rawVideo != nil else {
            return .notRecorded
        }
        switch preference {
        case .keep:
            return .keep
        case .analyzeAndDelete:
            return .keep
        }
    }

    private func makeLiveFireSessionRecord(
        from analysis: LiveFireSessionAnalysis,
        rawVideo: AppOwnedMediaAssetReference?
    ) -> PersistedTrainingSession {
        PersistedTrainingSession(
            id: analysis.sessionID,
            mode: PersistentSessionMode.liveFire.rawValue,
            status: analysis.acceptedEventCount > 0 ? SessionStatus.completed.rawValue : SessionStatus.degraded.rawValue,
            createdAt: analysis.createdAt,
            startedAt: analysis.createdAt,
            endedAt: nil,
            targetRepCount: 0,
            validRepCount: 0,
            degradedRepCount: 0,
            invalidRepCount: 0,
            actualSegmentedRepCount: 0,
            cameraPerspective: "live-fire-beta",
            cameraPosition: nil,
            captureOrientation: "portrait",
            nominalCaptureFPS: nil,
            analysisCadenceFPS: nil,
            deviceModelIdentifier: nil,
            osVersion: nil,
            persistenceSchemaVersion: VersionCatalog.current.persistenceSchemaVersion,
            analysisVersion: analysis.analysisVersion,
            analysisConfigurationVersion: analysis.analysisConfigurationVersion,
            overallConfidence: analysis.overallConfidence.rawValue,
            movementConsistency: nil,
            movementConsistencyAvailability: ComparisonAvailability.unavailable.rawValue,
            movementConsistencyConfidence: ConfidenceStatus.low.rawValue,
            movementConsistencyReason: ComparisonUnavailableReason.insufficientEligibleReps.rawValue,
            averageRepDuration: nil,
            representativeRepID: nil,
            fastestRepID: nil,
            videoRetentionState: initialRetentionState(preference: .keep, rawVideo: rawVideo).rawValue,
            analysisReasonsJSON: "[\"none\"]",
            durationAggregation: SessionDurationAggregation.arithmeticMeanOfValidReps.rawValue,
            durationEligibleRepCount: 0
        )
    }

    private func makeLiveEventRecord(
        from event: LiveEventAnalysis,
        analysis: LiveFireSessionAnalysis,
        poseAssetID: UUID?
    ) -> PersistedLiveEventRecord {
        PersistedLiveEventRecord(
            id: event.id,
            sessionID: event.sessionID,
            sequenceIndex: event.sequenceIndex,
            timestampSeconds: event.timestampSeconds,
            eventConfidence: event.eventConfidence.rawValue,
            status: event.status.rawValue,
            interEventDurationSeconds: event.interEventDurationSeconds,
            headDisplacement: event.headDisplacement.value,
            headDisplacementAvailability: event.headDisplacement.availability.rawValue,
            upperBodyDisplacement: event.upperBodyDisplacement.value,
            upperBodyDisplacementAvailability: event.upperBodyDisplacement.availability.rawValue,
            peakVisibleDisplacement: event.peakVisibleDisplacement.value,
            peakVisibleDisplacementAvailability: event.peakVisibleDisplacement.availability.rawValue,
            recoveryDuration: event.recoveryDuration.value,
            recoveryDurationAvailability: event.recoveryDuration.availability.rawValue,
            recoverySimilarity: event.recoverySimilarity,
            recoveryConfidence: event.recoveryConfidence.rawValue,
            isOutlier: event.isOutlier,
            poseAssetID: poseAssetID,
            reason: event.reason.rawValue,
            analysisVersion: analysis.analysisVersion,
            analysisConfigurationVersion: analysis.analysisConfigurationVersion
        )
    }

    private func liveFireAnalysis(from session: PersistedTrainingSession) -> LiveFireSessionAnalysis {
        let events = session.liveEvents.sorted { $0.sequenceIndex < $1.sequenceIndex }.map { record in
            LiveEventAnalysis(
                id: record.id,
                sessionID: record.sessionID,
                sequenceIndex: record.sequenceIndex,
                timestampSeconds: record.timestampSeconds,
                eventConfidence: ConfidenceStatus(rawValue: record.eventConfidence) ?? .low,
                status: LiveEventStatus(rawValue: record.status) ?? .rejected,
                interEventDurationSeconds: record.interEventDurationSeconds,
                headDisplacement: liveMetric(.headDisplacement, value: record.headDisplacement, availability: record.headDisplacementAvailability, configurationVersion: record.analysisConfigurationVersion),
                upperBodyDisplacement: liveMetric(.shoulderDisplacement, value: record.upperBodyDisplacement, availability: record.upperBodyDisplacementAvailability, configurationVersion: record.analysisConfigurationVersion),
                peakVisibleDisplacement: liveMetric(.shoulderDisplacement, value: record.peakVisibleDisplacement, availability: record.peakVisibleDisplacementAvailability, configurationVersion: record.analysisConfigurationVersion),
                recoveryDuration: liveMetric(.totalRepDuration, value: record.recoveryDuration, availability: record.recoveryDurationAvailability, configurationVersion: record.analysisConfigurationVersion),
                recoverySimilarity: record.recoverySimilarity,
                recoveryConfidence: ConfidenceStatus(rawValue: record.recoveryConfidence) ?? .low,
                isOutlier: record.isOutlier,
                poseAssetID: record.poseAssetID,
                reason: LiveEventReason(rawValue: record.reason) ?? .none
            )
        }
        return LiveFireSessionAnalysis(
            sessionID: session.id,
            createdAt: session.createdAt,
            analysisVersion: session.analysisVersion,
            analysisConfigurationVersion: session.analysisConfigurationVersion,
            events: events,
            recoveryConsistency: liveRecoveryConsistency(from: events),
            overallConfidence: ConfidenceStatus(rawValue: session.overallConfidence) ?? .low
        )
    }

    private func liveRecoveryConsistency(from events: [LiveEventAnalysis]) -> SessionConsistencyResult {
        let similarities = events.compactMap { event in
            event.status == .accepted ? event.recoverySimilarity : nil
        }
        guard similarities.count >= 3 else {
            return .unavailable(reason: .insufficientEligibleReps)
        }
        let value = similarities.reduce(0, +) / Double(similarities.count)
        return SessionConsistencyResult(availability: .available, internalValue: value, confidence: .medium, reason: .none)
    }

    private func liveMetric(
        _ key: MovementMetricKey,
        value: Double?,
        availability: String,
        configurationVersion: String
    ) -> MovementMetricResult {
        if availability == MetricAvailability.available.rawValue, let value {
            return .available(key: key, value: value, confidence: .medium, configurationVersion: configurationVersion)
        }
        return .unavailable(key: key, reason: .insufficientJointCoverage, configurationVersion: configurationVersion)
    }

    private func transitionPersistedMediaToPendingDelete(sessionID: UUID) async throws {
        let context = ModelContext(modelContainer)
        let session = try fetchPersistedSession(id: sessionID, in: context)
        guard let media = videoMedia(in: session), media.relativePath != nil else {
            return
        }
        session.videoRetentionState = VideoRetentionState.pendingDelete.rawValue
        media.retentionState = VideoRetentionState.pendingDelete.rawValue
        try context.save()
    }

    private func attemptPendingDeletion(sessionID: UUID) async {
        let context = ModelContext(modelContainer)
        guard let session = try? fetchPersistedSession(id: sessionID, in: context) else {
            return
        }
        _ = await repairMediaState(for: session)
        try? context.save()
    }

    @discardableResult
    private func repairMediaState(for session: PersistedTrainingSession) async -> Bool {
        guard let media = videoMedia(in: session),
              let state = VideoRetentionState(rawValue: media.retentionState) else {
            return false
        }
        switch state {
        case .pendingDelete, .deletionFailed:
            guard let reference = mediaReference(from: media) else {
                session.videoRetentionState = VideoRetentionState.deleted.rawValue
                media.retentionState = VideoRetentionState.deleted.rawValue
                media.relativePath = nil
                return true
            }
            do {
                if try await mediaAssetStore.exists(reference) {
                    try await mediaAssetStore.delete(reference)
                }
                if try await mediaAssetStore.exists(reference) == false {
                    session.videoRetentionState = VideoRetentionState.deleted.rawValue
                    media.retentionState = VideoRetentionState.deleted.rawValue
                    media.relativePath = nil
                } else {
                    session.videoRetentionState = VideoRetentionState.deletionFailed.rawValue
                    media.retentionState = VideoRetentionState.deletionFailed.rawValue
                }
            } catch {
                session.videoRetentionState = VideoRetentionState.deletionFailed.rawValue
                media.retentionState = VideoRetentionState.deletionFailed.rawValue
            }
            return true
        case .keep:
            if let reference = mediaReference(from: media),
               (try? await mediaAssetStore.exists(reference)) == false {
                reportMissingKeptMedia(session: session, media: media)
            }
            return false
        case .deleted, .notRecorded:
            return false
        }
    }

    private func videoAvailability(for session: PersistedTrainingSession) async -> VideoMediaAvailability {
        let state = VideoRetentionState(rawValue: session.videoRetentionState) ?? .notRecorded
        guard let media = videoMedia(in: session) else {
            return state == .notRecorded ? .notRecorded : .unavailable
        }
        switch state {
        case .notRecorded:
            return .notRecorded
        case .deleted:
            return .videoDeletedByPreference
        case .pendingDelete:
            return .videoDeletionPending
        case .deletionFailed:
            return .videoDeletionFailed
        case .keep:
            guard let reference = mediaReference(from: media) else {
                return .videoMissing
            }
            do {
                return try await mediaAssetStore.exists(reference) ? .videoAvailable : .videoMissing
            } catch {
                return .videoMissing
            }
        }
    }

    private func videoMedia(in session: PersistedTrainingSession) -> PersistedMediaAssetReference? {
        session.mediaAssets.first { $0.mediaType == MediaAssetType.video.rawValue }
    }

    private func mediaReference(from media: PersistedMediaAssetReference) -> AppOwnedMediaAssetReference? {
        guard let relativePath = media.relativePath else {
            return nil
        }
        return AppOwnedMediaAssetReference(
            sessionID: media.sessionID,
            relativePath: relativePath,
            durationSeconds: media.durationSeconds,
            fileSizeBytes: media.fileSizeBytes,
            checksum: media.checksum
        )
    }

    private func reportMissingKeptMedia(session: PersistedTrainingSession, media: PersistedMediaAssetReference) {
        session.videoRetentionState = VideoRetentionState.keep.rawValue
        media.retentionState = VideoRetentionState.keep.rawValue
    }

    private func fetchPersistedSession(id: UUID, in context: ModelContext) throws -> PersistedTrainingSession {
        guard let session = try fetchPersistedSessionIfExists(id: id, in: context) else {
            throw PersistenceError.sessionNotFound(id)
        }
        return session
    }

    private func fetchPersistedSessionIfExists(id: UUID, in context: ModelContext) throws -> PersistedTrainingSession? {
        let descriptor = FetchDescriptor<PersistedTrainingSession>(
            predicate: #Predicate { $0.id == id }
        )
        return try context.fetch(descriptor).first
    }
}
