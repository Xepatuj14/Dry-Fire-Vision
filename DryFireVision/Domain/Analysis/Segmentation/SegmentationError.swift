import Foundation

public enum SegmentationError: Error, Codable, Equatable, Sendable {
    case insufficientPoseData
    case invalidTimestampSequence
    case invalidConfiguration
    case unusableCalibration
    case insufficientSignalCoverage
}
