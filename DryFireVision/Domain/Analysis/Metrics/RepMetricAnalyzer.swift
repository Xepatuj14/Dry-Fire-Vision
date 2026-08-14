import Foundation

public struct RepMetricAnalyzer: Sendable {
    public let configuration: AnalysisConfiguration
    public let sampleExtractor: RepPoseSampleExtractor
    public let timingAnalyzer: TimingAnalyzer
    public let displacementAnalyzer: DisplacementAnalyzer
    public let trajectoryAnalyzer: TrajectoryAnalyzer

    public init(configuration: AnalysisConfiguration = .provisionalSegmentationV1) {
        self.configuration = configuration
        self.sampleExtractor = RepPoseSampleExtractor()
        self.timingAnalyzer = TimingAnalyzer(configuration: configuration)
        self.displacementAnalyzer = DisplacementAnalyzer(configuration: configuration)
        self.trajectoryAnalyzer = TrajectoryAnalyzer(configuration: configuration)
    }

    public func analyze(
        recording: PoseRecording,
        segmentationResult: SegmentationResult
    ) -> [AnalyzedRep] {
        segmentationResult.segments.map { segment in
            analyze(segment: segment, recording: recording)
        }
    }

    public func analyze(segment: RepSegment, recording: PoseRecording) -> AnalyzedRep {
        let samples = sampleExtractor.samples(for: segment, in: recording)

        let duration = timingAnalyzer.totalRepDuration(for: segment)
        let (head, headDiagnostic) = displacementAnalyzer.headDisplacement(
            samples: samples,
            calibration: recording.calibrationResult
        )
        let (shoulder, shoulderDiagnostic) = displacementAnalyzer.shoulderDisplacement(
            samples: samples,
            calibration: recording.calibrationResult
        )
        let wrist = trajectoryAnalyzer.primaryWristMetrics(
            samples: samples,
            calibration: recording.calibrationResult
        )

        let metrics = MovementMetricSet(
            duration: duration,
            headDisplacement: head,
            shoulderDisplacement: shoulder,
            primaryWristPathLength: wrist.pathLength,
            wristPathDirectness: wrist.directness,
            configurationVersion: configuration.version
        )

        return AnalyzedRep(
            id: segment.id,
            sequenceIndex: segment.sequenceIndex,
            segment: segment,
            metrics: metrics,
            metricDiagnostics: [headDiagnostic, shoulderDiagnostic] + wrist.diagnostics,
            sourceRecordingID: recording.id
        )
    }
}
