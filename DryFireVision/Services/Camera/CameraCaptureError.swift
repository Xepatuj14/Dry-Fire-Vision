import Foundation

public enum CameraCaptureError: Error, Equatable, Sendable {
    case permissionDenied
    case permissionRestricted
    case deviceUnavailable
    case cannotAddInput
    case sessionInterrupted
    case runtimeFailure
}
