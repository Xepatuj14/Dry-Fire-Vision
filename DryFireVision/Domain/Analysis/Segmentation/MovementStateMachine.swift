import Foundation

public struct MovementStateMachine: Sendable {
    public let configuration: AnalysisConfiguration

    public init(configuration: AnalysisConfiguration) {
        self.configuration = configuration
    }

    public func process(samples: [MovementSignalSample]) -> SegmentationResult {
        var engine = Engine(configuration: configuration)
        for sample in samples {
            engine.process(sample)
        }
        return engine.finish(inputSampleCount: samples.count)
    }
}

private struct Engine {
    private let timeComparisonTolerance = 0.000_000_001
    let configuration: AnalysisConfiguration
    var state: MovementAnalysisState = .waitingForStable
    var stableStartTimestamp: Double?
    var startCandidateTimestamp: Double?
    var currentRepStartTimestamp: Double?
    var activeMovementEndTimestamp: Double?
    var settleStartTimestamp: Double?
    var resetStartTimestamp: Double?
    var unavailableSignalCount = 0
    var lastSampleTimestamp: Double?
    var failureReasons: [SegmentationReason] = []
    var diagnostics: [SegmentationDiagnostic] = []
    var segments: [RepSegment] = []
    var rejectedSegments: [RepSegment] = []

    mutating func process(_ sample: MovementSignalSample) {
        lastSampleTimestamp = sample.timestampSeconds
        if sample.availability == .firstUsableSample {
            return
        }

        guard sample.availability == .available, let velocity = sample.velocity else {
            unavailableSignalCount += 1
            appendFailure(.poseSignalUnavailable)
            diagnostics.append(SegmentationDiagnostic(
                event: .poseSignalUnavailable,
                timestampSeconds: sample.timestampSeconds,
                fromState: state,
                movementSignal: sample.velocity,
                baselineDistance: sample.baselineDistance,
                reason: .poseSignalUnavailable
            ))
            if state == .waitingForStable || state == .ready {
                stableStartTimestamp = nil
                startCandidateTimestamp = nil
            }
            return
        }

        switch state {
        case .waitingForStable:
            processWaitingForStable(sample: sample, velocity: velocity)
        case .ready:
            processReady(sample: sample, velocity: velocity)
        case .moving:
            processMoving(sample: sample, velocity: velocity)
        case .settling:
            processSettling(sample: sample, velocity: velocity)
        case .complete:
            transition(to: .resetting, sample: sample, threshold: configuration.resetBaselineDistanceThreshold)
            processResetting(sample: sample, velocity: velocity)
        case .resetting:
            processResetting(sample: sample, velocity: velocity)
        }
    }

    mutating func finish(inputSampleCount: Int) -> SegmentationResult {
        if let repStart = currentRepStartTimestamp,
           let lastTimestamp = lastSampleTimestamp,
           lastTimestamp - repStart > configuration.plausibleRepDurationMaximumSeconds {
            let segment = makeSegment(
                start: repStart,
                activeEnd: activeMovementEndTimestamp,
                complete: lastTimestamp,
                sequenceIndex: segments.count + rejectedSegments.count,
                forcedReason: .durationAboveMaximum
            )
            rejectedSegments.append(segment)
            appendFailure(.durationAboveMaximum)
        }

        let status: SegmentationStatus
        if failureReasons.contains(.invalidTimestampSequence) || failureReasons.contains(.unusableCalibration) {
            status = .failed
        } else if !failureReasons.isEmpty || !rejectedSegments.isEmpty {
            status = .degraded
        } else {
            status = .complete
        }

        diagnostics.append(SegmentationDiagnostic(
            event: .repCompleted,
            timestampSeconds: lastSampleTimestamp ?? 0,
            reason: segments.isEmpty ? .none : nil
        ))

        return SegmentationResult(
            segments: segments,
            rejectedSegments: rejectedSegments,
            diagnostics: diagnostics,
            status: status,
            inputSampleCount: inputSampleCount,
            analysisVersion: VersionCatalog.current.analysisVersion,
            configurationVersion: configuration.version,
            failureReasons: failureReasons
        )
    }

    mutating private func processWaitingForStable(sample: MovementSignalSample, velocity: Double) {
        if velocity <= configuration.readyStabilityThreshold {
            if stableStartTimestamp == nil {
                stableStartTimestamp = sample.timestampSeconds
            }
            if let stableStart = stableStartTimestamp,
               sample.timestampSeconds - stableStart + timeComparisonTolerance >= configuration.readyStabilityWindowSeconds {
                transition(to: .ready, sample: sample, threshold: configuration.readyStabilityThreshold)
            }
        } else {
            stableStartTimestamp = nil
        }
    }

    mutating private func processReady(sample: MovementSignalSample, velocity: Double) {
        if velocity > configuration.movementStartThreshold {
            if startCandidateTimestamp == nil {
                startCandidateTimestamp = sample.timestampSeconds
                diagnostics.append(SegmentationDiagnostic(
                    event: .startCandidate,
                    timestampSeconds: sample.timestampSeconds,
                    fromState: state,
                    movementSignal: velocity,
                    baselineDistance: sample.baselineDistance,
                    threshold: configuration.movementStartThreshold
                ))
            }
            if let candidate = startCandidateTimestamp,
               sample.timestampSeconds - candidate + timeComparisonTolerance >= configuration.movementStartConfirmationWindowSeconds {
                currentRepStartTimestamp = candidate
                activeMovementEndTimestamp = nil
                settleStartTimestamp = nil
                diagnostics.append(SegmentationDiagnostic(
                    event: .startConfirmed,
                    timestampSeconds: sample.timestampSeconds,
                    fromState: .ready,
                    toState: .moving,
                    movementSignal: velocity,
                    baselineDistance: sample.baselineDistance,
                    threshold: configuration.movementStartThreshold
                ))
                transition(to: .moving, sample: sample, threshold: configuration.movementStartThreshold)
            }
        } else {
            if startCandidateTimestamp != nil {
                diagnostics.append(SegmentationDiagnostic(
                    event: .falseStartRejected,
                    timestampSeconds: sample.timestampSeconds,
                    fromState: .ready,
                    toState: .ready,
                    movementSignal: velocity,
                    baselineDistance: sample.baselineDistance,
                    threshold: configuration.movementStartThreshold,
                    reason: .falseStartRejected
                ))
            }
            startCandidateTimestamp = nil
        }
    }

    mutating private func processMoving(sample: MovementSignalSample, velocity: Double) {
        if velocity < configuration.activeMovementThreshold {
            activeMovementEndTimestamp = sample.timestampSeconds
            settleStartTimestamp = sample.timestampSeconds
            transition(to: .settling, sample: sample, threshold: configuration.activeMovementThreshold)
        }
    }

    mutating private func processSettling(sample: MovementSignalSample, velocity: Double) {
        if velocity >= configuration.activeMovementThreshold {
            settleStartTimestamp = nil
            activeMovementEndTimestamp = nil
            transition(to: .moving, sample: sample, threshold: configuration.activeMovementThreshold)
            return
        }

        if velocity <= configuration.settleThreshold {
            if settleStartTimestamp == nil {
                settleStartTimestamp = sample.timestampSeconds
            }
            if let settleStart = settleStartTimestamp,
               sample.timestampSeconds - settleStart + timeComparisonTolerance >= configuration.settleWindowSeconds,
               let repStart = currentRepStartTimestamp {
                let segment = makeSegment(
                    start: repStart,
                    activeEnd: activeMovementEndTimestamp,
                    complete: sample.timestampSeconds,
                    sequenceIndex: segments.count + rejectedSegments.count
                )
                if segment.validity == .valid {
                    segments.append(segment)
                } else {
                    rejectedSegments.append(segment)
                    appendFailure(segment.diagnosticReason)
                    diagnostics.append(SegmentationDiagnostic(
                        event: .repDurationRejected,
                        timestampSeconds: sample.timestampSeconds,
                        movementSignal: velocity,
                        baselineDistance: sample.baselineDistance,
                        reason: segment.diagnosticReason
                    ))
                }
                diagnostics.append(SegmentationDiagnostic(
                    event: .repCompleted,
                    timestampSeconds: sample.timestampSeconds,
                    fromState: .settling,
                    toState: .complete,
                    movementSignal: velocity,
                    baselineDistance: sample.baselineDistance,
                    threshold: configuration.settleThreshold
                ))
                transition(to: .complete, sample: sample, threshold: configuration.settleThreshold)
                currentRepStartTimestamp = nil
                activeMovementEndTimestamp = nil
                settleStartTimestamp = nil
            }
        } else {
            settleStartTimestamp = nil
        }
    }

    mutating private func processResetting(sample: MovementSignalSample, velocity: Double) {
        guard velocity <= configuration.readyStabilityThreshold,
              let baselineDistance = sample.baselineDistance,
              baselineDistance <= configuration.resetBaselineDistanceThreshold else {
            resetStartTimestamp = nil
            return
        }

        if resetStartTimestamp == nil {
            resetStartTimestamp = sample.timestampSeconds
        }

        if let resetStart = resetStartTimestamp,
           sample.timestampSeconds - resetStart + timeComparisonTolerance >= configuration.resetStabilityWindowSeconds {
            diagnostics.append(SegmentationDiagnostic(
                event: .resetConfirmed,
                timestampSeconds: sample.timestampSeconds,
                fromState: .resetting,
                toState: .ready,
                movementSignal: velocity,
                baselineDistance: baselineDistance,
                threshold: configuration.resetBaselineDistanceThreshold
            ))
            transition(to: .ready, sample: sample, threshold: configuration.resetBaselineDistanceThreshold)
            self.resetStartTimestamp = nil
        }
    }

    mutating private func makeSegment(
        start: Double,
        activeEnd: Double?,
        complete: Double,
        sequenceIndex: Int,
        forcedReason: SegmentationReason? = nil
    ) -> RepSegment {
        let duration = complete - start
        let validity: RepValidity
        let reason: SegmentationReason

        if let forcedReason {
            validity = .invalid
            reason = forcedReason
        } else if duration < configuration.plausibleRepDurationMinimumSeconds {
            validity = .invalid
            reason = .durationBelowMinimum
        } else if duration > configuration.plausibleRepDurationMaximumSeconds {
            validity = .invalid
            reason = .durationAboveMaximum
        } else {
            validity = .valid
            reason = .none
        }

        return RepSegment(
            id: deterministicSegmentID(sequenceIndex: sequenceIndex, start: start, complete: complete),
            sequenceIndex: sequenceIndex,
            startTimestampSeconds: start,
            activeMovementEndTimestampSeconds: activeEnd,
            completeTimestampSeconds: complete,
            validity: validity,
            confidenceStatus: unavailableSignalCount == 0 ? .high : .medium,
            diagnosticReason: reason
        )
    }

    mutating private func transition(to newState: MovementAnalysisState, sample: MovementSignalSample, threshold: Double?) {
        let oldState = state
        state = newState
        diagnostics.append(SegmentationDiagnostic(
            event: .stateTransition,
            timestampSeconds: sample.timestampSeconds,
            fromState: oldState,
            toState: newState,
            movementSignal: sample.velocity,
            baselineDistance: sample.baselineDistance,
            threshold: threshold
        ))
    }

    mutating private func appendFailure(_ reason: SegmentationReason) {
        if !failureReasons.contains(reason) {
            failureReasons.append(reason)
        }
    }

    private func deterministicSegmentID(sequenceIndex: Int, start: Double, complete: Double) -> UUID {
        let seed = UInt64(sequenceIndex + 1) &* 1_000_003
            &+ UInt64((start * 1000).rounded())
            &+ UInt64((complete * 1000).rounded()) &* 97
        return UUID(uuid: (
            0, 0, 0, 0,
            0, 0,
            UInt8((seed >> 40) & 0xff),
            UInt8((seed >> 32) & 0xff),
            UInt8((seed >> 24) & 0xff),
            UInt8((seed >> 16) & 0xff),
            UInt8((seed >> 8) & 0xff),
            UInt8(seed & 0xff),
            UInt8(sequenceIndex & 0xff),
            UInt8((sequenceIndex >> 8) & 0xff),
            UInt8((sequenceIndex >> 16) & 0xff),
            UInt8((sequenceIndex >> 24) & 0xff)
        ))
    }
}
