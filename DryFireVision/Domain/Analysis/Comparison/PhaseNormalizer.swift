import Foundation

public struct PhaseNormalizer: Sendable {
    public let configuration: AnalysisConfiguration
    public let sampleExtractor: RepPoseSampleExtractor

    public init(configuration: AnalysisConfiguration) {
        self.configuration = configuration
        self.sampleExtractor = RepPoseSampleExtractor()
    }

    public func comparisonJoints() -> [PoseJointID]? {
        guard let primaryWrist = configuration.primaryWristJointID else {
            return nil
        }
        return [.nose, .leftShoulder, .rightShoulder, primaryWrist]
    }

    public func phaseGrid() -> [Double] {
        let count = max(2, configuration.comparisonPhaseSampleCount)
        return (0..<count).map { index in
            Double(index) / Double(count - 1)
        }
    }

    public func align(analyzedRep: AnalyzedRep, recording: PoseRecording) -> PhaseAlignedRep? {
        guard recording.calibrationResult.normalizationScale.isFinite,
              recording.calibrationResult.normalizationScale > 0,
              analyzedRep.segment.durationSeconds > 0,
              let joints = comparisonJoints() else {
            return nil
        }

        let samples = sampleExtractor.samples(for: analyzedRep.segment, in: recording)
        let grid = phaseGrid()
        let scale = recording.calibrationResult.normalizationScale
        let trajectories = Dictionary(uniqueKeysWithValues: joints.map { jointID in
            (jointID, resample(jointID: jointID, samples: samples, segment: analyzedRep.segment, scale: scale, grid: grid))
        })

        return PhaseAlignedRep(
            repID: analyzedRep.id,
            sequenceIndex: analyzedRep.sequenceIndex,
            sourceRecordingID: recording.id,
            startTimestampSeconds: analyzedRep.segment.startTimestampSeconds,
            completeTimestampSeconds: analyzedRep.segment.completeTimestampSeconds,
            phaseGrid: grid,
            trajectories: trajectories,
            analysisVersion: analyzedRep.metrics.analysisVersion,
            configurationVersion: configuration.version
        )
    }

    public func align(analyzedRep: AnalyzedRep, payload: PoseAssetPayload) -> PhaseAlignedRep? {
        guard payload.normalizationScale.isFinite,
              payload.normalizationScale > 0,
              analyzedRep.segment.durationSeconds > 0,
              payload.encodingVersion == VersionCatalog.current.poseEncodingVersion,
              payload.coordinateConventionVersion == VersionCatalog.current.coordinateConventionVersion,
              payload.jointSetVersion == VersionCatalog.current.jointSetVersion,
              let joints = comparisonJoints() else {
            return nil
        }

        let samples = payload.frames.filter {
            $0.timestampSeconds >= analyzedRep.segment.startTimestampSeconds &&
                $0.timestampSeconds <= analyzedRep.segment.completeTimestampSeconds
        }
        let grid = phaseGrid()
        let trajectories = Dictionary(uniqueKeysWithValues: joints.map { jointID in
            (jointID, resample(jointID: jointID, samples: samples, segment: analyzedRep.segment, scale: payload.normalizationScale, grid: grid))
        })

        return PhaseAlignedRep(
            repID: analyzedRep.id,
            sequenceIndex: analyzedRep.sequenceIndex,
            sourceRecordingID: analyzedRep.sourceRecordingID,
            startTimestampSeconds: analyzedRep.segment.startTimestampSeconds,
            completeTimestampSeconds: analyzedRep.segment.completeTimestampSeconds,
            phaseGrid: grid,
            trajectories: trajectories,
            analysisVersion: analyzedRep.metrics.analysisVersion,
            configurationVersion: configuration.version
        )
    }

    private func resample(
        jointID: PoseJointID,
        samples: [PoseFrame],
        segment: RepSegment,
        scale: Double,
        grid: [Double]
    ) -> [PhaseSample?] {
        let duration = segment.completeTimestampSeconds - segment.startTimestampSeconds
        let source = samples.compactMap { frame -> PhaseSample? in
            guard let joint = frame.sample(for: jointID),
                  joint.confidence >= configuration.mediumConfidenceThreshold,
                  joint.x.isFinite,
                  joint.y.isFinite,
                  joint.confidence.isFinite else {
                return nil
            }
            let phase = (frame.timestampSeconds - segment.startTimestampSeconds) / duration
            guard phase >= 0, phase <= 1, phase.isFinite else {
                return nil
            }
            return PhaseSample(
                phase: phase,
                sourceTimestampSeconds: frame.timestampSeconds,
                x: joint.x / scale,
                y: joint.y / scale,
                confidence: joint.confidence,
                interpolated: false
            )
        }.sorted { $0.phase < $1.phase }

        guard !source.isEmpty else {
            return Array(repeating: nil, count: grid.count)
        }

        return grid.map { phase in
            sample(at: phase, source: source)
        }
    }

    private func resample(
        jointID: PoseJointID,
        samples: [PoseAssetFrame],
        segment: RepSegment,
        scale: Double,
        grid: [Double]
    ) -> [PhaseSample?] {
        let duration = segment.completeTimestampSeconds - segment.startTimestampSeconds
        let source = samples.compactMap { frame -> PhaseSample? in
            guard let joint = frame.joints.first(where: { $0.jointID == jointID }),
                  joint.confidence >= configuration.mediumConfidenceThreshold,
                  joint.x.isFinite,
                  joint.y.isFinite,
                  joint.confidence.isFinite else {
                return nil
            }
            let phase = (frame.timestampSeconds - segment.startTimestampSeconds) / duration
            guard phase >= 0, phase <= 1, phase.isFinite else {
                return nil
            }
            return PhaseSample(
                phase: phase,
                sourceTimestampSeconds: frame.timestampSeconds,
                x: joint.x / scale,
                y: joint.y / scale,
                confidence: joint.confidence,
                interpolated: false
            )
        }.sorted { $0.phase < $1.phase }

        guard !source.isEmpty else {
            return Array(repeating: nil, count: grid.count)
        }

        return grid.map { phase in
            sample(at: phase, source: source)
        }
    }

    private func sample(at phase: Double, source: [PhaseSample]) -> PhaseSample? {
        if let exact = source.first(where: { abs($0.phase - phase) <= 0.000_000_001 }) {
            return exact
        }
        guard let before = source.last(where: { $0.phase < phase }),
              let after = source.first(where: { $0.phase > phase }) else {
            return nil
        }
        let timeGap = after.sourceTimestampSeconds - before.sourceTimestampSeconds
        guard timeGap > 0, timeGap <= configuration.maximumInterpolationGapSeconds else {
            return nil
        }
        let phaseGap = after.phase - before.phase
        guard phaseGap > 0 else {
            return nil
        }
        let fraction = (phase - before.phase) / phaseGap
        return PhaseSample(
            phase: phase,
            sourceTimestampSeconds: before.sourceTimestampSeconds + timeGap * fraction,
            x: before.x + (after.x - before.x) * fraction,
            y: before.y + (after.y - before.y) * fraction,
            confidence: min(before.confidence, after.confidence),
            interpolated: true
        )
    }
}
