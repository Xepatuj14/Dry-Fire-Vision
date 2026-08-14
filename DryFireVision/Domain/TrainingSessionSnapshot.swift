import Foundation

public struct TrainingSessionSnapshot: Equatable, Identifiable, Sendable {
    public let id: UUID
    public let mode: SessionMode
    public let status: SessionAnalysisStatus
    public let createdAt: Date
    public let analysisVersion: String
    public let analysisConfigurationVersion: String
    public let analysis: SessionAnalysis?
    public let poseAssetAvailability: PoseAssetAvailability
    public let videoRetentionState: VideoRetentionState
    public let videoMediaAvailability: VideoMediaAvailability

    public init(
        id: UUID,
        mode: SessionMode,
        status: SessionAnalysisStatus = .failed,
        createdAt: Date = Date(timeIntervalSince1970: 0),
        analysisVersion: String = VersionCatalog.current.analysisVersion,
        analysisConfigurationVersion: String = VersionCatalog.current.analysisConfigurationVersion,
        analysis: SessionAnalysis? = nil,
        poseAssetAvailability: PoseAssetAvailability = .notChecked,
        videoRetentionState: VideoRetentionState = .notRecorded,
        videoMediaAvailability: VideoMediaAvailability = .notRecorded
    ) {
        self.id = id
        self.mode = mode
        self.status = status
        self.createdAt = createdAt
        self.analysisVersion = analysisVersion
        self.analysisConfigurationVersion = analysisConfigurationVersion
        self.analysis = analysis
        self.poseAssetAvailability = poseAssetAvailability
        self.videoRetentionState = videoRetentionState
        self.videoMediaAvailability = videoMediaAvailability
    }
}

public enum PoseAssetAvailability: String, Codable, Equatable, Sendable {
    case available
    case missing
    case corrupt
    case unavailable
    case notChecked
}

public enum VideoRetentionState: String, Codable, Equatable, Sendable {
    case keep
    case pendingDelete
    case deleted
    case deletionFailed
    case notRecorded
}

public enum VideoRetentionPreference: String, Codable, CaseIterable, Equatable, Sendable {
    case keep
    case analyzeAndDelete

    public var title: String {
        switch self {
        case .keep:
            return "Keep Video"
        case .analyzeAndDelete:
            return "Analyze & Delete"
        }
    }

    public var setupSummary: String {
        switch self {
        case .keep:
            return "Raw app-owned video is retained when video recording is available."
        case .analyzeAndDelete:
            return "Raw app-owned video is removed only after analysis and required saves complete."
        }
    }
}

public enum VideoMediaAvailability: String, Codable, Equatable, Sendable {
    case videoAvailable
    case videoDeletedByPreference
    case videoMissing
    case videoDeletionPending
    case videoDeletionFailed
    case notRecorded
    case unavailable
}

public enum SessionStatus: String, Codable, Equatable, Sendable {
    case draft
    case capturing
    case processing
    case completed
    case degraded
    case failed
    case cancelled
}
