import Foundation

public struct VersionCatalog: Equatable, Sendable {
    public let persistenceSchemaVersion: Int
    public let analysisVersion: String
    public let analysisConfigurationVersion: String
    public let poseEncodingVersion: String
    public let jointSetVersion: String
    public let coordinateConventionVersion: String

    public init(
        persistenceSchemaVersion: Int,
        analysisVersion: String,
        analysisConfigurationVersion: String,
        poseEncodingVersion: String,
        jointSetVersion: String,
        coordinateConventionVersion: String
    ) {
        self.persistenceSchemaVersion = persistenceSchemaVersion
        self.analysisVersion = analysisVersion
        self.analysisConfigurationVersion = analysisConfigurationVersion
        self.poseEncodingVersion = poseEncodingVersion
        self.jointSetVersion = jointSetVersion
        self.coordinateConventionVersion = coordinateConventionVersion
    }

    public static let current = VersionCatalog(
        persistenceSchemaVersion: 2,
        analysisVersion: "1.0.0",
        analysisConfigurationVersion: "1.1.0",
        poseEncodingVersion: "1",
        jointSetVersion: "vision-body-2d-v1",
        coordinateConventionVersion: "dfv-normalized-2d-v1"
    )
}
