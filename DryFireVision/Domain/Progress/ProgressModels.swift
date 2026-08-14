import Foundation

public enum HistoricalMetricKey: String, Codable, CaseIterable, Equatable, Sendable {
    case averageMovementDuration
    case movementConsistency
    case fastestRepDuration

    public var title: String {
        switch self {
        case .averageMovementDuration:
            return "Movement Duration"
        case .movementConsistency:
            return "Movement Consistency"
        case .fastestRepDuration:
            return "Fastest Rep Duration"
        }
    }
}

public struct HistoricalMetricPoint: Equatable, Identifiable, Sendable {
    public let id: UUID
    public let sourceSessionID: UUID
    public let sourceRepID: UUID?
    public let date: Date
    public let metricKey: HistoricalMetricKey
    public let value: Double
    public let analysisVersion: String
    public let confidence: ConfidenceStatus

    public init(
        id: UUID,
        sourceSessionID: UUID,
        sourceRepID: UUID? = nil,
        date: Date,
        metricKey: HistoricalMetricKey,
        value: Double,
        analysisVersion: String,
        confidence: ConfidenceStatus
    ) {
        self.id = id
        self.sourceSessionID = sourceSessionID
        self.sourceRepID = sourceRepID
        self.date = date
        self.metricKey = metricKey
        self.value = value
        self.analysisVersion = analysisVersion
        self.confidence = confidence
    }
}

public struct PersonalRecordSnapshot: Equatable, Identifiable, Sendable {
    public let id: UUID
    public let metricKey: HistoricalMetricKey
    public let mode: SessionMode
    public let value: Double
    public let achievedDate: Date
    public let sourceSessionID: UUID
    public let sourceRepID: UUID?
    public let analysisVersion: String
    public let confidence: ConfidenceStatus
    public let previousValue: Double?

    public init(
        id: UUID,
        metricKey: HistoricalMetricKey,
        mode: SessionMode,
        value: Double,
        achievedDate: Date,
        sourceSessionID: UUID,
        sourceRepID: UUID?,
        analysisVersion: String,
        confidence: ConfidenceStatus,
        previousValue: Double?
    ) {
        self.id = id
        self.metricKey = metricKey
        self.mode = mode
        self.value = value
        self.achievedDate = achievedDate
        self.sourceSessionID = sourceSessionID
        self.sourceRepID = sourceRepID
        self.analysisVersion = analysisVersion
        self.confidence = confidence
        self.previousValue = previousValue
    }
}

public enum PersonalBaselineAvailability: Equatable, Sendable {
    case available
    case insufficientHistory
}

public struct PersonalBaselineSnapshot: Equatable, Identifiable, Sendable {
    public let id: UUID
    public let metricKey: HistoricalMetricKey
    public let mode: SessionMode
    public let analysisVersion: String
    public let sampleCount: Int
    public let medianValue: Double?
    public let robustDispersion: Double?
    public let lastRebuiltAt: Date
    public let availability: PersonalBaselineAvailability

    public init(
        id: UUID,
        metricKey: HistoricalMetricKey,
        mode: SessionMode,
        analysisVersion: String,
        sampleCount: Int,
        medianValue: Double?,
        robustDispersion: Double?,
        lastRebuiltAt: Date,
        availability: PersonalBaselineAvailability
    ) {
        self.id = id
        self.metricKey = metricKey
        self.mode = mode
        self.analysisVersion = analysisVersion
        self.sampleCount = sampleCount
        self.medianValue = medianValue
        self.robustDispersion = robustDispersion
        self.lastRebuiltAt = lastRebuiltAt
        self.availability = availability
    }
}

public struct ProgressOverviewSnapshot: Equatable, Sendable {
    public let durationTrend: [HistoricalMetricPoint]
    public let consistencyTrend: [HistoricalMetricPoint]
    public let personalRecords: [PersonalRecordSnapshot]
    public let baselines: [PersonalBaselineSnapshot]
    public let compatibleAnalysisVersion: String
    public let generatedAt: Date

    public init(
        durationTrend: [HistoricalMetricPoint],
        consistencyTrend: [HistoricalMetricPoint],
        personalRecords: [PersonalRecordSnapshot],
        baselines: [PersonalBaselineSnapshot],
        compatibleAnalysisVersion: String,
        generatedAt: Date
    ) {
        self.durationTrend = durationTrend
        self.consistencyTrend = consistencyTrend
        self.personalRecords = personalRecords
        self.baselines = baselines
        self.compatibleAnalysisVersion = compatibleAnalysisVersion
        self.generatedAt = generatedAt
    }
}
