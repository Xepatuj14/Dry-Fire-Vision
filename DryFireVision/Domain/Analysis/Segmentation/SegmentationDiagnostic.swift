import Foundation

public enum SegmentationDiagnosticEvent: String, Codable, Equatable, Sendable {
    case stateTransition
    case startCandidate
    case startConfirmed
    case falseStartRejected
    case repCompleted
    case repDurationRejected
    case repWindowExceeded
    case poseSignalUnavailable
    case resetConfirmed
}

public struct SegmentationDiagnostic: Codable, Equatable, Sendable {
    public let event: SegmentationDiagnosticEvent
    public let timestampSeconds: Double
    public let fromState: MovementAnalysisState?
    public let toState: MovementAnalysisState?
    public let movementSignal: Double?
    public let baselineDistance: Double?
    public let threshold: Double?
    public let reason: SegmentationReason?

    public init(
        event: SegmentationDiagnosticEvent,
        timestampSeconds: Double,
        fromState: MovementAnalysisState? = nil,
        toState: MovementAnalysisState? = nil,
        movementSignal: Double? = nil,
        baselineDistance: Double? = nil,
        threshold: Double? = nil,
        reason: SegmentationReason? = nil
    ) {
        self.event = event
        self.timestampSeconds = timestampSeconds
        self.fromState = fromState
        self.toState = toState
        self.movementSignal = movementSignal
        self.baselineDistance = baselineDistance
        self.threshold = threshold
        self.reason = reason
    }
}
