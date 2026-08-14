import Foundation
#if os(iOS)
import AVFoundation
#endif

public enum MicrophoneAuthorizationStatus: Equatable, Sendable {
    case notDetermined
    case authorized
    case denied
    case restricted
}

public protocol MicrophonePermissionProviding: Sendable {
    func authorizationStatus() async -> MicrophoneAuthorizationStatus
    func requestAuthorization() async -> MicrophoneAuthorizationStatus
}

public struct SystemMicrophonePermissionProvider: MicrophonePermissionProviding {
    public init() {}

    public func authorizationStatus() async -> MicrophoneAuthorizationStatus {
        #if os(iOS)
        switch AVAudioSession.sharedInstance().recordPermission {
        case .granted:
            return .authorized
        case .denied:
            return .denied
        case .undetermined:
            return .notDetermined
        @unknown default:
            return .restricted
        }
        #else
        return .restricted
        #endif
    }

    public func requestAuthorization() async -> MicrophoneAuthorizationStatus {
        #if os(iOS)
        return await withCheckedContinuation { continuation in
            AVAudioSession.sharedInstance().requestRecordPermission { granted in
                continuation.resume(returning: granted ? .authorized : .denied)
            }
        }
        #else
        return .restricted
        #endif
    }
}
