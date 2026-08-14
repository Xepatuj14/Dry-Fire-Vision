import Foundation

public protocol PoseDetecting: Sendable {
    func detectPoses(in frame: CameraFrame) async throws -> PoseDetectionResult
}
