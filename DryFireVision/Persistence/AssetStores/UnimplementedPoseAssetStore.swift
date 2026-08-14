import Foundation

public struct UnimplementedPoseAssetStore: PoseAssetStoring {
    public init() {}

    public func save(_ payload: PoseAssetPayload, sessionID: UUID, repID: UUID?, assetType: PoseAssetType) async throws -> SavedPoseAsset {
        throw ServiceBoundaryError.notImplemented
    }

    public func load(storageLocation: String) async throws -> PoseAssetPayload {
        throw ServiceBoundaryError.notImplemented
    }

    public func exists(storageLocation: String) async -> Bool {
        false
    }

    public func delete(storageLocation: String) async throws {
        throw ServiceBoundaryError.notImplemented
    }

    public func deleteAllAssets(for sessionID: UUID) async throws {
        throw ServiceBoundaryError.notImplemented
    }
}
