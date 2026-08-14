import Foundation

public struct RepSegment: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let sequenceIndex: Int
    public let startTimestampSeconds: Double
    public let activeMovementEndTimestampSeconds: Double?
    public let completeTimestampSeconds: Double
    public let durationSeconds: Double
    public let validity: RepValidity
    public let confidenceStatus: ConfidenceStatus
    public let diagnosticReason: SegmentationReason

    public init(
        id: UUID,
        sequenceIndex: Int,
        startTimestampSeconds: Double,
        activeMovementEndTimestampSeconds: Double?,
        completeTimestampSeconds: Double,
        validity: RepValidity,
        confidenceStatus: ConfidenceStatus,
        diagnosticReason: SegmentationReason
    ) {
        self.id = id
        self.sequenceIndex = sequenceIndex
        self.startTimestampSeconds = startTimestampSeconds
        self.activeMovementEndTimestampSeconds = activeMovementEndTimestampSeconds
        self.completeTimestampSeconds = completeTimestampSeconds
        self.durationSeconds = completeTimestampSeconds - startTimestampSeconds
        self.validity = validity
        self.confidenceStatus = confidenceStatus
        self.diagnosticReason = diagnosticReason
    }
}
