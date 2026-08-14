import Foundation

public struct JointTrajectory: Codable, Equatable, Sendable {
    public let jointID: PoseJointID
    public let positions: [NormalizedJointPosition]
    public let expectedSampleCount: Int
    public let interpolationCount: Int
    public let hasExcessiveGap: Bool

    public init(
        jointID: PoseJointID,
        positions: [NormalizedJointPosition],
        expectedSampleCount: Int,
        interpolationCount: Int,
        hasExcessiveGap: Bool
    ) {
        self.jointID = jointID
        self.positions = positions
        self.expectedSampleCount = expectedSampleCount
        self.interpolationCount = interpolationCount
        self.hasExcessiveGap = hasExcessiveGap
    }

    public var coverage: Double {
        guard expectedSampleCount > 0 else {
            return 0
        }
        return Double(positions.count) / Double(expectedSampleCount)
    }

    public var averageConfidence: Double? {
        guard !positions.isEmpty else {
            return nil
        }
        return positions.map(\.confidence).reduce(0, +) / Double(positions.count)
    }
}
