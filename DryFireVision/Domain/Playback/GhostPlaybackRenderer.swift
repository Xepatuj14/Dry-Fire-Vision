import CoreGraphics
import Foundation

public struct GhostDisplayMapper: Sendable {
    public let bounds: CGRect
    public let paddingFraction: Double

    public init(alignedRepA: PhaseAlignedRep, alignedRepB: PhaseAlignedRep, paddingFraction: Double = 0.12) {
        self.bounds = Self.bounds(for: [alignedRepA, alignedRepB])
        self.paddingFraction = paddingFraction
    }

    public init(bounds: CGRect, paddingFraction: Double = 0.12) {
        self.bounds = bounds
        self.paddingFraction = paddingFraction
    }

    public func displayPoint(for joint: RepPlaybackJoint, in size: CGSize) -> CGPoint {
        let safeBounds = bounds.width > 0 && bounds.height > 0 ? bounds : CGRect(x: 0, y: 0, width: 1, height: 1)
        let boundsWidth = Double(safeBounds.width)
        let boundsHeight = Double(safeBounds.height)
        let boundsMinX = Double(safeBounds.minX)
        let boundsMinY = Double(safeBounds.minY)
        let paddedWidth = boundsWidth * (1 + paddingFraction * 2)
        let paddedHeight = boundsHeight * (1 + paddingFraction * 2)
        let paddedOriginX = boundsMinX - boundsWidth * paddingFraction
        let paddedOriginY = boundsMinY - boundsHeight * paddingFraction
        let scale = min(
            Double(size.width) / max(Double(paddedWidth), 0.000_001),
            Double(size.height) / max(Double(paddedHeight), 0.000_001)
        )
        let drawnWidth = paddedWidth * scale
        let drawnHeight = paddedHeight * scale
        let offsetX = (Double(size.width) - drawnWidth) / 2
        let offsetY = (Double(size.height) - drawnHeight) / 2

        return CGPoint(
            x: offsetX + (joint.x - paddedOriginX) * scale,
            y: offsetY + (joint.y - paddedOriginY) * scale
        )
    }

    private static func bounds(for reps: [PhaseAlignedRep]) -> CGRect {
        let points = reps.flatMap { rep in
            rep.trajectories.values.flatMap { samples in
                samples.compactMap { sample -> CGPoint? in
                    guard let sample else {
                        return nil
                    }
                    return CGPoint(x: sample.x, y: sample.y)
                }
            }
        }
        guard let first = points.first else {
            return CGRect(x: 0, y: 0, width: 1, height: 1)
        }
        let minX = points.map(\.x).min() ?? first.x
        let maxX = points.map(\.x).max() ?? first.x
        let minY = points.map(\.y).min() ?? first.y
        let maxY = points.map(\.y).max() ?? first.y
        return CGRect(
            x: minX,
            y: minY,
            width: max(maxX - minX, CGFloat(0.000_001)),
            height: max(maxY - minY, CGFloat(0.000_001))
        )
    }
}

public enum GhostPlaybackRenderer {
    public static func skeletonSegments(
        for pose: GhostPlaybackPose,
        in size: CGSize,
        mapper: GhostDisplayMapper
    ) -> [PoseSkeletonSegment] {
        PosePlaybackRenderer.skeletonConnections.compactMap { connection in
            guard let start = pose.joints[connection.0],
                  let end = pose.joints[connection.1],
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
        for pose: GhostPlaybackPose,
        in size: CGSize,
        mapper: GhostDisplayMapper
    ) -> [PoseJointID: CGPoint] {
        Dictionary(uniqueKeysWithValues: pose.joints.map { jointID, joint in
            (jointID, mapper.displayPoint(for: joint, in: size))
        })
    }

    public static func trajectory(
        joints: [RepPlaybackJoint],
        in size: CGSize,
        mapper: GhostDisplayMapper
    ) -> [CGPoint] {
        joints.filter { $0.confidence > 0 }.map { mapper.displayPoint(for: $0, in: size) }
    }
}
