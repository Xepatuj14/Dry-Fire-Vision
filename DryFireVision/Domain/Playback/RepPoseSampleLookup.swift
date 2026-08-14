import Foundation

public struct RepPoseSampleLookup: Sendable {
    public let maximumInterpolationGapSeconds: Double

    public init(maximumInterpolationGapSeconds: Double = 0.12) {
        self.maximumInterpolationGapSeconds = maximumInterpolationGapSeconds
    }

    public func sample(at repTimeSeconds: Double, in samples: [RepPlaybackPoseSample]) -> RepPlaybackPoseSample? {
        guard let first = samples.first else {
            return nil
        }
        guard samples.count > 1 else {
            return first
        }
        let clampedTime = min(max(0, repTimeSeconds), samples.last?.repTimeSeconds ?? repTimeSeconds)
        if clampedTime <= first.repTimeSeconds {
            return first
        }
        if let last = samples.last, clampedTime >= last.repTimeSeconds {
            return last
        }

        for index in 0..<(samples.count - 1) {
            let lower = samples[index]
            let upper = samples[index + 1]
            if clampedTime == lower.repTimeSeconds {
                return lower
            }
            guard lower.repTimeSeconds < clampedTime, clampedTime < upper.repTimeSeconds else {
                continue
            }
            let gap = upper.repTimeSeconds - lower.repTimeSeconds
            guard gap > 0, gap <= maximumInterpolationGapSeconds else {
                return nearest(to: clampedTime, lower: lower, upper: upper)
            }
            let ratio = (clampedTime - lower.repTimeSeconds) / gap
            return interpolatedSample(lower: lower, upper: upper, ratio: ratio, repTimeSeconds: clampedTime)
        }

        return samples.last
    }

    public func previousStoredSample(before repTimeSeconds: Double, in samples: [RepPlaybackPoseSample]) -> RepPlaybackPoseSample? {
        samples.last { $0.repTimeSeconds < repTimeSeconds }
    }

    public func nextStoredSample(after repTimeSeconds: Double, in samples: [RepPlaybackPoseSample]) -> RepPlaybackPoseSample? {
        samples.first { $0.repTimeSeconds > repTimeSeconds }
    }

    private func nearest(
        to timeSeconds: Double,
        lower: RepPlaybackPoseSample,
        upper: RepPlaybackPoseSample
    ) -> RepPlaybackPoseSample {
        abs(timeSeconds - lower.repTimeSeconds) <= abs(upper.repTimeSeconds - timeSeconds) ? lower : upper
    }

    private func interpolatedSample(
        lower: RepPlaybackPoseSample,
        upper: RepPlaybackPoseSample,
        ratio: Double,
        repTimeSeconds: Double
    ) -> RepPlaybackPoseSample {
        let sharedJointIDs = Set(lower.joints.keys).intersection(upper.joints.keys)
        let joints = Dictionary(uniqueKeysWithValues: sharedJointIDs.compactMap { jointID -> (PoseJointID, RepPlaybackJoint)? in
            guard let start = lower.joints[jointID], let end = upper.joints[jointID] else {
                return nil
            }
            return (
                jointID,
                RepPlaybackJoint(
                    jointID: jointID,
                    x: start.x + (end.x - start.x) * ratio,
                    y: start.y + (end.y - start.y) * ratio,
                    confidence: min(start.confidence, end.confidence),
                    isInterpolated: true
                )
            )
        })
        return RepPlaybackPoseSample(
            sourceTimestampSeconds: lower.sourceTimestampSeconds + (upper.sourceTimestampSeconds - lower.sourceTimestampSeconds) * ratio,
            repTimeSeconds: repTimeSeconds,
            joints: joints
        )
    }
}
