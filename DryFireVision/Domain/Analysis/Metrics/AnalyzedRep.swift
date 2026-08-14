import Foundation

public struct AnalyzedRep: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let sequenceIndex: Int
    public let segment: RepSegment
    public let metrics: MovementMetricSet
    public let metricDiagnostics: [MetricDiagnostic]
    public let sourceRecordingID: UUID

    public init(
        id: UUID,
        sequenceIndex: Int,
        segment: RepSegment,
        metrics: MovementMetricSet,
        metricDiagnostics: [MetricDiagnostic],
        sourceRecordingID: UUID
    ) {
        self.id = id
        self.sequenceIndex = sequenceIndex
        self.segment = segment
        self.metrics = metrics
        self.metricDiagnostics = metricDiagnostics
        self.sourceRecordingID = sourceRecordingID
    }
}
