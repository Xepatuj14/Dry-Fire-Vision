import Combine
import Foundation

public enum LiveFireBetaSetupState: Equatable, Sendable {
    case introduction
    case microphonePermissionRequired
    case ready
    case permissionDenied
    case restricted
}

@MainActor
public final class LiveFireBetaViewModel: ObservableObject {
    @Published public private(set) var state: LiveFireBetaSetupState = .introduction

    private let microphonePermissionProvider: any MicrophonePermissionProviding

    public init(microphonePermissionProvider: any MicrophonePermissionProviding) {
        self.microphonePermissionProvider = microphonePermissionProvider
    }

    public func acknowledgeAndContinue() {
        Task {
            await refreshPermission()
        }
    }

    public func requestMicrophonePermission() {
        Task {
            let status = await microphonePermissionProvider.requestAuthorization()
            apply(status)
        }
    }

    public func refreshPermission() async {
        let status = await microphonePermissionProvider.authorizationStatus()
        apply(status)
    }

    private func apply(_ status: MicrophoneAuthorizationStatus) {
        switch status {
        case .notDetermined:
            state = .microphonePermissionRequired
        case .authorized:
            state = .ready
        case .denied:
            state = .permissionDenied
        case .restricted:
            state = .restricted
        }
    }
}

