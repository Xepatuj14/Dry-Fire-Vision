import Foundation
import SwiftData

public enum DryFireVisionPersistenceSchema {
    public static let currentVersion = VersionCatalog.current.persistenceSchemaVersion

    public static var schema: Schema {
        Schema([
            PersistedTrainingSession.self,
            PersistedRepRecord.self,
            PersistedCalibrationRecord.self,
            PersistedPoseAssetRecord.self,
            PersistedMediaAssetReference.self,
            PersistedLiveEventRecord.self
        ])
    }
}
