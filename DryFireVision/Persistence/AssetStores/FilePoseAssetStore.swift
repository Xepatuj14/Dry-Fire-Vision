import Foundation

public actor FilePoseAssetStore: PoseAssetStoring {
    private let rootDirectory: URL
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(rootDirectory: URL, fileManager: FileManager = .default) {
        self.rootDirectory = rootDirectory
        self.fileManager = fileManager
        self.encoder = JSONEncoder()
        self.encoder.outputFormatting = [.sortedKeys]
        self.decoder = JSONDecoder()
    }

    public static func applicationSupportStore(fileManager: FileManager = .default) throws -> FilePoseAssetStore {
        let applicationSupport = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return FilePoseAssetStore(
            rootDirectory: applicationSupport.appendingPathComponent("DryFireVision", isDirectory: true),
            fileManager: fileManager
        )
    }

    public func save(
        _ payload: PoseAssetPayload,
        sessionID: UUID,
        repID: UUID?,
        assetType: PoseAssetType
    ) async throws -> SavedPoseAsset {
        guard payload.encodingVersion == VersionCatalog.current.poseEncodingVersion else {
            throw PersistenceError.unsupportedPayloadVersion(payload.encodingVersion)
        }
        guard payloadContainsOnlyFiniteNumbers(payload) else {
            throw PersistenceError.integrityViolation(.nonFiniteMetric)
        }

        let id = UUID()
        let location = relativeLocation(sessionID: sessionID, assetID: id)
        let url = try url(for: location)
        do {
            try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try encoder.encode(payload)
            try data.write(to: url, options: [.atomic])
            guard fileManager.fileExists(atPath: url.path) else {
                throw PersistenceError.poseAssetWriteFailed
            }
            return SavedPoseAsset(
                id: id,
                sessionID: sessionID,
                repID: repID,
                assetType: assetType,
                storageLocation: location,
                encodingVersion: payload.encodingVersion,
                sampleCount: payload.frames.count,
                startTimestamp: payload.frames.first?.timestampSeconds,
                endTimestamp: payload.frames.last?.timestampSeconds,
                jointSetVersion: payload.jointSetVersion,
                coordinateConventionVersion: payload.coordinateConventionVersion,
                checksum: nil
            )
        } catch let error as PersistenceError {
            throw error
        } catch {
            throw PersistenceError.poseAssetWriteFailed
        }
    }

    public func load(storageLocation: String) async throws -> PoseAssetPayload {
        do {
            let data = try Data(contentsOf: try url(for: storageLocation))
            let payload = try decoder.decode(PoseAssetPayload.self, from: data)
            guard payload.encodingVersion == VersionCatalog.current.poseEncodingVersion else {
                throw PersistenceError.unsupportedPayloadVersion(payload.encodingVersion)
            }
            return payload
        } catch let error as PersistenceError {
            throw error
        } catch {
            throw PersistenceError.poseAssetReadFailed
        }
    }

    public func exists(storageLocation: String) async -> Bool {
        guard let resolved = try? url(for: storageLocation) else {
            return false
        }
        return fileManager.fileExists(atPath: resolved.path)
    }

    public func delete(storageLocation: String) async throws {
        do {
            let resolved = try url(for: storageLocation)
            if fileManager.fileExists(atPath: resolved.path) {
                try fileManager.removeItem(at: resolved)
            }
        } catch {
            throw PersistenceError.poseAssetDeleteFailed
        }
    }

    public func deleteAllAssets(for sessionID: UUID) async throws {
        let location = "Pose/Sessions/\(sessionID.uuidString)"
        do {
            let resolved = try url(for: location)
            if fileManager.fileExists(atPath: resolved.path) {
                try fileManager.removeItem(at: resolved)
            }
        } catch {
            throw PersistenceError.poseAssetDeleteFailed
        }
    }

    private func relativeLocation(sessionID: UUID, assetID: UUID) -> String {
        "Pose/Sessions/\(sessionID.uuidString)/\(assetID.uuidString).dfvpose.json"
    }

    private func url(for storageLocation: String) throws -> URL {
        let parts = storageLocation.split(separator: "/").map(String.init)
        guard !storageLocation.hasPrefix("/"),
              !storageLocation.contains("\\"),
              !parts.contains(".."),
              !parts.isEmpty else {
            throw PersistenceError.integrityViolation(.invalidPoseAssetReference)
        }
        return parts.reduce(rootDirectory) { partial, component in
            partial.appendingPathComponent(component, isDirectory: false)
        }
    }

    private func payloadContainsOnlyFiniteNumbers(_ payload: PoseAssetPayload) -> Bool {
        guard payload.normalizationScale.isFinite else {
            return false
        }
        return payload.frames.allSatisfy { frame in
            frame.timestampSeconds.isFinite &&
                frame.joints.allSatisfy { joint in
                    joint.x.isFinite && joint.y.isFinite && joint.confidence.isFinite
                }
        }
    }
}
