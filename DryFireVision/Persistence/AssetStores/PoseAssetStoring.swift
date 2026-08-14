import Foundation

public struct SavedPoseAsset: Equatable, Sendable {
    public let id: UUID
    public let sessionID: UUID
    public let repID: UUID?
    public let assetType: PoseAssetType
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
        repID: UUID?,
        assetType: PoseAssetType,
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

public protocol PoseAssetStoring: Sendable {
    func save(_ payload: PoseAssetPayload, sessionID: UUID, repID: UUID?, assetType: PoseAssetType) async throws -> SavedPoseAsset
    func load(storageLocation: String) async throws -> PoseAssetPayload
    func exists(storageLocation: String) async -> Bool
    func delete(storageLocation: String) async throws
    func deleteAllAssets(for sessionID: UUID) async throws
}
