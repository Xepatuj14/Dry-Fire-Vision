import Foundation

public enum CameraCaptureLifecycleEvent: Equatable, Sendable {
    case interrupted
    case interruptionEnded
    case runtimeError
}
