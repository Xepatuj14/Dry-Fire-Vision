import Foundation

public struct PoseFrame: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let timestampSeconds: Double
    public let joints: [PoseJointID: JointSample]
    public let coordinateConventionVersion: String
    public let jointSetVersion: String

    public init(
        id: UUID = UUID(),
        timestampSeconds: Double,
        joints: [PoseJointID: JointSample],
        coordinateConventionVersion: String = VersionCatalog.current.coordinateConventionVersion,
        jointSetVersion: String = VersionCatalog.current.jointSetVersion
    ) {
        self.id = id
        self.timestampSeconds = timestampSeconds
        self.joints = joints
        self.coordinateConventionVersion = coordinateConventionVersion
        self.jointSetVersion = jointSetVersion
    }

    public func sample(for jointID: PoseJointID) -> JointSample? {
        joints[jointID]
    }
}
