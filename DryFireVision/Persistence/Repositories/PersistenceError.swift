import Foundation

public enum PersistenceError: Error, Equatable, Sendable {
    case databaseWriteFailed
    case databaseReadFailed
    case sessionSaveFailed
    case poseAssetWriteFailed
    case poseAssetReadFailed
    case poseAssetDeleteFailed
    case mediaDeleteFailed
    case mediaReadFailed
    case integrityViolation(PersistenceIntegrityReason)
    case migrationFailed
    case unsupportedPayloadVersion(String)
    case sessionNotFound(UUID)
}

public enum PersistenceIntegrityReason: String, Codable, Equatable, Sendable {
    case unsupportedSessionMode
    case unsupportedSessionStatus
    case representativeRepOutsideSession
    case fastestRepOutsideSession
    case outlierRepOutsideSession
    case repOutsideSession
    case nonFiniteMetric
    case missingPoseAssetFile
    case invalidPoseAssetReference
    case invalidMediaAssetReference
    case missingSessionRelationship
}
