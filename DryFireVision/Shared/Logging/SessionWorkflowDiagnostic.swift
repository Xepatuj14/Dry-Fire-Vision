import Foundation

public struct SessionWorkflowDiagnostic: Equatable, Sendable {
    public let sessionID: UUID
    public let recordingID: UUID?
    public let poseSampleCount: Int
    public let acceptedPoseFrameCount: Int?
    public let captureDurationSeconds: Double?
    public let effectivePoseFPS: Double?
    public let targetRepCount: Int
    public let actualSegmentedRepCount: Int
    public let validRepCount: Int
    public let degradedRepCount: Int
    public let invalidRepCount: Int
    public let representativeRepID: UUID?
    public let fastestRepID: UUID?
    public let movementOutlierCount: Int
    public let movementConsistencyAvailable: Bool
    public let status: SessionAnalysisStatus
    public let reasons: [SessionAnalysisReason]
    public let persistedSessionID: UUID?
    public let failureCategory: SessionWorkflowFailureCategory?
    public let analysisVersion: String
    public let analysisConfigurationVersion: String

    public init(
        sessionID: UUID,
        recordingID: UUID?,
        poseSampleCount: Int,
        acceptedPoseFrameCount: Int?,
        captureDurationSeconds: Double?,
        effectivePoseFPS: Double?,
        targetRepCount: Int,
        actualSegmentedRepCount: Int,
        validRepCount: Int,
        degradedRepCount: Int,
        invalidRepCount: Int,
        representativeRepID: UUID?,
        fastestRepID: UUID?,
        movementOutlierCount: Int,
        movementConsistencyAvailable: Bool,
        status: SessionAnalysisStatus,
        reasons: [SessionAnalysisReason],
        persistedSessionID: UUID?,
        failureCategory: SessionWorkflowFailureCategory?,
        analysisVersion: String,
        analysisConfigurationVersion: String
    ) {
        self.sessionID = sessionID
        self.recordingID = recordingID
        self.poseSampleCount = poseSampleCount
        self.acceptedPoseFrameCount = acceptedPoseFrameCount
        self.captureDurationSeconds = captureDurationSeconds
        self.effectivePoseFPS = effectivePoseFPS
        self.targetRepCount = targetRepCount
        self.actualSegmentedRepCount = actualSegmentedRepCount
        self.validRepCount = validRepCount
        self.degradedRepCount = degradedRepCount
        self.invalidRepCount = invalidRepCount
        self.representativeRepID = representativeRepID
        self.fastestRepID = fastestRepID
        self.movementOutlierCount = movementOutlierCount
        self.movementConsistencyAvailable = movementConsistencyAvailable
        self.status = status
        self.reasons = reasons
        self.persistedSessionID = persistedSessionID
        self.failureCategory = failureCategory
        self.analysisVersion = analysisVersion
        self.analysisConfigurationVersion = analysisConfigurationVersion
    }

    public static func make(
        analysis: SessionAnalysis,
        persistedSessionID: UUID?,
        failureCategory: SessionWorkflowFailureCategory? = nil
    ) -> SessionWorkflowDiagnostic {
        let poseSampleCount = analysis.sourceRecording?.poseFrames.count ?? analysis.recordingMetadata?.acceptedPoseFrameCount ?? 0
        let captureDuration = captureDurationSeconds(
            start: analysis.recordingStartTimestampSeconds,
            end: analysis.recordingEndTimestampSeconds
        )
        let effectivePoseFPS = analysis.recordingMetadata?.effectivePoseFPS ?? derivedFPS(
            poseSampleCount: poseSampleCount,
            durationSeconds: captureDuration
        )

        return SessionWorkflowDiagnostic(
            sessionID: analysis.sessionID,
            recordingID: analysis.recordingID,
            poseSampleCount: poseSampleCount,
            acceptedPoseFrameCount: analysis.recordingMetadata?.acceptedPoseFrameCount,
            captureDurationSeconds: captureDuration,
            effectivePoseFPS: effectivePoseFPS,
            targetRepCount: analysis.targetRepCount,
            actualSegmentedRepCount: analysis.actualSegmentedRepCount,
            validRepCount: analysis.validRepCount,
            degradedRepCount: analysis.degradedRepCount,
            invalidRepCount: analysis.invalidRepCount,
            representativeRepID: analysis.representativeRepID,
            fastestRepID: analysis.fastestRepID,
            movementOutlierCount: analysis.movementOutlierRepIDs.count,
            movementConsistencyAvailable: analysis.movementConsistency.availability == .available,
            status: analysis.status,
            reasons: analysis.reasons,
            persistedSessionID: persistedSessionID,
            failureCategory: failureCategory,
            analysisVersion: analysis.analysisVersion,
            analysisConfigurationVersion: analysis.analysisConfigurationVersion
        )
    }

    private static func captureDurationSeconds(start: Double?, end: Double?) -> Double? {
        guard let start,
              let end else {
            return nil
        }
        let duration = end - start
        return duration.isFinite && duration >= 0 ? duration : nil
    }

    private static func derivedFPS(poseSampleCount: Int, durationSeconds: Double?) -> Double? {
        guard let durationSeconds,
              durationSeconds > 0,
              poseSampleCount > 0 else {
            return nil
        }
        let fps = Double(poseSampleCount) / durationSeconds
        return fps.isFinite ? fps : nil
    }
}

public enum SessionWorkflowFailureCategory: String, Codable, Equatable, Sendable {
    case analysis
    case persistence
}
