import Foundation

public enum PoseRecordingState: Equatable, Sendable {
    case idle
    case awaitingCalibration
    case countdown(remainingSeconds: Int)
    case waitingForStartPosition
    case recording(elapsedSeconds: Double)
    case finishingSession
    case completing
    case completed(PoseRecording)
    case cancelled
    case interrupted
    case failed(PoseRecordingError)
}
