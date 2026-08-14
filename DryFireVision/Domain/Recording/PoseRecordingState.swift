import Foundation

public enum PoseRecordingState: Equatable, Sendable {
    case idle
    case awaitingCalibration
    case countdown(remainingSeconds: Int)
    case recording(elapsedSeconds: Double)
    case completing
    case completed(PoseRecording)
    case cancelled
    case interrupted
    case failed(PoseRecordingError)
}
