import Foundation

public enum GhostTimingMode: String, CaseIterable, Equatable, Sendable {
    case normalizedPhase

    public var label: String {
        switch self {
        case .normalizedPhase:
            return "Normalized Phase"
        }
    }
}

public enum GhostPlaybackPhase: String, Equatable, Sendable {
    case atStart
    case playing
    case paused
    case atEnd
}

public struct GhostPlaybackPose: Equatable, Sendable {
    public let phase: Double
    public let joints: [PoseJointID: RepPlaybackJoint]

    public init(phase: Double, joints: [PoseJointID: RepPlaybackJoint]) {
        self.phase = phase
        self.joints = joints
    }
}

public struct GhostPlaybackModel: Equatable, Sendable {
    public let repAID: UUID
    public let repBID: UUID
    public let repADurationSeconds: Double
    public let repBDurationSeconds: Double
    public let alignedRepA: PhaseAlignedRep
    public let alignedRepB: PhaseAlignedRep
    public var currentPhase: Double
    public var phase: GhostPlaybackPhase
    public var speed: RepPlaybackSpeed
    public var timingMode: GhostTimingMode
    public var skeletonVisible: Bool
    public var trajectoryVisible: Bool

    public var comparisonDurationSeconds: Double {
        max(repADurationSeconds, repBDurationSeconds, 0.01)
    }

    public init(
        repAID: UUID,
        repBID: UUID,
        repADurationSeconds: Double,
        repBDurationSeconds: Double,
        alignedRepA: PhaseAlignedRep,
        alignedRepB: PhaseAlignedRep,
        currentPhase: Double = 0,
        phase: GhostPlaybackPhase = .atStart,
        speed: RepPlaybackSpeed = .normal,
        timingMode: GhostTimingMode = .normalizedPhase,
        skeletonVisible: Bool = true,
        trajectoryVisible: Bool = true
    ) {
        self.repAID = repAID
        self.repBID = repBID
        self.repADurationSeconds = repADurationSeconds
        self.repBDurationSeconds = repBDurationSeconds
        self.alignedRepA = alignedRepA
        self.alignedRepB = alignedRepB
        self.currentPhase = min(max(0, currentPhase), 1)
        self.phase = phase
        self.speed = speed
        self.timingMode = timingMode
        self.skeletonVisible = skeletonVisible
        self.trajectoryVisible = trajectoryVisible
    }

    public mutating func play() {
        if currentPhase >= 1 {
            currentPhase = 0
        }
        phase = .playing
    }

    public mutating func pause() {
        phase = currentPhase >= 1 ? .atEnd : .paused
    }

    public mutating func scrub(to phase: Double) {
        currentPhase = min(max(0, phase), 1)
        self.phase = currentPhase >= 1 ? .atEnd : .paused
    }

    public mutating func advance(by elapsedSeconds: Double) {
        guard phase == .playing, elapsedSeconds.isFinite, elapsedSeconds > 0 else {
            return
        }
        currentPhase = min(1, currentPhase + (elapsedSeconds * speed.rawValue / comparisonDurationSeconds))
        if currentPhase >= 1 {
            phase = .atEnd
        }
    }
}

public struct GhostPoseLookup: Sendable {
    public init() {}

    public func pose(at phase: Double, in alignedRep: PhaseAlignedRep) -> GhostPlaybackPose? {
        let clampedPhase = min(max(0, phase), 1)
        let jointPairs = alignedRep.trajectories.compactMap { jointID, samples -> (PoseJointID, RepPlaybackJoint)? in
            guard let sample = sample(at: clampedPhase, samples: samples) else {
                return nil
            }
            return (
                jointID,
                RepPlaybackJoint(
                    jointID: jointID,
                    x: sample.x,
                    y: sample.y,
                    confidence: sample.confidence,
                    isInterpolated: sample.interpolated
                )
            )
        }
        guard !jointPairs.isEmpty else {
            return nil
        }
        return GhostPlaybackPose(phase: clampedPhase, joints: Dictionary(uniqueKeysWithValues: jointPairs))
    }

    public func trajectory(
        jointID: PoseJointID,
        in alignedRep: PhaseAlignedRep,
        through phase: Double
    ) -> [RepPlaybackJoint] {
        let clampedPhase = min(max(0, phase), 1)
        return (alignedRep.trajectories[jointID] ?? []).compactMap { sample in
            guard let sample, sample.phase <= clampedPhase else {
                return nil
            }
            return RepPlaybackJoint(
                jointID: jointID,
                x: sample.x,
                y: sample.y,
                confidence: sample.confidence,
                isInterpolated: sample.interpolated
            )
        }
    }

    private func sample(at phase: Double, samples: [PhaseSample?]) -> PhaseSample? {
        let available = samples.compactMap { $0 }.sorted { $0.phase < $1.phase }
        guard let first = available.first else {
            return nil
        }
        if phase <= first.phase {
            return first
        }
        guard let last = available.last else {
            return first
        }
        if phase >= last.phase {
            return last
        }
        if let exact = available.first(where: { abs($0.phase - phase) <= 0.000_000_001 }) {
            return exact
        }
        guard let before = available.last(where: { $0.phase < phase }),
              let after = available.first(where: { $0.phase > phase }) else {
            return nil
        }
        let phaseGap = after.phase - before.phase
        guard phaseGap > 0 else {
            return nil
        }
        let fraction = (phase - before.phase) / phaseGap
        return PhaseSample(
            phase: phase,
            sourceTimestampSeconds: before.sourceTimestampSeconds + (after.sourceTimestampSeconds - before.sourceTimestampSeconds) * fraction,
            x: before.x + (after.x - before.x) * fraction,
            y: before.y + (after.y - before.y) * fraction,
            confidence: min(before.confidence, after.confidence),
            interpolated: true
        )
    }
}
