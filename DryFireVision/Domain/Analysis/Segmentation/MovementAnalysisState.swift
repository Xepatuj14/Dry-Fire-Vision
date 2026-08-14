import Foundation

public enum MovementAnalysisState: String, Codable, Equatable, Sendable {
    case waitingForStable = "WAITING_FOR_STABLE"
    case ready = "READY"
    case moving = "MOVING"
    case settling = "SETTLING"
    case complete = "COMPLETE"
    case resetting = "RESETTING"
}
