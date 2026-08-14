import Foundation

public struct RepPoseSampleExtractor: Sendable {
    public init() {}

    public func samples(for segment: RepSegment, in recording: PoseRecording) -> [PoseFrame] {
        recording.poseFrames
            .filter { frame in
                frame.timestampSeconds >= segment.startTimestampSeconds &&
                    frame.timestampSeconds <= segment.completeTimestampSeconds
            }
            .sorted { $0.timestampSeconds < $1.timestampSeconds }
    }
}
