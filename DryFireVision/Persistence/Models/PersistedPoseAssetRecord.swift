import Foundation
import SwiftData

public enum PoseAssetType: String, Codable, Equatable, Sendable {
    case baseline
    case repTrajectory
    case fullSessionFixture
    case recoveryWindow
}

@Model
public final class PersistedPoseAssetRecord {
    public var id: UUID
    public var sessionID: UUID
    public var repID: UUID?
    public var assetType: String
    public var storageLocation: String
    public var encodingVersion: String
    public var sampleCount: Int
    public var startTimestamp: Double?
    public var endTimestamp: Double?
    public var jointSetVersion: String
    public var coordinateConventionVersion: String
    public var checksum: String?

    public var session: PersistedTrainingSession?

    public init(
        id: UUID,
        sessionID: UUID,
        repID: UUID?,
        assetType: String,
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
        self.assetType = assetType
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
