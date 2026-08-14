import Foundation

public struct LiveFireSynchronizedInput: Equatable, Sendable {
    public let sessionID: UUID
    public let createdAt: Date
    public let audioSamples: [AudioSignalSample]
    public let poseFrames: [PoseFrame]
    public let normalizationScale: Double
    public let configuration: AnalysisConfiguration

    public init(
        sessionID: UUID = UUID(),
        createdAt: Date = Date(timeIntervalSince1970: 0),
        audioSamples: [AudioSignalSample],
        poseFrames: [PoseFrame],
        normalizationScale: Double,
        configuration: AnalysisConfiguration = .provisionalSegmentationV1
    ) {
        self.sessionID = sessionID
        self.createdAt = createdAt
        self.audioSamples = audioSamples
        self.poseFrames = poseFrames
        self.normalizationScale = normalizationScale
        self.configuration = configuration
    }
}

public struct LiveFireSessionAnalyzer: Sendable {
    private let detector: any AudioEventDetecting

    public init(detector: any AudioEventDetecting = AudioEventDetector()) {
        self.detector = detector
    }

    public func analyze(_ input: LiveFireSynchronizedInput) -> LiveFireSessionAnalysis {
        let candidates = detector.detectCandidates(in: input.audioSamples, configuration: input.configuration)
        var previousAcceptedTimestamp: Double?
        var events: [LiveEventAnalysis] = []
        var poseAssetsByEventID: [UUID: PoseAssetPayload] = [:]

        for (index, candidate) in candidates.enumerated() {
            let interEvent = candidate.status == .accepted ? previousAcceptedTimestamp.map { candidate.timestampSeconds - $0 } : nil
            if candidate.status == .accepted {
                previousAcceptedTimestamp = candidate.timestampSeconds
            }
            let event = analyzeCandidate(
                candidate,
                sessionID: input.sessionID,
                sequenceIndex: index,
                interEventDurationSeconds: interEvent,
                poseFrames: input.poseFrames,
                normalizationScale: input.normalizationScale,
                configuration: input.configuration
            )
            events.append(event)
            if event.status == .accepted {
                let window = recoveryWindowFrames(
                    around: candidate.timestampSeconds,
                    poseFrames: input.poseFrames,
                    configuration: input.configuration
                )
                if !window.isEmpty {
                    poseAssetsByEventID[event.id] = PoseAssetPayload(
                        encodingVersion: VersionCatalog.current.poseEncodingVersion,
                        coordinateConventionVersion: VersionCatalog.current.coordinateConventionVersion,
                        jointSetVersion: VersionCatalog.current.jointSetVersion,
                        normalizationScale: input.normalizationScale,
                        normalizationScaleSource: .shoulderWidth,
                        frames: window.map(PoseAssetFrame.init)
                    )
                }
            }
        }

        events = markOutliersAndSimilarity(events, configuration: input.configuration)
        let consistency = recoveryConsistency(for: events)
        return LiveFireSessionAnalysis(
            sessionID: input.sessionID,
            createdAt: input.createdAt,
            events: events,
            recoveryPoseAssetsByEventID: poseAssetsByEventID,
            recoveryConsistency: consistency,
            overallConfidence: events.contains { $0.recoveryConfidence == .high } ? .high : (events.isEmpty ? .low : .medium)
        )
    }

    private func analyzeCandidate(
        _ candidate: CandidateAudioEvent,
        sessionID: UUID,
        sequenceIndex: Int,
        interEventDurationSeconds: Double?,
        poseFrames: [PoseFrame],
        normalizationScale: Double,
        configuration: AnalysisConfiguration
    ) -> LiveEventAnalysis {
        guard candidate.status == .accepted else {
            return unavailableEvent(
                candidate,
                sessionID: sessionID,
                sequenceIndex: sequenceIndex,
                interEventDurationSeconds: interEventDurationSeconds,
                reason: candidate.reason
            )
        }
        guard normalizationScale.isFinite, normalizationScale > 0 else {
            return unavailableEvent(
                candidate,
                sessionID: sessionID,
                sequenceIndex: sequenceIndex,
                interEventDurationSeconds: interEventDurationSeconds,
                reason: .invalidNormalization
            )
        }

        let preStart = candidate.timestampSeconds - configuration.liveFirePreEventWindowSeconds
        let postEnd = candidate.timestampSeconds + configuration.liveFirePostEventWindowSeconds
        let preFrames = poseFrames.filter { $0.timestampSeconds >= preStart && $0.timestampSeconds < candidate.timestampSeconds }
        let postFrames = poseFrames.filter { $0.timestampSeconds >= candidate.timestampSeconds && $0.timestampSeconds <= postEnd }
        guard hasUsableCoverage(preFrames + postFrames, eventTimestamp: candidate.timestampSeconds, configuration: configuration),
              let baseline = baselinePositions(from: preFrames, minimumConfidence: configuration.mediumConfidenceThreshold) else {
            return unavailableEvent(
                candidate,
                sessionID: sessionID,
                sequenceIndex: sequenceIndex,
                interEventDurationSeconds: interEventDurationSeconds,
                reason: .insufficientPoseCoverage
            )
        }

        let trajectory = postFrames.compactMap { frame -> RecoveryTrajectorySample? in
            guard let displacement = upperBodyDisplacement(frame: frame, baseline: baseline) else {
                return nil
            }
            return RecoveryTrajectorySample(
                timeSinceEventSeconds: frame.timestampSeconds - candidate.timestampSeconds,
                displacement: displacement
            )
        }
        guard let peak = trajectory.max(by: { $0.displacement < $1.displacement }) else {
            return unavailableEvent(
                candidate,
                sessionID: sessionID,
                sequenceIndex: sequenceIndex,
                interEventDurationSeconds: interEventDurationSeconds,
                reason: .recoveryUnavailable
            )
        }
        let recoveredTimestamp = recoveredTimestamp(
            in: trajectory,
            afterPeakTime: peak.timeSinceEventSeconds,
            tolerance: configuration.liveFireRecoveryTolerance,
            dwellSeconds: configuration.liveFireRecoveryDwellSeconds
        )
        let recoveryConfidence: ConfidenceStatus = recoveredTimestamp == nil ? .medium : minConfidence(candidate.confidence, .high)
        let recoveryDuration = recoveredTimestamp.map {
            MovementMetricResult.available(
                key: .totalRepDuration,
                value: $0,
                confidence: recoveryConfidence,
                configurationVersion: configuration.version
            )
        } ?? MovementMetricResult.unavailable(key: .totalRepDuration, reason: .insufficientJointCoverage, configurationVersion: configuration.version)

        let head = postFrames.compactMap { headDisplacement(frame: $0, baseline: baseline) }.max() ?? 0
        return LiveEventAnalysis(
            id: candidate.id,
            sessionID: sessionID,
            sequenceIndex: sequenceIndex,
            timestampSeconds: candidate.timestampSeconds,
            eventConfidence: candidate.confidence,
            status: .accepted,
            interEventDurationSeconds: interEventDurationSeconds,
            headDisplacement: MovementMetricResult.available(key: .headDisplacement, value: head, confidence: recoveryConfidence, configurationVersion: configuration.version),
            upperBodyDisplacement: MovementMetricResult.available(key: .shoulderDisplacement, value: peak.displacement, confidence: recoveryConfidence, configurationVersion: configuration.version),
            peakVisibleDisplacement: MovementMetricResult.available(key: .shoulderDisplacement, value: peak.displacement, confidence: recoveryConfidence, configurationVersion: configuration.version),
            recoveryDuration: recoveryDuration,
            recoveryConfidence: recoveryConfidence,
            reason: recoveredTimestamp == nil ? .recoveryUnavailable : .none,
            trajectory: trajectory
        )
    }

    private func unavailableEvent(
        _ candidate: CandidateAudioEvent,
        sessionID: UUID,
        sequenceIndex: Int,
        interEventDurationSeconds: Double?,
        reason: LiveEventReason
    ) -> LiveEventAnalysis {
        let headMetric = MovementMetricResult.unavailable(
            key: .headDisplacement,
            reason: .insufficientJointCoverage,
            configurationVersion: VersionCatalog.current.analysisConfigurationVersion
        )
        let shoulderMetric = MovementMetricResult.unavailable(
            key: .shoulderDisplacement,
            reason: .insufficientJointCoverage,
            configurationVersion: VersionCatalog.current.analysisConfigurationVersion
        )
        return LiveEventAnalysis(
            id: candidate.id,
            sessionID: sessionID,
            sequenceIndex: sequenceIndex,
            timestampSeconds: candidate.timestampSeconds,
            eventConfidence: candidate.confidence,
            status: candidate.status,
            interEventDurationSeconds: interEventDurationSeconds,
            headDisplacement: headMetric,
            upperBodyDisplacement: shoulderMetric,
            peakVisibleDisplacement: shoulderMetric,
            recoveryDuration: MovementMetricResult.unavailable(key: .totalRepDuration, reason: .insufficientJointCoverage, configurationVersion: VersionCatalog.current.analysisConfigurationVersion),
            recoveryConfidence: .low,
            reason: reason
        )
    }

    private func baselinePositions(from frames: [PoseFrame], minimumConfidence: Double) -> [PoseJointID: (x: Double, y: Double)]? {
        var result: [PoseJointID: (x: Double, y: Double)] = [:]
        for joint in recoveryJoints {
            let samples = frames.compactMap { frame -> JointSample? in
                guard let sample = frame.joints[joint], sample.confidence >= minimumConfidence else {
                    return nil
                }
                return sample
            }
            guard !samples.isEmpty else {
                return nil
            }
            result[joint] = (median(samples.map(\.x)), median(samples.map(\.y)))
        }
        return result
    }

    private func upperBodyDisplacement(frame: PoseFrame, baseline: [PoseJointID: (x: Double, y: Double)]) -> Double? {
        let values = recoveryJoints.compactMap { joint -> Double? in
            guard let sample = frame.joints[joint], let base = baseline[joint] else {
                return nil
            }
            let dx = sample.x - base.x
            let dy = sample.y - base.y
            return (dx * dx + dy * dy).squareRoot()
        }
        guard values.count >= 2 else {
            return nil
        }
        return values.reduce(0, +) / Double(values.count)
    }

    private func headDisplacement(frame: PoseFrame, baseline: [PoseJointID: (x: Double, y: Double)]) -> Double? {
        guard let sample = frame.joints[.nose], let base = baseline[.nose] else {
            return nil
        }
        let dx = sample.x - base.x
        let dy = sample.y - base.y
        return (dx * dx + dy * dy).squareRoot()
    }

    private func recoveredTimestamp(
        in trajectory: [RecoveryTrajectorySample],
        afterPeakTime: Double,
        tolerance: Double,
        dwellSeconds: Double
    ) -> Double? {
        let candidates = trajectory.filter { $0.timeSinceEventSeconds >= afterPeakTime && $0.displacement <= tolerance }
        for candidate in candidates {
            let dwellEnd = candidate.timeSinceEventSeconds + dwellSeconds
            let dwellSamples = trajectory.filter {
                $0.timeSinceEventSeconds >= candidate.timeSinceEventSeconds && $0.timeSinceEventSeconds <= dwellEnd
            }
            if !dwellSamples.isEmpty,
               dwellSamples.last?.timeSinceEventSeconds ?? 0 >= dwellEnd,
               dwellSamples.allSatisfy({ $0.displacement <= tolerance }) {
                return candidate.timeSinceEventSeconds
            }
        }
        return nil
    }

    private func hasUsableCoverage(_ frames: [PoseFrame], eventTimestamp: Double, configuration: AnalysisConfiguration) -> Bool {
        guard frames.count >= 3 else {
            return false
        }
        let ordered = frames.sorted { $0.timestampSeconds < $1.timestampSeconds }
        for pair in zip(ordered, ordered.dropFirst()) {
            if pair.1.timestampSeconds - pair.0.timestampSeconds > configuration.liveFireMaximumPoseGapSeconds {
                return false
            }
        }
        let withJoints = ordered.filter { frame in
            recoveryJoints.filter { frame.joints[$0] != nil }.count >= 2
        }
        return Double(withJoints.count) / Double(ordered.count) >= configuration.liveFireMinimumPoseCoverage &&
            ordered.contains { $0.timestampSeconds < eventTimestamp } &&
            ordered.contains { $0.timestampSeconds >= eventTimestamp }
    }

    private func recoveryWindowFrames(
        around timestamp: Double,
        poseFrames: [PoseFrame],
        configuration: AnalysisConfiguration
    ) -> [PoseFrame] {
        let start = timestamp - configuration.liveFirePreEventWindowSeconds
        let end = timestamp + configuration.liveFirePostEventWindowSeconds
        return poseFrames.filter { $0.timestampSeconds >= start && $0.timestampSeconds <= end }
    }

    private func markOutliersAndSimilarity(
        _ events: [LiveEventAnalysis],
        configuration: AnalysisConfiguration
    ) -> [LiveEventAnalysis] {
        let accepted = events.filter { $0.status == .accepted && $0.peakVisibleDisplacement.value != nil }
        let peaks = accepted.compactMap(\.peakVisibleDisplacement.value)
        let medianPeak = median(peaks)
        let mad = median(peaks.map { abs($0 - medianPeak) })
        return events.map { event in
            let similarity = event.status == .accepted && event.peakVisibleDisplacement.value != nil
                ? max(0, 1 - abs((event.peakVisibleDisplacement.value ?? 0) - medianPeak) / max(configuration.similarityErrorScale, 0.000_001))
                : nil
            let isOutlier = peaks.count >= configuration.minimumRepsForOutlierDetection &&
                mad > configuration.zeroDispersionThreshold &&
                event.peakVisibleDisplacement.value.map { abs($0 - medianPeak) / mad > configuration.outlierMedianAbsoluteDeviationMultiplier } == true
            return LiveEventAnalysis(
                id: event.id,
                sessionID: event.sessionID,
                sequenceIndex: event.sequenceIndex,
                timestampSeconds: event.timestampSeconds,
                eventConfidence: event.eventConfidence,
                status: event.status,
                interEventDurationSeconds: event.interEventDurationSeconds,
                headDisplacement: event.headDisplacement,
                upperBodyDisplacement: event.upperBodyDisplacement,
                peakVisibleDisplacement: event.peakVisibleDisplacement,
                recoveryDuration: event.recoveryDuration,
                recoverySimilarity: similarity,
                recoveryConfidence: event.recoveryConfidence,
                isOutlier: isOutlier,
                poseAssetID: event.poseAssetID,
                reason: event.reason,
                trajectory: event.trajectory
            )
        }
    }

    private func recoveryConsistency(for events: [LiveEventAnalysis]) -> SessionConsistencyResult {
        let similarities = events.compactMap { event in
            event.status == .accepted ? event.recoverySimilarity : nil
        }
        guard similarities.count >= 3 else {
            return .unavailable(reason: .insufficientEligibleReps)
        }
        let value = similarities.reduce(0, +) / Double(similarities.count)
        return SessionConsistencyResult(availability: .available, internalValue: value, confidence: .medium, reason: .none)
    }

    private func minConfidence(_ lhs: ConfidenceStatus, _ rhs: ConfidenceStatus) -> ConfidenceStatus {
        if lhs == .low || rhs == .low {
            return .low
        }
        if lhs == .medium || rhs == .medium {
            return .medium
        }
        return .high
    }

    private func median(_ values: [Double]) -> Double {
        let sorted = values.sorted()
        guard !sorted.isEmpty else {
            return 0
        }
        let middle = sorted.count / 2
        return sorted.count.isMultiple(of: 2) ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle]
    }

    private var recoveryJoints: [PoseJointID] {
        [.nose, .leftShoulder, .rightShoulder]
    }
}
