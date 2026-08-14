import Foundation

public struct PhaseSample: Codable, Equatable, Sendable {
    public let phase: Double
    public let sourceTimestampSeconds: Double
    public let x: Double
    public let y: Double
    public let confidence: Double
    public let interpolated: Bool

    public init(
        phase: Double,
        sourceTimestampSeconds: Double,
        x: Double,
        y: Double,
        confidence: Double,
        interpolated: Bool
    ) {
        self.phase = phase
        self.sourceTimestampSeconds = sourceTimestampSeconds
        self.x = x
        self.y = y
        self.confidence = confidence
        self.interpolated = interpolated
    }
}
