import Foundation

public struct ExponentialPoseSmoother: Sendable {
    public let alpha: Double

    public init(alpha: Double) {
        self.alpha = min(1, max(0, alpha))
    }

    public func smooth(current: PoseSignalPoint, previous: PoseSignalPoint?) -> PoseSignalPoint {
        guard let previous else {
            return current
        }

        return PoseSignalPoint(
            jointID: current.jointID,
            x: previous.x + alpha * (current.x - previous.x),
            y: previous.y + alpha * (current.y - previous.y),
            confidence: current.confidence
        )
    }
}
