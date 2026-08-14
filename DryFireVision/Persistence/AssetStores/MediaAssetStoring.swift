import Foundation

public struct AppOwnedMediaAssetReference: Equatable, Sendable {
    public let sessionID: UUID
    public let relativePath: String
    public let durationSeconds: Double?
    public let fileSizeBytes: Int?
    public let checksum: String?

    public init(
        sessionID: UUID,
        relativePath: String,
        durationSeconds: Double? = nil,
        fileSizeBytes: Int? = nil,
        checksum: String? = nil
    ) {
        self.sessionID = sessionID
        self.relativePath = relativePath
        self.durationSeconds = durationSeconds
        self.fileSizeBytes = fileSizeBytes
        self.checksum = checksum
    }
}

public protocol MediaAssetStoring: Sendable {
    func exists(_ media: AppOwnedMediaAssetReference) async throws -> Bool
    func delete(_ media: AppOwnedMediaAssetReference) async throws
    func deleteAllMedia(for sessionID: UUID) async throws
}

public struct UnimplementedMediaAssetStore: MediaAssetStoring {
    public init() {}

    public func exists(_ media: AppOwnedMediaAssetReference) async throws -> Bool {
        false
    }

    public func delete(_ media: AppOwnedMediaAssetReference) async throws {}

    public func deleteAllMedia(for sessionID: UUID) async throws {}
}
