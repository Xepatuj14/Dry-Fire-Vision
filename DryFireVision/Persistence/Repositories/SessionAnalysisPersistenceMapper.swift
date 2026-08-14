import Foundation

public enum SessionAnalysisPersistenceMapper {
    public static func makeSessionRecord(from analysis: SessionAnalysis) throws -> PersistedTrainingSession {
        try validateReferences(analysis)
        let metadata = analysis.recordingMetadata
        return PersistedTrainingSession(
            id: analysis.sessionID,
            mode: try persistentMode(for: analysis.mode).rawValue,
            status: persistentStatus(for: analysis.status).rawValue,
            createdAt: Date(timeIntervalSince1970: analysis.recordingStartTimestampSeconds ?? 0),
            startedAt: analysis.recordingStartTimestampSeconds.map { Date(timeIntervalSince1970: $0) },
            endedAt: analysis.recordingEndTimestampSeconds.map { Date(timeIntervalSince1970: $0) },
            targetRepCount: analysis.targetRepCount,
            validRepCount: analysis.validRepCount,
            degradedRepCount: analysis.degradedRepCount,
            invalidRepCount: analysis.invalidRepCount,
            actualSegmentedRepCount: analysis.actualSegmentedRepCount,
            cameraPerspective: metadata?.cameraPerspective ?? "unspecified",
            cameraPosition: nil,
            captureOrientation: metadata?.captureOrientation ?? "portrait",
            nominalCaptureFPS: try finiteOptional(metadata?.nominalCaptureFPS),
            analysisCadenceFPS: try finiteOptional(metadata?.effectivePoseFPS),
            deviceModelIdentifier: nil,
            osVersion: nil,
            persistenceSchemaVersion: VersionCatalog.current.persistenceSchemaVersion,
            analysisVersion: analysis.analysisVersion,
            analysisConfigurationVersion: analysis.analysisConfigurationVersion,
            overallConfidence: analysis.overallConfidence.rawValue,
            movementConsistency: try finiteOptional(analysis.movementConsistency.internalValue),
            movementConsistencyAvailability: analysis.movementConsistency.availability.rawValue,
            movementConsistencyConfidence: analysis.movementConsistency.confidence.rawValue,
            movementConsistencyReason: analysis.movementConsistency.reason.rawValue,
            averageRepDuration: try finiteOptional(analysis.averageValidRepDurationSeconds),
            representativeRepID: analysis.representativeRepID,
            fastestRepID: analysis.fastestRepID,
            videoRetentionState: VideoRetentionState.notRecorded.rawValue,
            analysisReasonsJSON: try encodeReasons(analysis.reasons),
            durationAggregation: analysis.durationDiagnostics.aggregation.rawValue,
            durationEligibleRepCount: analysis.durationDiagnostics.eligibleRepCount
        )
    }

    public static func makeRepRecord(
        from rep: AnalyzedRep,
        analysis: SessionAnalysis,
        poseAssetID: UUID?
    ) throws -> PersistedRepRecord {
        let comparison = analysis.comparisonResult?.similarityToRepresentative[rep.id]
        return PersistedRepRecord(
            id: rep.id,
            sessionID: analysis.sessionID,
            sequenceIndex: rep.sequenceIndex,
            startTimestamp: rep.segment.startTimestampSeconds,
            activeMovementEndTimestamp: try finiteOptional(rep.segment.activeMovementEndTimestampSeconds),
            completeTimestamp: rep.segment.completeTimestampSeconds,
            duration: try finite(rep.segment.durationSeconds),
            validity: rep.segment.validity.rawValue,
            segmentationConfidence: rep.segment.confidenceStatus.rawValue,
            segmentationReason: rep.segment.diagnosticReason.rawValue,
            aggregateMetricConfidence: rep.metrics.aggregateConfidence.rawValue,
            isOutlier: analysis.movementOutlierRepIDs.contains(rep.id),
            outlierReason: analysis.movementOutlierRepIDs.contains(rep.id) ? "movementOutlier" : nil,
            similarityToRepresentative: try finiteOptional(comparison?.internalSimilarity),
            poseAssetID: poseAssetID,
            sourceRecordingID: rep.sourceRecordingID,
            durationAvailability: rep.metrics.duration.availability.rawValue,
            durationConfidence: rep.metrics.duration.confidence.rawValue,
            durationReason: rep.metrics.duration.reason.rawValue,
            headDisplacement: try persistedMetricValue(rep.metrics.headDisplacement),
            headDisplacementAvailability: rep.metrics.headDisplacement.availability.rawValue,
            headDisplacementConfidence: rep.metrics.headDisplacement.confidence.rawValue,
            headDisplacementReason: rep.metrics.headDisplacement.reason.rawValue,
            shoulderDisplacement: try persistedMetricValue(rep.metrics.shoulderDisplacement),
            shoulderDisplacementAvailability: rep.metrics.shoulderDisplacement.availability.rawValue,
            shoulderDisplacementConfidence: rep.metrics.shoulderDisplacement.confidence.rawValue,
            shoulderDisplacementReason: rep.metrics.shoulderDisplacement.reason.rawValue,
            wristPathLength: try persistedMetricValue(rep.metrics.primaryWristPathLength),
            wristPathLengthAvailability: rep.metrics.primaryWristPathLength.availability.rawValue,
            wristPathLengthConfidence: rep.metrics.primaryWristPathLength.confidence.rawValue,
            wristPathLengthReason: rep.metrics.primaryWristPathLength.reason.rawValue,
            wristPathDirectness: try persistedMetricValue(rep.metrics.wristPathDirectness),
            wristPathDirectnessAvailability: rep.metrics.wristPathDirectness.availability.rawValue,
            wristPathDirectnessConfidence: rep.metrics.wristPathDirectness.confidence.rawValue,
            wristPathDirectnessReason: rep.metrics.wristPathDirectness.reason.rawValue,
            analysisVersion: rep.metrics.analysisVersion,
            analysisConfigurationVersion: rep.metrics.configurationVersion
        )
    }

    public static func makeCalibrationRecord(from analysis: SessionAnalysis) throws -> PersistedCalibrationRecord? {
        guard let recording = analysis.sourceRecording else {
            return nil
        }
        let calibration = recording.calibrationResult
        return PersistedCalibrationRecord(
            id: UUID(),
            sessionID: analysis.sessionID,
            createdAt: Date(timeIntervalSince1970: analysis.recordingStartTimestampSeconds ?? 0),
            baselineDuration: try finite(calibration.baselinePose.durationSeconds),
            normalizationScale: try finite(calibration.normalizationScale),
            normalizationSource: calibration.normalizationScaleSource.rawValue,
            baselinePoseAssetID: nil,
            requiredJointCoverage: try finite(calibration.quality.requiredJointCoverage),
            averageJointConfidence: try finite(calibration.quality.averageConfidence),
            calibrationConfidence: calibration.quality.confidenceStatus.rawValue,
            blockingFailureReason: nil
        )
    }

    public static func posePayload(for rep: AnalyzedRep, analysis: SessionAnalysis) -> PoseAssetPayload? {
        guard let recording = analysis.sourceRecording else {
            return nil
        }
        let frames = recording.poseFrames.filter {
            $0.timestampSeconds >= rep.segment.startTimestampSeconds &&
                $0.timestampSeconds <= rep.segment.completeTimestampSeconds
        }
        return PoseAssetPayload(recording: recording, frames: frames)
    }

    public static func makePoseAssetRecord(from saved: SavedPoseAsset) -> PersistedPoseAssetRecord {
        PersistedPoseAssetRecord(
            id: saved.id,
            sessionID: saved.sessionID,
            repID: saved.repID,
            assetType: saved.assetType.rawValue,
            storageLocation: saved.storageLocation,
            encodingVersion: saved.encodingVersion,
            sampleCount: saved.sampleCount,
            startTimestamp: saved.startTimestamp,
            endTimestamp: saved.endTimestamp,
            jointSetVersion: saved.jointSetVersion,
            coordinateConventionVersion: saved.coordinateConventionVersion,
            checksum: saved.checksum
        )
    }

    public static func snapshot(
        from session: PersistedTrainingSession,
        poseAssetsAvailable: PoseAssetAvailability,
        videoMediaAvailability: VideoMediaAvailability = .notRecorded
    ) -> TrainingSessionSnapshot {
        let analysis = analysis(from: session)
        return TrainingSessionSnapshot(
            id: session.id,
            mode: domainMode(for: session.mode),
            status: analysis.status,
            createdAt: session.createdAt,
            analysisVersion: session.analysisVersion,
            analysisConfigurationVersion: session.analysisConfigurationVersion,
            analysis: analysis,
            poseAssetAvailability: poseAssetsAvailable,
            videoRetentionState: VideoRetentionState(rawValue: session.videoRetentionState) ?? .notRecorded,
            videoMediaAvailability: videoMediaAvailability
        )
    }

    private static func analysis(from session: PersistedTrainingSession) -> SessionAnalysis {
        let reps = session.reps.sorted { $0.sequenceIndex < $1.sequenceIndex }.map(analyzedRep(from:))
        let reasons = decodeReasons(session.analysisReasonsJSON)
        return SessionAnalysis(
            sessionID: session.id,
            recordingID: nil,
            mode: domainMode(for: session.mode),
            recordingStartTimestampSeconds: session.startedAt?.timeIntervalSince1970,
            recordingEndTimestampSeconds: session.endedAt?.timeIntervalSince1970,
            recordingMetadata: PoseRecordingMetadata(
                cameraPerspective: session.cameraPerspective,
                captureOrientation: session.captureOrientation,
                nominalCaptureFPS: session.nominalCaptureFPS,
                effectivePoseFPS: session.analysisCadenceFPS
            ),
            sourceRecording: nil,
            analysisVersion: session.analysisVersion,
            analysisConfigurationVersion: session.analysisConfigurationVersion,
            targetRepCount: session.targetRepCount,
            actualSegmentedRepCount: session.actualSegmentedRepCount,
            validRepCount: session.validRepCount,
            degradedRepCount: session.degradedRepCount,
            invalidRepCount: session.invalidRepCount,
            averageValidRepDurationSeconds: session.averageRepDuration,
            analyzedReps: reps,
            representativeRepID: session.representativeRepID,
            fastestRepID: session.fastestRepID,
            movementOutlierRepIDs: session.reps.filter(\.isOutlier).sorted { $0.sequenceIndex < $1.sequenceIndex }.map(\.id),
            movementConsistency: SessionConsistencyResult(
                availability: ComparisonAvailability(rawValue: session.movementConsistencyAvailability) ?? .unavailable,
                internalValue: session.movementConsistency,
                confidence: ConfidenceStatus(rawValue: session.movementConsistencyConfidence) ?? .low,
                reason: ComparisonUnavailableReason(rawValue: session.movementConsistencyReason) ?? .none
            ),
            comparisonResult: nil,
            segmentationResult: nil,
            overallConfidence: ConfidenceStatus(rawValue: session.overallConfidence) ?? .low,
            status: domainStatus(for: session.status, reasons: reasons),
            reasons: reasons,
            durationDiagnostics: SessionAnalysisDurationDiagnostics(
                aggregation: SessionDurationAggregation(rawValue: session.durationAggregation) ?? .arithmeticMeanOfValidReps,
                eligibleRepCount: session.durationEligibleRepCount
            )
        )
    }

    private static func analyzedRep(from record: PersistedRepRecord) -> AnalyzedRep {
        let segment = RepSegment(
            id: record.id,
            sequenceIndex: record.sequenceIndex,
            startTimestampSeconds: record.startTimestamp,
            activeMovementEndTimestampSeconds: record.activeMovementEndTimestamp,
            completeTimestampSeconds: record.completeTimestamp,
            validity: RepValidity(rawValue: record.validity) ?? .invalid,
            confidenceStatus: ConfidenceStatus(rawValue: record.segmentationConfidence) ?? .low,
            diagnosticReason: SegmentationReason(rawValue: record.segmentationReason) ?? .none
        )
        let metrics = MovementMetricSet(
            duration: metric(.totalRepDuration, value: record.durationAvailability == MetricAvailability.available.rawValue ? record.duration : nil, availability: record.durationAvailability, confidence: record.durationConfidence, reason: record.durationReason, configurationVersion: record.analysisConfigurationVersion),
            headDisplacement: metric(.headDisplacement, value: record.headDisplacement, availability: record.headDisplacementAvailability, confidence: record.headDisplacementConfidence, reason: record.headDisplacementReason, configurationVersion: record.analysisConfigurationVersion),
            shoulderDisplacement: metric(.shoulderDisplacement, value: record.shoulderDisplacement, availability: record.shoulderDisplacementAvailability, confidence: record.shoulderDisplacementConfidence, reason: record.shoulderDisplacementReason, configurationVersion: record.analysisConfigurationVersion),
            primaryWristPathLength: metric(.primaryWristPathLength, value: record.wristPathLength, availability: record.wristPathLengthAvailability, confidence: record.wristPathLengthConfidence, reason: record.wristPathLengthReason, configurationVersion: record.analysisConfigurationVersion),
            wristPathDirectness: metric(.wristPathDirectness, value: record.wristPathDirectness, availability: record.wristPathDirectnessAvailability, confidence: record.wristPathDirectnessConfidence, reason: record.wristPathDirectnessReason, configurationVersion: record.analysisConfigurationVersion),
            analysisVersion: record.analysisVersion,
            configurationVersion: record.analysisConfigurationVersion
        )
        return AnalyzedRep(
            id: record.id,
            sequenceIndex: record.sequenceIndex,
            segment: segment,
            metrics: metrics,
            metricDiagnostics: [],
            sourceRecordingID: record.sourceRecordingID
        )
    }

    private static func metric(
        _ key: MovementMetricKey,
        value: Double?,
        availability: String,
        confidence: String,
        reason: String,
        configurationVersion: String
    ) -> MovementMetricResult {
        MovementMetricResult(
            key: key,
            value: value,
            availability: MetricAvailability(rawValue: availability) ?? .unavailable,
            confidence: ConfidenceStatus(rawValue: confidence) ?? .low,
            reason: MetricUnavailableReason(rawValue: reason) ?? .none,
            configurationVersion: configurationVersion
        )
    }

    private static func validateReferences(_ analysis: SessionAnalysis) throws {
        let repIDs = Set(analysis.analyzedReps.map(\.id))
        if let representative = analysis.representativeRepID, !repIDs.contains(representative) {
            throw PersistenceError.integrityViolation(.representativeRepOutsideSession)
        }
        if let fastest = analysis.fastestRepID, !repIDs.contains(fastest) {
            throw PersistenceError.integrityViolation(.fastestRepOutsideSession)
        }
        if !analysis.movementOutlierRepIDs.allSatisfy({ repIDs.contains($0) }) {
            throw PersistenceError.integrityViolation(.outlierRepOutsideSession)
        }
    }

    private static func persistedMetricValue(_ metric: MovementMetricResult) throws -> Double? {
        guard metric.availability == .available else {
            return nil
        }
        return try finiteOptional(metric.value)
    }

    private static func finiteOptional(_ value: Double?) throws -> Double? {
        guard let value else {
            return nil
        }
        return try finite(value)
    }

    private static func finite(_ value: Double) throws -> Double {
        guard value.isFinite else {
            throw PersistenceError.integrityViolation(.nonFiniteMetric)
        }
        return value
    }

    private static func encodeReasons(_ reasons: [SessionAnalysisReason]) throws -> String {
        let data = try JSONEncoder().encode(reasons.map(\.rawValue))
        return String(decoding: data, as: UTF8.self)
    }

    private static func decodeReasons(_ json: String) -> [SessionAnalysisReason] {
        guard let data = json.data(using: .utf8),
              let values = try? JSONDecoder().decode([String].self, from: data) else {
            return [.none]
        }
        let reasons = values.compactMap(SessionAnalysisReason.init(rawValue:))
        return reasons.isEmpty ? [.none] : reasons
    }

    private static func persistentMode(for mode: SessionMode) throws -> PersistentSessionMode {
        switch mode {
        case .dryFire:
            return .dryFire
        case .liveFireBeta:
            return .liveFire
        }
    }

    private static func domainMode(for rawValue: String) -> SessionMode {
        PersistentSessionMode(rawValue: rawValue) == .liveFire ? .liveFireBeta : .dryFire
    }

    private static func persistentStatus(for status: SessionAnalysisStatus) -> SessionStatus {
        switch status {
        case .completed:
            return .completed
        case .degraded, .noValidReps:
            return .degraded
        case .failed:
            return .failed
        }
    }

    private static func domainStatus(for rawValue: String, reasons: [SessionAnalysisReason]) -> SessionAnalysisStatus {
        if reasons.contains(.noValidReps) {
            return .noValidReps
        }
        switch SessionStatus(rawValue: rawValue) {
        case .completed:
            return .completed
        case .degraded:
            return .degraded
        case .failed:
            return .failed
        default:
            return .failed
        }
    }
}

public enum PersistentSessionMode: String, Codable, Equatable, Sendable {
    case dryFire
    case liveFire
}
