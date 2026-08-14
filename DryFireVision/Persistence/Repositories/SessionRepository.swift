import Foundation

public protocol SessionRepository: Sendable {
    func save(_ analysis: SessionAnalysis) async throws -> UUID
    func save(
        _ analysis: SessionAnalysis,
        videoRetentionPreference: VideoRetentionPreference,
        rawVideo: AppOwnedMediaAssetReference?
    ) async throws -> UUID
    func session(id: UUID) async throws -> TrainingSessionSnapshot
    func poseAssetReference(sessionID: UUID, repID: UUID) async throws -> RepPoseAssetReference?
    func recentCompletedSessions(limit: Int) async throws -> [TrainingSessionSnapshot]
    func deleteSession(id: UUID) async throws
    func saveLiveFire(_ analysis: LiveFireSessionAnalysis, videoRetentionPreference: VideoRetentionPreference, rawVideo: AppOwnedMediaAssetReference?) async throws -> UUID
    func liveFireSession(id: UUID) async throws -> LiveFireSessionAnalysis
}

public extension SessionRepository {
    func save(_ analysis: SessionAnalysis) async throws -> UUID {
        try await save(analysis, videoRetentionPreference: .keep, rawVideo: nil)
    }

    func save(
        _ analysis: SessionAnalysis,
        videoRetentionPreference: VideoRetentionPreference,
        rawVideo: AppOwnedMediaAssetReference?
    ) async throws -> UUID {
        try await save(analysis)
    }

    func saveLiveFire(_ analysis: LiveFireSessionAnalysis, videoRetentionPreference: VideoRetentionPreference = .keep, rawVideo: AppOwnedMediaAssetReference? = nil) async throws -> UUID {
        throw ServiceBoundaryError.notImplemented
    }

    func liveFireSession(id: UUID) async throws -> LiveFireSessionAnalysis {
        throw ServiceBoundaryError.notImplemented
    }
}

public struct RepPoseAssetReference: Equatable, Sendable {
    public let id: UUID
    public let sessionID: UUID
    public let repID: UUID
    public let storageLocation: String
    public let encodingVersion: String
    public let sampleCount: Int
    public let startTimestamp: Double?
    public let endTimestamp: Double?
    public let jointSetVersion: String
    public let coordinateConventionVersion: String
    public let checksum: String?

    public init(
        id: UUID,
        sessionID: UUID,
        repID: UUID,
        storageLocation: String,
        encodingVersion: String,
        sampleCount: Int,
        startTimestamp: Double?,
        endTimestamp: Double?,
        jointSetVersion: String,
        coordinateConventionVersion: String,
        checksum: String?
    ) {
        self.id = id
        self.sessionID = sessionID
        self.repID = repID
        self.storageLocation = storageLocation
        self.encodingVersion = encodingVersion
        self.sampleCount = sampleCount
        self.startTimestamp = startTimestamp
        self.endTimestamp = endTimestamp
        self.jointSetVersion = jointSetVersion
        self.coordinateConventionVersion = coordinateConventionVersion
        self.checksum = checksum
    }
}

public struct UnimplementedSessionRepository: SessionRepository {
    public init() {}

    public func save(_ analysis: SessionAnalysis) async throws -> UUID {
        try await save(analysis, videoRetentionPreference: .keep, rawVideo: nil)
    }

    public func save(
        _ analysis: SessionAnalysis,
        videoRetentionPreference: VideoRetentionPreference,
        rawVideo: AppOwnedMediaAssetReference?
    ) async throws -> UUID {
        throw ServiceBoundaryError.notImplemented
    }

    public func session(id: UUID) async throws -> TrainingSessionSnapshot {
        throw ServiceBoundaryError.notImplemented
    }

    public func poseAssetReference(sessionID: UUID, repID: UUID) async throws -> RepPoseAssetReference? {
        throw ServiceBoundaryError.notImplemented
    }

    public func recentCompletedSessions(limit: Int) async throws -> [TrainingSessionSnapshot] {
        throw ServiceBoundaryError.notImplemented
    }

    public func deleteSession(id: UUID) async throws {
        throw ServiceBoundaryError.notImplemented
    }
}
