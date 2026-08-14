import Foundation

public enum CameraPermissionRecoveryReason: Equatable, Sendable {
    case denied
    case restricted
}

public enum CameraFailureReason: Equatable, Sendable {
    case deviceUnavailable
    case cannotAddInput
    case runtimeFailure
}

public enum CameraFlowState: Equatable, Sendable {
    case permissionRequired
    case startingCamera
    case active
    case interrupted
    case failed(CameraFailureReason)
    case permissionRecovery(CameraPermissionRecoveryReason)
}
