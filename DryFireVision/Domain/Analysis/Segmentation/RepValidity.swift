import Foundation

public enum RepValidity: String, Codable, Equatable, Sendable {
    case valid
    case degraded
    case invalid
}

public enum SegmentationReason: String, Codable, Equatable, Sendable {
    case none
    case durationBelowMinimum
    case durationAboveMaximum
    case insufficientPoseData
    case invalidTimestampSequence
    case unusableCalibration
    case insufficientSignalCoverage
    case poseSignalUnavailable
    case falseStartRejected
    case incompleteOpenRepetition
    case repWindowExceeded
}

public enum SegmentationStatus: String, Codable, Equatable, Sendable {
    case complete
    case degraded
    case failed
}
