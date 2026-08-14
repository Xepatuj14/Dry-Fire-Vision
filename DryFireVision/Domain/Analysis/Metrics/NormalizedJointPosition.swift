import Foundation

public struct NormalizedJointPosition: Codable, Equatable, Sendable {
    public let timestampSeconds: Double
    public let x: Double
    public let y: Double
    public let confidence: Double
    public let interpolated: Bool

    public init(timestampSeconds: Double, x: Double, y: Double, confidence: Double, interpolated: Bool = false) {
        self.timestampSeconds = timestampSeconds
        self.x = x
        self.y = y
        self.confidence = confidence
        self.interpolated = interpolated
    }
}
