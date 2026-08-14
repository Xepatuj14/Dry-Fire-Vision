import DryFireVisionCore
import Foundation

public enum LiveFireSyntheticFixtureID: String, CaseIterable, Sendable {
    case clean5 = "LF_CLEAN_5"
    case variableRecovery = "LF_VARIABLE_RECOVERY"
    case backgroundOnly = "LF_BACKGROUND_ONLY"
    case mixedNoise = "LF_MIXED_NOISE"
    case clippedAudio = "LF_CLIPPED_AUDIO"
    case cameraMoved = "LF_CAMERA_MOVED"
    case poseOccluded = "LF_POSE_OCCLUDED"
}

public enum LiveFireSyntheticFixtures {
    public static func input(_ id: LiveFireSyntheticFixtureID) -> LiveFireSynchronizedInput {
        let sessionID = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 15, UInt8(LiveFireSyntheticFixtureID.allCases.firstIndex(of: id) ?? 0)))
        let eventTimes: [Double]
        let amplitudes: [Double]
        switch id {
        case .clean5:
            eventTimes = [1.0, 1.6, 2.2, 2.8, 3.4]
            amplitudes = Array(repeating: 0.95, count: eventTimes.count)
        case .variableRecovery:
            eventTimes = [1.0, 1.7, 2.4, 3.1, 3.8]
            amplitudes = Array(repeating: 0.95, count: eventTimes.count)
        case .backgroundOnly:
            eventTimes = [1.0, 1.12, 1.8]
            amplitudes = [0.76, 0.72, 0.74]
        case .mixedNoise:
            eventTimes = [1.0, 1.08, 1.7, 2.3]
            amplitudes = [0.95, 0.80, 0.70, 0.95]
        case .clippedAudio:
            eventTimes = [1.0]
            amplitudes = [1.0]
        case .cameraMoved:
            eventTimes = [1.0]
            amplitudes = [0.95]
        case .poseOccluded:
            eventTimes = [1.0]
            amplitudes = [0.95]
        }
        return LiveFireSynchronizedInput(
            sessionID: sessionID,
            createdAt: Date(timeIntervalSince1970: 1_000),
            audioSamples: audio(eventTimes: eventTimes, amplitudes: amplitudes),
            poseFrames: poseFrames(for: id, eventTimes: eventTimes),
            normalizationScale: id == .cameraMoved ? 0.2 : 0.2
        )
    }

    public static func audio(eventTimes: [Double], amplitudes: [Double]) -> [AudioSignalSample] {
        var samples = stride(from: 0.0, through: 5.0, by: 0.02).map {
            AudioSignalSample(timestampSeconds: $0, amplitude: 0.03)
        }
        for (time, amplitude) in zip(eventTimes, amplitudes) {
            samples.append(AudioSignalSample(timestampSeconds: time, amplitude: amplitude))
            samples.append(AudioSignalSample(timestampSeconds: time + 0.03, amplitude: amplitude * 0.55))
        }
        return samples.sorted { $0.timestampSeconds < $1.timestampSeconds }
    }

    public static func poseFrames(for id: LiveFireSyntheticFixtureID, eventTimes: [Double]) -> [PoseFrame] {
        stride(from: 0.0, through: 5.0, by: 0.05).map { time in
            let offset = recoveryOffset(time: time, eventTimes: eventTimes, fixtureID: id)
            if id == .poseOccluded, let event = eventTimes.first, time > event + 0.10 {
                return PoseFrame(timestampSeconds: time, joints: [
                    .nose: JointSample(jointID: .nose, x: 0.50, y: 0.14, confidence: 0.9)
                ])
            }
            return pose(timestamp: time, xOffset: offset)
        }
    }

    private static func recoveryOffset(time: Double, eventTimes: [Double], fixtureID: LiveFireSyntheticFixtureID) -> Double {
        guard let event = eventTimes.last(where: { time >= $0 }) else {
            return 0
        }
        let elapsed = time - event
        switch fixtureID {
        case .backgroundOnly, .clippedAudio:
            return 0
        case .poseOccluded:
            return elapsed > 0.12 ? 0.0 : 0.10
        case .cameraMoved:
            return time > event + 0.10 ? 0.30 : 0.0
        case .variableRecovery:
            let duration = 0.25 + Double(eventTimes.firstIndex(of: event) ?? 0) * 0.10
            return elapsed <= duration ? max(0, 0.12 * (1 - elapsed / duration)) : 0
        case .clean5, .mixedNoise:
            return elapsed <= 0.30 ? max(0, 0.12 * (1 - elapsed / 0.30)) : 0
        }
    }

    private static func pose(timestamp: Double, xOffset: Double) -> PoseFrame {
        let joints: [PoseJointID: JointSample] = [
            .nose: JointSample(jointID: .nose, x: 0.50 + xOffset, y: 0.14, confidence: 0.9),
            .leftShoulder: JointSample(jointID: .leftShoulder, x: 0.40 + xOffset, y: 0.28, confidence: 0.9),
            .rightShoulder: JointSample(jointID: .rightShoulder, x: 0.60 + xOffset, y: 0.28, confidence: 0.9)
        ]
        return PoseFrame(timestampSeconds: timestamp, joints: joints)
    }
}
