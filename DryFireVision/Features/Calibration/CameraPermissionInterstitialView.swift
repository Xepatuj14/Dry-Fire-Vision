import SwiftUI

struct CameraPermissionInterstitialView: View {
    let continueAction: () async -> Void
    let cancelAction: () async -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: "camera.viewfinder")
                    .font(.largeTitle)
                    .accessibilityHidden(true)
                Text("Camera Access")
                    .font(.title)
                    .fontWeight(.semibold)
                Text("Dry Fire Vision uses the camera to detect body pose and analyze visible movement during training.")
                    .foregroundStyle(.secondary)
            }

            Button {
                Task {
                    await continueAction()
                }
            } label: {
                Label("Continue", systemImage: "camera.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .accessibilityLabel("Continue and request camera access")

            Button("Back to Train") {
                Task {
                    await cancelAction()
                }
            }
            .buttonStyle(.bordered)
            .frame(maxWidth: .infinity)
            .accessibilityLabel("Back to Train")

            Spacer()
        }
        .padding()
    }
}
