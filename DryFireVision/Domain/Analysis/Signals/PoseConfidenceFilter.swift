import Foundation

public struct PoseConfidenceFilter: Sendable {
    public let configuration: AnalysisConfiguration

    public init(configuration: AnalysisConfiguration) {
        self.configuration = configuration
    }

    public func filteredPoints(from frame: PoseFrame, jointIDs: [PoseJointID]) -> [PoseJointID: PoseSignalPoint] {
        var points: [PoseJointID: PoseSignalPoint] = [:]
        for jointID in jointIDs {
            guard let sample = frame.sample(for: jointID),
                  sample.confidence >= configuration.mediumConfidenceThreshold else {
                continue
            }

            points[jointID] = PoseSignalPoint(
                jointID: jointID,
                x: sample.x,
                y: sample.y,
                confidence: sample.confidence
            )
        }
        return points
    }
}
