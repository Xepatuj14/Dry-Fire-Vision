import Foundation

public struct PoseObservationMapper: Sendable {
    private let coordinateConverter: PoseCoordinateConverter

    public init(coordinateConverter: PoseCoordinateConverter = PoseCoordinateConverter()) {
        self.coordinateConverter = coordinateConverter
    }

    public func map(joints: [VisionJointObservation], timestampSeconds: Double) -> PoseFrame {
        var mappedJoints: [PoseJointID: JointSample] = [:]

        for joint in joints {
            guard let point = coordinateConverter.domainPointFromVisionNormalizedPoint(x: joint.x, y: joint.y) else {
                continue
            }

            mappedJoints[joint.jointID] = JointSample(
                jointID: joint.jointID,
                x: point.x,
                y: point.y,
                confidence: joint.confidence
            )
        }

        return PoseFrame(timestampSeconds: timestampSeconds, joints: mappedJoints)
    }
}
