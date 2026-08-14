import Foundation

public enum MovementMetricKey: String, Codable, CaseIterable, Sendable {
    case totalRepDuration
    case headDisplacement
    case shoulderDisplacement
    case primaryWristPathLength
    case wristPathDirectness
}
