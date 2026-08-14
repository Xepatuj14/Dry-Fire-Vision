import Foundation
import SwiftData

public enum MediaAssetType: String, Codable, Equatable, Sendable {
    case video
}

@Model
public final class PersistedMediaAssetReference {
    public var id: UUID
    public var sessionID: UUID
    public var mediaType: String
    public var relativePath: String?
    public var createdAt: Date
    public var durationSeconds: Double?
    public var fileSizeBytes: Int?
    public var retentionState: String
    public var checksum: String?

    public var session: PersistedTrainingSession?

    public init(
        id: UUID,
        sessionID: UUID,
        mediaType: String,
        relativePath: String?,
        createdAt: Date,
        durationSeconds: Double?,
        fileSizeBytes: Int?,
        retentionState: String,
        checksum: String?
    ) {
        self.id = id
        self.sessionID = sessionID
        self.mediaType = mediaType
        self.relativePath = relativePath
        self.createdAt = createdAt
        self.durationSeconds = durationSeconds
        self.fileSizeBytes = fileSizeBytes
        self.retentionState = retentionState
        self.checksum = checksum
    }
}
