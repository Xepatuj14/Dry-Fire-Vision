import Foundation

public struct PoseRecordingMetadata: Codable, Equatable, Sendable {
    public let cameraPerspective: String
    public let captureOrientation: String
    public let nominalCaptureFPS: Double?
    public let effectivePoseFPS: Double?
    public let acceptedPoseFrameCount: Int
    public let rejectedPoseFrameCount: Int
    public let coordinateConventionVersion: String
    public let jointSetVersion: String
    public let poseEncodingVersion: String

    public init(
        cameraPerspective: String = "unspecified",
        captureOrientation: String = "portrait",
        nominalCaptureFPS: Double? = nil,
        effectivePoseFPS: Double? = nil,
        acceptedPoseFrameCount: Int = 0,
        rejectedPoseFrameCount: Int = 0,
        coordinateConventionVersion: String = VersionCatalog.current.coordinateConventionVersion,
        jointSetVersion: String = VersionCatalog.current.jointSetVersion,
        poseEncodingVersion: String = VersionCatalog.current.poseEncodingVersion
    ) {
        self.cameraPerspective = cameraPerspective
        self.captureOrientation = captureOrientation
        self.nominalCaptureFPS = nominalCaptureFPS
        self.effectivePoseFPS = effectivePoseFPS
        self.acceptedPoseFrameCount = acceptedPoseFrameCount
        self.rejectedPoseFrameCount = rejectedPoseFrameCount
        self.coordinateConventionVersion = coordinateConventionVersion
        self.jointSetVersion = jointSetVersion
        self.poseEncodingVersion = poseEncodingVersion
    }

    public func finalized(
        durationSeconds: Double,
        acceptedPoseFrameCount: Int,
        rejectedPoseFrameCount: Int
    ) -> PoseRecordingMetadata {
        PoseRecordingMetadata(
            cameraPerspective: cameraPerspective,
            captureOrientation: captureOrientation,
            nominalCaptureFPS: nominalCaptureFPS,
            effectivePoseFPS: durationSeconds > 0 ? Double(acceptedPoseFrameCount) / durationSeconds : nil,
            acceptedPoseFrameCount: acceptedPoseFrameCount,
            rejectedPoseFrameCount: rejectedPoseFrameCount,
            coordinateConventionVersion: coordinateConventionVersion,
            jointSetVersion: jointSetVersion,
            poseEncodingVersion: poseEncodingVersion
        )
    }
}
