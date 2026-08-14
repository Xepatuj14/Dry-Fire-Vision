import Foundation

public struct VisionJointObservation: Equatable, Sendable {
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
}
