import Foundation

public struct AudioSignalSample: Equatable, Sendable {
    public let timestampSeconds: Double
    public let amplitude: Double

    public init(timestampSeconds: Double, amplitude: Double) {
        self.timestampSeconds = timestampSeconds
        self.amplitude = amplitude
    }
}

public enum LiveEventStatus: String, Codable, Equatable, Sendable {
    case accepted
    case ambiguous
    case rejected
}

public enum LiveEventReason: String, Codable, Equatable, Sendable {
    case none
    case belowThreshold
    case clippedAudio
    case neighboringImpulse
    case noisyBackground
    case insufficientPoseCoverage
    case recoveryUnavailable
    case invalidNormalization
    case cameraMovement
}

public struct CandidateAudioEvent: Equatable, Identifiable, Sendable {
    public let id: UUID
    public let timestampSeconds: Double
    public let peakAmplitude: Double
    public let noiseFloor: Double
    public let isClipped: Bool
    public let confidence: ConfidenceStatus
    public let status: LiveEventStatus
    public let reason: LiveEventReason

    public init(
        id: UUID = UUID(),
        timestampSeconds: Double,
        peakAmplitude: Double,
        noiseFloor: Double,
        isClipped: Bool,
        confidence: ConfidenceStatus,
        status: LiveEventStatus,
        reason: LiveEventReason
    ) {
        self.id = id
        self.timestampSeconds = timestampSeconds
        self.peakAmplitude = peakAmplitude
        self.noiseFloor = noiseFloor
        self.isClipped = isClipped
        self.confidence = confidence
        self.status = status
        self.reason = reason
    }
}

public protocol AudioEventDetecting: Sendable {
    func detectCandidates(in samples: [AudioSignalSample], configuration: AnalysisConfiguration) -> [CandidateAudioEvent]
}

public struct AudioEventDetector: AudioEventDetecting {
    public init() {}

    public func detectCandidates(in samples: [AudioSignalSample], configuration: AnalysisConfiguration = .provisionalSegmentationV1) -> [CandidateAudioEvent] {
        let ordered = samples
            .filter { $0.timestampSeconds.isFinite && $0.amplitude.isFinite }
            .sorted { $0.timestampSeconds < $1.timestampSeconds }
        guard !ordered.isEmpty else {
            return []
        }

        let noiseFloor = median(ordered.map { abs($0.amplitude) })
        var candidates: [CandidateAudioEvent] = []
        var debouncePeak: AudioSignalSample?

        func flushDebouncePeak() {
            guard let peak = debouncePeak else {
                return
            }
            candidates.append(makeCandidate(peak: peak, noiseFloor: noiseFloor, configuration: configuration))
            debouncePeak = nil
        }

        for sample in ordered where abs(sample.amplitude) >= configuration.liveFireAudioImpulseThreshold {
            if let current = debouncePeak,
               sample.timestampSeconds - current.timestampSeconds <= configuration.liveFireDebounceWindowSeconds {
                if abs(sample.amplitude) > abs(current.amplitude) {
                    debouncePeak = sample
                }
            } else {
                flushDebouncePeak()
                debouncePeak = sample
            }
        }
        flushDebouncePeak()

        var spaced: [CandidateAudioEvent] = []
        for candidate in candidates {
            if let previous = spaced.last,
               candidate.timestampSeconds - previous.timestampSeconds < configuration.liveFireMinimumEventSpacingSeconds {
                let stronger = candidate.peakAmplitude > previous.peakAmplitude ? candidate : previous
                let weaker = candidate.peakAmplitude > previous.peakAmplitude ? previous : candidate
                spaced[spaced.count - 1] = CandidateAudioEvent(
                    id: stronger.id,
                    timestampSeconds: stronger.timestampSeconds,
                    peakAmplitude: stronger.peakAmplitude,
                    noiseFloor: stronger.noiseFloor,
                    isClipped: stronger.isClipped,
                    confidence: .medium,
                    status: .ambiguous,
                    reason: weaker.isClipped ? .clippedAudio : .neighboringImpulse
                )
            } else {
                spaced.append(candidate)
            }
        }
        return spaced
    }

    private func makeCandidate(
        peak: AudioSignalSample,
        noiseFloor: Double,
        configuration: AnalysisConfiguration
    ) -> CandidateAudioEvent {
        let amplitude = abs(peak.amplitude)
        let isClipped = amplitude >= 0.995
        let confidence: ConfidenceStatus
        let status: LiveEventStatus
        let reason: LiveEventReason

        if isClipped {
            confidence = .medium
            status = .ambiguous
            reason = .clippedAudio
        } else if amplitude >= configuration.liveFireAudioHighConfidenceThreshold && noiseFloor < configuration.liveFireAudioImpulseThreshold * 0.45 {
            confidence = .high
            status = .accepted
            reason = .none
        } else if amplitude >= configuration.liveFireAudioMediumConfidenceThreshold {
            confidence = .medium
            status = .ambiguous
            reason = noiseFloor >= configuration.liveFireAudioImpulseThreshold * 0.45 ? .noisyBackground : .none
        } else {
            confidence = .low
            status = .rejected
            reason = .belowThreshold
        }

        return CandidateAudioEvent(
            id: stableID(timestampSeconds: peak.timestampSeconds),
            timestampSeconds: peak.timestampSeconds,
            peakAmplitude: amplitude,
            noiseFloor: noiseFloor,
            isClipped: isClipped,
            confidence: confidence,
            status: status,
            reason: reason
        )
    }

    private func stableID(timestampSeconds: Double) -> UUID {
        let milliseconds = max(0, Int((timestampSeconds * 1_000).rounded()))
        return UUID(uuid: (
            UInt8((milliseconds >> 56) & 0xff),
            UInt8((milliseconds >> 48) & 0xff),
            UInt8((milliseconds >> 40) & 0xff),
            UInt8((milliseconds >> 32) & 0xff),
            UInt8((milliseconds >> 24) & 0xff),
            UInt8((milliseconds >> 16) & 0xff),
            UInt8((milliseconds >> 8) & 0xff),
            UInt8(milliseconds & 0xff),
            0, 0, 0, 0, 0, 0, 15, 15
        ))
    }

    private func median(_ values: [Double]) -> Double {
        let sorted = values.sorted()
        guard !sorted.isEmpty else {
            return 0
        }
        let middle = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return (sorted[middle - 1] + sorted[middle]) / 2
        }
        return sorted[middle]
    }
}
