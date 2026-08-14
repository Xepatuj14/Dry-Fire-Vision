import Foundation

public struct RepSegmenter: Sendable {
    public let configuration: AnalysisConfiguration
    public let signalBuilder: MovementSignalBuilder
    public let stateMachine: MovementStateMachine

    public init(configuration: AnalysisConfiguration = .provisionalSegmentationV1) {
        self.configuration = configuration
        self.signalBuilder = MovementSignalBuilder(configuration: configuration)
        self.stateMachine = MovementStateMachine(configuration: configuration)
    }

    public func segment(_ recording: PoseRecording) throws -> SegmentationResult {
        try validate(recording)
        let signals = signalBuilder.build(from: recording)
        guard signals.contains(where: { $0.availability == .available }) else {
            return SegmentationResult(
                segments: [],
                rejectedSegments: [],
                diagnostics: [
                    SegmentationDiagnostic(
                        event: .poseSignalUnavailable,
                        timestampSeconds: recording.poseFrames.first?.timestampSeconds ?? 0,
                        reason: .insufficientSignalCoverage
                    )
                ],
                status: .degraded,
                inputSampleCount: recording.poseFrames.count,
                analysisVersion: VersionCatalog.current.analysisVersion,
                configurationVersion: configuration.version,
                failureReasons: [.insufficientSignalCoverage]
            )
        }
        return stateMachine.process(samples: signals)
    }

    private func validate(_ recording: PoseRecording) throws {
        guard configuration.smoothingAlpha >= 0,
              configuration.smoothingAlpha <= 1,
              configuration.plausibleRepDurationMinimumSeconds > 0,
              configuration.plausibleRepDurationMaximumSeconds > configuration.plausibleRepDurationMinimumSeconds,
              configuration.minimumSignalJointCount > 0 else {
            throw SegmentationError.invalidConfiguration
        }

        guard recording.calibrationResult.normalizationScale > 0 else {
            throw SegmentationError.unusableCalibration
        }

        guard recording.poseFrames.count >= 2 else {
            throw SegmentationError.insufficientPoseData
        }

        for pair in zip(recording.poseFrames, recording.poseFrames.dropFirst()) {
            guard pair.1.timestampSeconds > pair.0.timestampSeconds else {
                throw SegmentationError.invalidTimestampSequence
            }
        }
    }
}
