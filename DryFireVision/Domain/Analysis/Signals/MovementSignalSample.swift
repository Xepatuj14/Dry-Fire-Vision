import Foundation

public enum MovementSignalAvailability: String, Codable, Equatable, Sendable {
    case available
    case firstUsableSample
    case invalidTimestampDelta
    case poseGapExceeded
    case insufficientJointCoverage
}

public struct MovementSignalSample: Codable, Equatable, Sendable {
    public let timestampSeconds: Double
    public let velocity: Double?
    public let baselineDistance: Double?
    public let contributingJointCount: Int
    public let availability: MovementSignalAvailability

    public init(
        timestampSeconds: Double,
        velocity: Double?,
        baselineDistance: Double?,
        contributingJointCount: Int,
        availability: MovementSignalAvailability
    ) {
        self.timestampSeconds = timestampSeconds
        self.velocity = velocity
        self.baselineDistance = baselineDistance
        self.contributingJointCount = contributingJointCount
        self.availability = availability
    }
}
