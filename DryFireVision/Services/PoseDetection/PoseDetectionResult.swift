import Foundation

public struct PoseDetectionResult: Equatable, Sendable {
    public let poseFrames: [PoseFrame]

    public init(poseFrames: [PoseFrame]) {
        self.poseFrames = poseFrames
    }
}
