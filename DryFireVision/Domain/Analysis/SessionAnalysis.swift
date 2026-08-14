import Foundation

public enum SessionAnalysisStatus: String, Codable, Equatable, Sendable {
    case completed
    case degraded
    case noValidReps
    case failed
}

public enum SessionAnalysisReason: String, Codable, Equatable, Hashable, Sendable {
    case none
    case invalidRecording
    case unusableCalibration
    case segmentationFailed
    case insufficientPoseData
    case invalidAnalysisConfiguration
    case noValidReps
    case comparisonUnavailable
    case metricUnavailable
    case fewerThanTargetReps
    case moreThanTargetReps
    case degradedCalibration
    case degradedSegmentation
    case internalAnalysisFailure
}

public struct SessionAnalysis: Equatable, Sendable {
    public let sessionID: UUID
    public let recordingID: UUID?
    public let mode: SessionMode
    public let recordingStartTimestampSeconds: Double?
    public let recordingEndTimestampSeconds: Double?
    public let recordingMetadata: PoseRecordingMetadata?
    public let sourceRecording: PoseRecording?
    public let analysisVersion: String
    public let analysisConfigurationVersion: String
    public let targetRepCount: Int
    public let actualSegmentedRepCount: Int
    public let validRepCount: Int
    public let degradedRepCount: Int
    public let invalidRepCount: Int
    public let averageValidRepDurationSeconds: Double?
    public let analyzedReps: [AnalyzedRep]
    public let representativeRepID: UUID?
    public let fastestRepID: UUID?
    public let movementOutlierRepIDs: [UUID]
    public let movementConsistency: SessionConsistencyResult
    public let comparisonResult: SessionComparisonResult?
    public let segmentationResult: SegmentationResult?
    public let overallConfidence: ConfidenceStatus
    public let status: SessionAnalysisStatus
    public let reasons: [SessionAnalysisReason]
    public let durationDiagnostics: SessionAnalysisDurationDiagnostics

    public init(
        sessionID: UUID,
        recordingID: UUID? = nil,
        mode: SessionMode,
        recordingStartTimestampSeconds: Double? = nil,
        recordingEndTimestampSeconds: Double? = nil,
        recordingMetadata: PoseRecordingMetadata? = nil,
        sourceRecording: PoseRecording? = nil,
        analysisVersion: String = VersionCatalog.current.analysisVersion,
        analysisConfigurationVersion: String,
        targetRepCount: Int = 10,
        actualSegmentedRepCount: Int = 0,
        validRepCount: Int = 0,
        degradedRepCount: Int = 0,
        invalidRepCount: Int = 0,
        averageValidRepDurationSeconds: Double? = nil,
        analyzedReps: [AnalyzedRep] = [],
        representativeRepID: UUID? = nil,
        fastestRepID: UUID? = nil,
        movementOutlierRepIDs: [UUID] = [],
        movementConsistency: SessionConsistencyResult = .unavailable(reason: .insufficientEligibleReps),
        comparisonResult: SessionComparisonResult? = nil,
        segmentationResult: SegmentationResult? = nil,
        overallConfidence: ConfidenceStatus = .low,
        status: SessionAnalysisStatus = .failed,
        reasons: [SessionAnalysisReason] = [],
        durationDiagnostics: SessionAnalysisDurationDiagnostics = SessionAnalysisDurationDiagnostics()
    ) {
        self.sessionID = sessionID
        self.recordingID = recordingID
        self.mode = mode
        self.recordingStartTimestampSeconds = recordingStartTimestampSeconds
        self.recordingEndTimestampSeconds = recordingEndTimestampSeconds
        self.recordingMetadata = recordingMetadata
        self.sourceRecording = sourceRecording
        self.analysisVersion = analysisVersion
        self.analysisConfigurationVersion = analysisConfigurationVersion
        self.targetRepCount = targetRepCount
        self.actualSegmentedRepCount = actualSegmentedRepCount
        self.validRepCount = validRepCount
        self.degradedRepCount = degradedRepCount
        self.invalidRepCount = invalidRepCount
        self.averageValidRepDurationSeconds = averageValidRepDurationSeconds?.isFinite == true ? averageValidRepDurationSeconds : nil
        self.analyzedReps = analyzedReps
        self.representativeRepID = representativeRepID
        self.fastestRepID = fastestRepID
        self.movementOutlierRepIDs = movementOutlierRepIDs
        self.movementConsistency = movementConsistency
        self.comparisonResult = comparisonResult
        self.segmentationResult = segmentationResult
        self.overallConfidence = overallConfidence
        self.status = status
        self.reasons = reasons.isEmpty ? [.none] : reasons
        self.durationDiagnostics = durationDiagnostics
    }
}

public struct SessionAnalysisDurationDiagnostics: Equatable, Sendable {
    public let aggregation: SessionDurationAggregation
    public let eligibleRepCount: Int

    public init(
        aggregation: SessionDurationAggregation = .arithmeticMeanOfValidReps,
        eligibleRepCount: Int = 0
    ) {
        self.aggregation = aggregation
        self.eligibleRepCount = eligibleRepCount
    }
}

public enum SessionDurationAggregation: String, Codable, Equatable, Sendable {
    case arithmeticMeanOfValidReps
}

public extension SessionConsistencyResult {
    static func unavailable(reason: ComparisonUnavailableReason) -> SessionConsistencyResult {
        SessionConsistencyResult(
            availability: .unavailable,
            internalValue: nil,
            confidence: .low,
            reason: reason
        )
    }
}
