import Foundation

public struct SessionComparisonResult: Codable, Equatable, Sendable {
    public let recordingID: UUID
    public let analyzedReps: [AnalyzedRep]
    public let eligibleRepIDs: [UUID]
    public let representativeRepID: UUID?
    public let fastestRepID: UUID?
    public let consistency: SessionConsistencyResult
    public let outlierRepIDs: [UUID]
    public let similarityToRepresentative: [UUID: RepComparisonResult]
    public let pairwiseComparisons: [RepComparisonResult]
    public let confidence: ConfidenceStatus
    public let diagnostics: SessionComparisonDiagnostic
    public let analysisVersion: String
    public let configurationVersion: String

    public init(
        recordingID: UUID,
        analyzedReps: [AnalyzedRep],
        eligibleRepIDs: [UUID],
        representativeRepID: UUID?,
        fastestRepID: UUID?,
        consistency: SessionConsistencyResult,
        outlierRepIDs: [UUID],
        similarityToRepresentative: [UUID: RepComparisonResult],
        pairwiseComparisons: [RepComparisonResult],
        confidence: ConfidenceStatus,
        diagnostics: SessionComparisonDiagnostic,
        analysisVersion: String = VersionCatalog.current.analysisVersion,
        configurationVersion: String
    ) {
        self.recordingID = recordingID
        self.analyzedReps = analyzedReps
        self.eligibleRepIDs = eligibleRepIDs
        self.representativeRepID = representativeRepID
        self.fastestRepID = fastestRepID
        self.consistency = consistency
        self.outlierRepIDs = outlierRepIDs
        self.similarityToRepresentative = similarityToRepresentative
        self.pairwiseComparisons = pairwiseComparisons
        self.confidence = confidence
        self.diagnostics = diagnostics
        self.analysisVersion = analysisVersion
        self.configurationVersion = configurationVersion
    }
}
