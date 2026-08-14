import Foundation

public struct PoseCoordinateConverter: Sendable {
    public init() {}

    /// Dry Fire Vision internal 2D coordinates are normalized image-space coordinates with origin at top-left,
    /// x increasing rightward, and y increasing downward.
    public func domainPointFromVisionNormalizedPoint(x: Double, y: Double) -> (x: Double, y: Double)? {
        guard x.isFinite, y.isFinite else {
            return nil
        }

        return (x: x, y: 1.0 - y)
    }

    public func displayPointFromDomainPoint(
        x: Double,
        y: Double,
        displayWidth: Double,
        displayHeight: Double
    ) -> (x: Double, y: Double) {
        (x: x * displayWidth, y: y * displayHeight)
    }
}
