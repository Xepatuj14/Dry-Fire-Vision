import Foundation

public struct CalibrationConfiguration: Codable, Equatable, Sendable {
    public let minimumRequiredJointConfidence: Double
    public let mediumConfidenceThreshold: Double
    public let highConfidenceThreshold: Double
    public let minimumAverageConfidence: Double
    public let minimumShoulderWidth: Double
    public let minimumBodyHeight: Double
    public let maximumBodyHeight: Double
    public let edgeMargin: Double
    public let stabilityWindowSeconds: Double
    public let stabilityMovementThreshold: Double
    public let minimumBaselineSamples: Int

    public init(
        minimumRequiredJointConfidence: Double = 0.35,
        mediumConfidenceThreshold: Double = 0.35,
        highConfidenceThreshold: Double = 0.7,
        minimumAverageConfidence: Double = 0.5,
        minimumShoulderWidth: Double = 0.04,
        minimumBodyHeight: Double = 0.42,
        maximumBodyHeight: Double = 0.92,
        edgeMargin: Double = 0.04,
        stabilityWindowSeconds: Double = 1.0,
        stabilityMovementThreshold: Double = 0.025,
        minimumBaselineSamples: Int = 4
    ) {
        self.minimumRequiredJointConfidence = minimumRequiredJointConfidence
        self.mediumConfidenceThreshold = mediumConfidenceThreshold
        self.highConfidenceThreshold = highConfidenceThreshold
        self.minimumAverageConfidence = minimumAverageConfidence
        self.minimumShoulderWidth = minimumShoulderWidth
        self.minimumBodyHeight = minimumBodyHeight
        self.maximumBodyHeight = maximumBodyHeight
        self.edgeMargin = edgeMargin
        self.stabilityWindowSeconds = stabilityWindowSeconds
        self.stabilityMovementThreshold = stabilityMovementThreshold
        self.minimumBaselineSamples = minimumBaselineSamples
    }
}
