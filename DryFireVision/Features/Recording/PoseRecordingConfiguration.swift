import Foundation

public struct PoseRecordingConfiguration: Equatable, Sendable {
    public let countdownSeconds: Int
    public let finalRepCompletionBufferSeconds: Double

    public init(countdownSeconds: Int = 3, finalRepCompletionBufferSeconds: Double = 1.5) {
        self.countdownSeconds = countdownSeconds
        self.finalRepCompletionBufferSeconds = finalRepCompletionBufferSeconds
    }
}
