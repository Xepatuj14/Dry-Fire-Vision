import Foundation

public struct SessionConsistencyResult: Codable, Equatable, Sendable {
    public let availability: ComparisonAvailability
    public let internalValue: Double?
    public let confidence: ConfidenceStatus
    public let reason: ComparisonUnavailableReason

    public init(
        availability: ComparisonAvailability,
        internalValue: Double?,
        confidence: ConfidenceStatus,
        reason: ComparisonUnavailableReason
    ) {
        self.availability = availability
        self.internalValue = internalValue?.isFinite == true ? internalValue : nil
        self.confidence = confidence
        self.reason = reason
    }
}
