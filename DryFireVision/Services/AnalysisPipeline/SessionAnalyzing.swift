import Foundation

public protocol SessionAnalyzing: Sendable {
    func analyze(_ input: AnalysisInput) async throws -> SessionAnalysis
}

public enum SessionAnalysisError: Error, Equatable, Sendable {
    case invalidRecording
    case unusableCalibration
    case segmentationFailed
    case insufficientPoseData
    case invalidAnalysisConfiguration
    case internalAnalysisFailure
}

public struct SessionAnalysisPipeline: SessionAnalyzing {
    public init() {}

    public func analyze(_ input: AnalysisInput) async throws -> SessionAnalysis {
        try Task.checkCancellation()
        guard let recording = input.recording else {
            throw SessionAnalysisError.invalidRecording
        }
        try validate(input: input, recording: recording)

        let segmenter = RepSegmenter(configuration: input.configuration)
        let segmentation: SegmentationResult
        do {
            segmentation = try segmenter.segment(recording)
        } catch let error as SegmentationError {
            throw map(segmentationError: error)
        } catch {
            throw SessionAnalysisError.internalAnalysisFailure
        }

        try Task.checkCancellation()
        guard segmentation.status != .failed else {
            throw SessionAnalysisError.segmentationFailed
        }

        let metricAnalyzer = RepMetricAnalyzer(configuration: input.configuration)
        let analyzedReps = metricAnalyzer.analyze(recording: recording, segmentationResult: segmentation)

        try Task.checkCancellation()
        let comparison = SessionComparisonAnalyzer(configuration: input.configuration)
            .analyze(recording: recording, analyzedReps: analyzedReps)

        try Task.checkCancellation()
        return makeAnalysis(
            input: input,
            recording: recording,
            segmentation: segmentation,
            analyzedReps: analyzedReps,
            comparison: comparison
        )
    }

    private func validate(input: AnalysisInput, recording: PoseRecording) throws {
        guard input.mode == .dryFire else {
            throw SessionAnalysisError.invalidRecording
        }
        guard input.targetRepCount > 0,
              input.configuration.smoothingAlpha >= 0,
              input.configuration.smoothingAlpha <= 1,
              input.configuration.comparisonPhaseSampleCount > 0,
              input.configuration.minimumComparisonJointCoverage > 0,
              input.configuration.minimumComparisonJointCoverage <= 1,
              input.configuration.minimumUsableComparisonJoints > 0,
              input.configuration.similarityErrorScale > 0,
              input.configuration.minimumRepsForSessionConsistency > 0,
              input.configuration.minimumRepsForOutlierDetection > 0 else {
            throw SessionAnalysisError.invalidAnalysisConfiguration
        }
        guard recording.calibrationResult.normalizationScale > 0,
              recording.calibrationResult.normalizationScale.isFinite else {
            throw SessionAnalysisError.unusableCalibration
        }
        guard recording.poseFrames.count >= 2 else {
            throw SessionAnalysisError.insufficientPoseData
        }
    }

    private func makeAnalysis(
        input: AnalysisInput,
        recording: PoseRecording,
        segmentation: SegmentationResult,
        analyzedReps: [AnalyzedRep],
        comparison: SessionComparisonResult
    ) -> SessionAnalysis {
        let validReps = analyzedReps.filter { $0.segment.validity == .valid }
        let degradedReps = analyzedReps.filter { $0.segment.validity == .degraded }
        let invalidReps = analyzedReps.filter { $0.segment.validity == .invalid }
        let durations = validReps.compactMap { rep in
            rep.metrics.duration.availability == .available ? rep.metrics.duration.value : nil
        }.filter(\.isFinite)
        let averageDuration = durations.isEmpty ? nil : durations.reduce(0, +) / Double(durations.count)
        let reasons = reasons(
            targetRepCount: input.targetRepCount,
            segmentation: segmentation,
            analyzedReps: analyzedReps,
            comparison: comparison,
            averageDuration: averageDuration
        )
        let status = status(validRepCount: validReps.count, reasons: reasons)
        let confidence = confidence(
            status: status,
            calibration: recording.calibrationResult,
            validReps: validReps,
            comparison: comparison,
            reasons: reasons
        )

        return SessionAnalysis(
            sessionID: input.sessionID,
            recordingID: recording.id,
            mode: input.mode,
            recordingStartTimestampSeconds: recording.startTimestampSeconds,
            recordingEndTimestampSeconds: recording.endTimestampSeconds,
            recordingMetadata: recording.metadata,
            sourceRecording: recording,
            analysisVersion: VersionCatalog.current.analysisVersion,
            analysisConfigurationVersion: input.configuration.version,
            targetRepCount: input.targetRepCount,
            actualSegmentedRepCount: segmentation.segments.count,
            validRepCount: validReps.count,
            degradedRepCount: degradedReps.count,
            invalidRepCount: invalidReps.count,
            averageValidRepDurationSeconds: averageDuration,
            analyzedReps: analyzedReps.sorted { $0.sequenceIndex < $1.sequenceIndex },
            representativeRepID: comparison.representativeRepID,
            fastestRepID: comparison.fastestRepID,
            movementOutlierRepIDs: comparison.outlierRepIDs,
            movementConsistency: comparison.consistency,
            comparisonResult: comparison,
            segmentationResult: segmentation,
            overallConfidence: confidence,
            status: status,
            reasons: reasons.isEmpty ? [.none] : reasons,
            durationDiagnostics: SessionAnalysisDurationDiagnostics(
                aggregation: .arithmeticMeanOfValidReps,
                eligibleRepCount: durations.count
            )
        )
    }

    private func reasons(
        targetRepCount: Int,
        segmentation: SegmentationResult,
        analyzedReps: [AnalyzedRep],
        comparison: SessionComparisonResult,
        averageDuration: Double?
    ) -> [SessionAnalysisReason] {
        var reasons: [SessionAnalysisReason] = []
        let validCount = analyzedReps.filter { $0.segment.validity == .valid }.count
        if validCount == 0 {
            reasons.append(.noValidReps)
        }
        if segmentation.status == .degraded || !segmentation.failureReasons.isEmpty {
            reasons.append(.degradedSegmentation)
        }
        if validCount < targetRepCount {
            reasons.append(.fewerThanTargetReps)
        } else if validCount > targetRepCount {
            reasons.append(.moreThanTargetReps)
        }
        if analyzedReps.contains(where: { $0.metrics.aggregateConfidence != .high }) || averageDuration == nil {
            reasons.append(.metricUnavailable)
        }
        if comparison.consistency.availability == .unavailable {
            reasons.append(.comparisonUnavailable)
        }
        return reasons
    }

    private func status(
        validRepCount: Int,
        reasons: [SessionAnalysisReason]
    ) -> SessionAnalysisStatus {
        if validRepCount == 0 {
            return .noValidReps
        }
        let degradationReasons: Set<SessionAnalysisReason> = [
            .degradedSegmentation,
            .fewerThanTargetReps,
            .moreThanTargetReps,
            .metricUnavailable,
            .comparisonUnavailable,
            .degradedCalibration
        ]
        return reasons.contains(where: { degradationReasons.contains($0) }) ? .degraded : .completed
    }

    private func confidence(
        status: SessionAnalysisStatus,
        calibration: CalibrationResult,
        validReps: [AnalyzedRep],
        comparison: SessionComparisonResult,
        reasons: [SessionAnalysisReason]
    ) -> ConfidenceStatus {
        guard status == .completed || status == .degraded else {
            return .low
        }
        if calibration.quality.confidenceStatus == .low || validReps.isEmpty {
            return .low
        }
        if reasons.contains(.metricUnavailable) || reasons.contains(.comparisonUnavailable) || comparison.confidence != .high {
            return .medium
        }
        if calibration.quality.confidenceStatus == .medium || validReps.contains(where: { $0.metrics.aggregateConfidence != .high }) {
            return .medium
        }
        return .high
    }

    private func map(segmentationError: SegmentationError) -> SessionAnalysisError {
        switch segmentationError {
        case .invalidConfiguration:
            return .invalidAnalysisConfiguration
        case .unusableCalibration:
            return .unusableCalibration
        case .insufficientPoseData:
            return .insufficientPoseData
        case .invalidTimestampSequence:
            return .invalidRecording
        }
    }
}

public struct UnimplementedSessionAnalyzer: SessionAnalyzing {
    public init() {}

    public func analyze(_ input: AnalysisInput) async throws -> SessionAnalysis {
        throw ServiceBoundaryError.notImplemented
    }
}
