import Foundation

public struct SegmentationResult: Codable, Equatable, Sendable {
    public let segments: [RepSegment]
    public let rejectedSegments: [RepSegment]
    public let diagnostics: [SegmentationDiagnostic]
    public let status: SegmentationStatus
    public let inputSampleCount: Int
    public let analysisVersion: String
    public let configurationVersion: String
    public let failureReasons: [SegmentationReason]

    public init(
        segments: [RepSegment],
        rejectedSegments: [RepSegment],
        diagnostics: [SegmentationDiagnostic],
        status: SegmentationStatus,
        inputSampleCount: Int,
        analysisVersion: String,
        configurationVersion: String,
        failureReasons: [SegmentationReason]
    ) {
        self.segments = segments
        self.rejectedSegments = rejectedSegments
        self.diagnostics = diagnostics
        self.status = status
        self.inputSampleCount = inputSampleCount
        self.analysisVersion = analysisVersion
        self.configurationVersion = configurationVersion
        self.failureReasons = failureReasons
    }
}
