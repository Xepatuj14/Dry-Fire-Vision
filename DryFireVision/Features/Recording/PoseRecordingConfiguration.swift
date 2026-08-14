import Foundation

public struct PoseRecordingConfiguration: Equatable, Sendable {
    public let countdownSeconds: Int

    public init(countdownSeconds: Int = 3) {
        self.countdownSeconds = countdownSeconds
    }
}
