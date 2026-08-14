import CoreGraphics
import Foundation

public enum PosePlaybackContentMode: Equatable, Sendable {
    case aspectFit
    case aspectFill
}

public struct PosePlaybackDisplayMapper: Sendable {
    public let sourceAspectRatio: Double
    public let contentMode: PosePlaybackContentMode
    public let isMirrored: Bool

    public init(
        sourceAspectRatio: Double = 9.0 / 16.0,
        contentMode: PosePlaybackContentMode = .aspectFit,
        isMirrored: Bool = false
    ) {
        self.sourceAspectRatio = sourceAspectRatio
        self.contentMode = contentMode
        self.isMirrored = isMirrored
    }

    public func displayPoint(x: Double, y: Double, in size: CGSize) -> CGPoint {
        let safeWidth = max(Double(size.width), 1)
        let safeHeight = max(Double(size.height), 1)
        let targetAspectRatio = safeWidth / safeHeight
        let imageWidth: Double
        let imageHeight: Double
        let offsetX: Double
        let offsetY: Double

        switch contentMode {
        case .aspectFit:
            if targetAspectRatio > sourceAspectRatio {
                imageHeight = safeHeight
                imageWidth = imageHeight * sourceAspectRatio
                offsetX = (safeWidth - imageWidth) / 2
                offsetY = 0
            } else {
                imageWidth = safeWidth
                imageHeight = imageWidth / sourceAspectRatio
                offsetX = 0
                offsetY = (safeHeight - imageHeight) / 2
            }
        case .aspectFill:
            if targetAspectRatio > sourceAspectRatio {
                imageWidth = safeWidth
                imageHeight = imageWidth / sourceAspectRatio
                offsetX = 0
                offsetY = (safeHeight - imageHeight) / 2
            } else {
                imageHeight = safeHeight
                imageWidth = imageHeight * sourceAspectRatio
                offsetX = (safeWidth - imageWidth) / 2
                offsetY = 0
            }
        }

        let mappedX = isMirrored ? 1 - x : x
        return CGPoint(
            x: offsetX + mappedX * imageWidth,
            y: offsetY + y * imageHeight
        )
    }

    public func displayPoint(for joint: RepPlaybackJoint, in size: CGSize) -> CGPoint {
        displayPoint(x: joint.x, y: joint.y, in: size)
    }
}

public struct PoseSkeletonSegment: Equatable, Sendable {
    public let startJointID: PoseJointID
    public let endJointID: PoseJointID
    public let start: CGPoint
    public let end: CGPoint
}

public enum PosePlaybackRenderer {
    public static let skeletonConnections: [(PoseJointID, PoseJointID)] = [
        (.nose, .leftShoulder),
        (.nose, .rightShoulder),
        (.leftShoulder, .rightShoulder),
        (.leftShoulder, .leftElbow),
        (.leftElbow, .leftWrist),
        (.rightShoulder, .rightElbow),
        (.rightElbow, .rightWrist),
        (.leftShoulder, .leftHip),
        (.rightShoulder, .rightHip),
        (.leftHip, .rightHip),
        (.leftHip, .leftKnee),
        (.leftKnee, .leftAnkle),
        (.rightHip, .rightKnee),
        (.rightKnee, .rightAnkle)
    ]

    public static func skeletonSegments(
        for sample: RepPlaybackPoseSample,
        in size: CGSize,
        mapper: PosePlaybackDisplayMapper = PosePlaybackDisplayMapper()
    ) -> [PoseSkeletonSegment] {
        skeletonConnections.compactMap { connection in
            guard let start = sample.joints[connection.0],
                  let end = sample.joints[connection.1],
                  start.confidence > 0,
                  end.confidence > 0 else {
                return nil
            }
            return PoseSkeletonSegment(
                startJointID: connection.0,
                endJointID: connection.1,
                start: mapper.displayPoint(for: start, in: size),
                end: mapper.displayPoint(for: end, in: size)
            )
        }
    }

    public static func jointPoints(
        for sample: RepPlaybackPoseSample,
        in size: CGSize,
        mapper: PosePlaybackDisplayMapper = PosePlaybackDisplayMapper()
    ) -> [PoseJointID: CGPoint] {
        Dictionary(uniqueKeysWithValues: sample.joints.map { jointID, joint in
            (jointID, mapper.displayPoint(for: joint, in: size))
        })
    }

    public static func trajectory(
        jointID: PoseJointID,
        samples: [RepPlaybackPoseSample],
        through currentTimeSeconds: Double?,
        in size: CGSize,
        mapper: PosePlaybackDisplayMapper = PosePlaybackDisplayMapper()
    ) -> [CGPoint] {
        let filtered = samples
            .filter { sample in
                guard let currentTimeSeconds else {
                    return true
                }
                return sample.repTimeSeconds <= currentTimeSeconds
            }
            .compactMap { sample -> CGPoint? in
                guard let joint = sample.joints[jointID], joint.confidence > 0 else {
                    return nil
                }
                return mapper.displayPoint(for: joint, in: size)
            }
        return filtered
    }
}
