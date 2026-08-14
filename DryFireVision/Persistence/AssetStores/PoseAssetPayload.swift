import Foundation

public struct PoseAssetPayload: Codable, Equatable, Sendable {
    public let encodingVersion: String
    public let coordinateConventionVersion: String
    public let jointSetVersion: String
    public let normalizationScale: Double
    public let normalizationScaleSource: NormalizationScaleSource
    public let frames: [PoseAssetFrame]

    public init(
        encodingVersion: String = VersionCatalog.current.poseEncodingVersion,
        coordinateConventionVersion: String = VersionCatalog.current.coordinateConventionVersion,
        jointSetVersion: String = VersionCatalog.current.jointSetVersion,
        normalizationScale: Double,
        normalizationScaleSource: NormalizationScaleSource,
        frames: [PoseAssetFrame]
    ) {
        self.encodingVersion = encodingVersion
        self.coordinateConventionVersion = coordinateConventionVersion
        self.jointSetVersion = jointSetVersion
        self.normalizationScale = normalizationScale
        self.normalizationScaleSource = normalizationScaleSource
        self.frames = frames
    }

    public init(recording: PoseRecording, frames: [PoseFrame]) {
        self.init(
            encodingVersion: recording.metadata.poseEncodingVersion,
            coordinateConventionVersion: recording.metadata.coordinateConventionVersion,
            jointSetVersion: recording.metadata.jointSetVersion,
            normalizationScale: recording.calibrationResult.normalizationScale,
            normalizationScaleSource: recording.calibrationResult.normalizationScaleSource,
            frames: frames.map(PoseAssetFrame.init)
        )
    }
}

public struct PoseAssetFrame: Codable, Equatable, Sendable {
    public let timestampSeconds: Double
    public let joints: [PoseAssetJointSample]

    public init(timestampSeconds: Double, joints: [PoseAssetJointSample]) {
        self.timestampSeconds = timestampSeconds
        self.joints = joints
    }

    public init(_ frame: PoseFrame) {
        self.timestampSeconds = frame.timestampSeconds
        self.joints = frame.joints.keys.sorted { $0.rawValue < $1.rawValue }.compactMap { jointID in
            frame.joints[jointID].map(PoseAssetJointSample.init)
        }
    }
}

public struct PoseAssetJointSample: Codable, Equatable, Sendable {
    public let jointID: PoseJointID
    public let x: Double
    public let y: Double
    public let confidence: Double

    public init(jointID: PoseJointID, x: Double, y: Double, confidence: Double) {
        self.jointID = jointID
        self.x = x
        self.y = y
        self.confidence = confidence
    }

    public init(_ sample: JointSample) {
        self.init(
            jointID: sample.jointID,
            x: sample.x,
            y: sample.y,
            confidence: sample.confidence
        )
    }
}
