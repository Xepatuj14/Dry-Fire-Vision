import Foundation

public actor FileMediaAssetStore: MediaAssetStoring {
    private let rootDirectory: URL
    private let fileManager: FileManager

    public init(rootDirectory: URL, fileManager: FileManager = .default) {
        self.rootDirectory = rootDirectory
        self.fileManager = fileManager
    }

    public static func applicationSupportStore(fileManager: FileManager = .default) throws -> FileMediaAssetStore {
        let applicationSupport = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return FileMediaAssetStore(
            rootDirectory: applicationSupport.appendingPathComponent("DryFireVision", isDirectory: true),
            fileManager: fileManager
        )
    }

    public func exists(_ media: AppOwnedMediaAssetReference) async throws -> Bool {
        fileManager.fileExists(atPath: try url(for: media).path)
    }

    public func delete(_ media: AppOwnedMediaAssetReference) async throws {
        do {
            let resolved = try url(for: media)
            if fileManager.fileExists(atPath: resolved.path) {
                try fileManager.removeItem(at: resolved)
            }
            guard !fileManager.fileExists(atPath: resolved.path) else {
                throw PersistenceError.mediaDeleteFailed
            }
        } catch let error as PersistenceError {
            throw error
        } catch {
            throw PersistenceError.mediaDeleteFailed
        }
    }

    public func deleteAllMedia(for sessionID: UUID) async throws {
        do {
            let resolved = try sessionMediaDirectory(for: sessionID)
            if fileManager.fileExists(atPath: resolved.path) {
                try fileManager.removeItem(at: resolved)
            }
        } catch let error as PersistenceError {
            throw error
        } catch {
            throw PersistenceError.mediaDeleteFailed
        }
    }

    private func url(for media: AppOwnedMediaAssetReference) throws -> URL {
        let parts = media.relativePath.split(separator: "/").map(String.init)
        guard !media.relativePath.hasPrefix("/"),
              !media.relativePath.contains("\\"),
              !parts.contains(".."),
              parts.count >= 4,
              parts[0] == "Media",
              parts[1] == "Sessions",
              parts[2] == media.sessionID.uuidString else {
            throw PersistenceError.integrityViolation(.invalidMediaAssetReference)
        }
        return parts.reduce(rootDirectory) { partial, component in
            partial.appendingPathComponent(component, isDirectory: false)
        }
    }

    private func sessionMediaDirectory(for sessionID: UUID) throws -> URL {
        try url(for: AppOwnedMediaAssetReference(
            sessionID: sessionID,
            relativePath: "Media/Sessions/\(sessionID.uuidString)/placeholder"
        )).deletingLastPathComponent()
    }
}
