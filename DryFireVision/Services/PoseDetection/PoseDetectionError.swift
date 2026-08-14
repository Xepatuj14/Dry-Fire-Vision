import Foundation

public enum PoseDetectionError: Error, Equatable, Sendable {
    case unsupportedPoseRequest
    case visionRequestFailed
    case invalidObservation
}
