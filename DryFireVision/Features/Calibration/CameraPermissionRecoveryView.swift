import SwiftUI

struct CameraPermissionRecoveryView: View {
    let reason: CameraPermissionRecoveryReason
    let openSettingsAction: () async -> Void
    let backToTrainAction: () async -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: "camera.badge.ellipsis")
                    .font(.largeTitle)
                    .accessibilityHidden(true)
                Text(title)
                    .font(.title)
                    .fontWeight(.semibold)
                Text(message)
                    .foregroundStyle(.secondary)
            }

            if reason == .denied {
                Button {
                    Task {
                        await openSettingsAction()
                    }
                } label: {
                    Label("Open Settings", systemImage: "gearshape")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityLabel("Open app settings")
            }

            Button("Back to Train") {
                Task {
                    await backToTrainAction()
                }
            }
            .buttonStyle(.bordered)
            .frame(maxWidth: .infinity)
            .accessibilityLabel("Back to Train")

            Spacer()
        }
        .padding()
    }

    private var title: String {
        switch reason {
        case .denied:
            return "Camera Access Needed"
        case .restricted:
            return "Camera Access Restricted"
        }
    }

    private var message: String {
        switch reason {
        case .denied:
            return "Enable camera access in Settings to continue into Dry Fire setup."
        case .restricted:
            return "Camera access is restricted on this device. Dry Fire setup cannot continue until access is available."
        }
    }
}
