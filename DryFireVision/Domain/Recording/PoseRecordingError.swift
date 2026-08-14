import Foundation

public enum PoseRecordingError: Error, Codable, Equatable, Sendable {
    case missingCalibration
    case notRecording
    case alreadyRecording
    case noAcceptedFrames
    case nonMonotonicTimestamp(previousSeconds: Double, nextSeconds: Double)
    case unsupportedFixtureEncoding(version: String)
}
