import CoreGraphics
import Foundation

public enum RepPlaybackPhase: String, Equatable, Sendable {
    case atStart
    case playing
    case paused
    case atEnd
}

public enum RepPlaybackSpeed: Double, CaseIterable, Equatable, Sendable {
    case quarter = 0.25
    case half = 0.5
    case normal = 1.0

    public var label: String {
        switch self {
        case .quarter:
            return "0.25x"
        case .half:
            return "0.5x"
        case .normal:
            return "1.0x"
        }
    }
}

public struct RepPlaybackJoint: Equatable, Sendable {
    public let jointID: PoseJointID
    public let x: Double
    public let y: Double
    public let confidence: Double
    public let isInterpolated: Bool

    public init(jointID: PoseJointID, x: Double, y: Double, confidence: Double, isInterpolated: Bool = false) {
        self.jointID = jointID
        self.x = x
        self.y = y
        self.confidence = confidence
        self.isInterpolated = isInterpolated
    }

    public init(_ sample: PoseAssetJointSample, isInterpolated: Bool = false) {
        self.init(
            jointID: sample.jointID,
            x: sample.x,
            y: sample.y,
            confidence: sample.confidence,
            isInterpolated: isInterpolated
        )
    }
}

public struct RepPlaybackPoseSample: Equatable, Sendable {
    public let sourceTimestampSeconds: Double
    public let repTimeSeconds: Double
    public let joints: [PoseJointID: RepPlaybackJoint]

    public init(sourceTimestampSeconds: Double, repTimeSeconds: Double, joints: [PoseJointID: RepPlaybackJoint]) {
        self.sourceTimestampSeconds = sourceTimestampSeconds
        self.repTimeSeconds = repTimeSeconds
        self.joints = joints
    }
}

public struct RepPlaybackModel: Equatable, Sendable {
    public let repID: UUID
    public let sessionStartTimestampSeconds: Double
    public let sessionEndTimestampSeconds: Double
    public let durationSeconds: Double
    public let orderedPoseSamples: [RepPlaybackPoseSample]
    public var currentTimeSeconds: Double
    public var phase: RepPlaybackPhase
    public var speed: RepPlaybackSpeed
    public var skeletonVisible: Bool
    public var trajectoryVisible: Bool

    public init(
        repID: UUID,
        sessionStartTimestampSeconds: Double,
        sessionEndTimestampSeconds: Double,
        orderedPoseSamples: [RepPlaybackPoseSample],
        currentTimeSeconds: Double = 0,
        phase: RepPlaybackPhase = .atStart,
        speed: RepPlaybackSpeed = .normal,
        skeletonVisible: Bool = true,
        trajectoryVisible: Bool = true
    ) {
        self.repID = repID
        self.sessionStartTimestampSeconds = sessionStartTimestampSeconds
        self.sessionEndTimestampSeconds = sessionEndTimestampSeconds
        self.durationSeconds = max(0, sessionEndTimestampSeconds - sessionStartTimestampSeconds)
        self.orderedPoseSamples = orderedPoseSamples.sorted { $0.repTimeSeconds < $1.repTimeSeconds }
        self.currentTimeSeconds = min(max(0, currentTimeSeconds), max(0, sessionEndTimestampSeconds - sessionStartTimestampSeconds))
        self.phase = phase
        self.speed = speed
        self.skeletonVisible = skeletonVisible
        self.trajectoryVisible = trajectoryVisible
    }

    public mutating func play() {
        if currentTimeSeconds >= durationSeconds {
            currentTimeSeconds = 0
        }
        phase = .playing
    }

    public mutating func pause() {
        phase = currentTimeSeconds >= durationSeconds ? .atEnd : .paused
    }

    public mutating func scrub(to timeSeconds: Double) {
        currentTimeSeconds = min(max(0, timeSeconds), durationSeconds)
        phase = currentTimeSeconds >= durationSeconds ? .atEnd : .paused
    }

    public mutating func advance(by elapsedSeconds: Double) {
        guard phase == .playing, elapsedSeconds.isFinite, elapsedSeconds > 0 else {
            return
        }
        currentTimeSeconds = min(durationSeconds, currentTimeSeconds + elapsedSeconds * speed.rawValue)
        if currentTimeSeconds >= durationSeconds {
            phase = .atEnd
        }
    }
}

public enum RepPlaybackModelBuilder {
    public static func make(repID: UUID, rep: AnalyzedRep, payload: PoseAssetPayload) -> RepPlaybackModel {
        let start = rep.segment.startTimestampSeconds
        let end = rep.segment.completeTimestampSeconds
        let samples = payload.frames
            .filter { $0.timestampSeconds >= start && $0.timestampSeconds <= end }
            .map { frame in
                RepPlaybackPoseSample(
                    sourceTimestampSeconds: frame.timestampSeconds,
                    repTimeSeconds: max(0, frame.timestampSeconds - start),
                    joints: Dictionary(uniqueKeysWithValues: frame.joints.map { ($0.jointID, RepPlaybackJoint($0)) })
                )
            }
        return RepPlaybackModel(
            repID: repID,
            sessionStartTimestampSeconds: start,
            sessionEndTimestampSeconds: end,
            orderedPoseSamples: samples
        )
    }
}
