import SwiftUI

struct CameraFailureView: View {
    let title: String
    let message: String
    let retryAction: () async -> Void
    let exitAction: () async -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.largeTitle)
                    .accessibilityHidden(true)
                Text(title)
                    .font(.title)
                    .fontWeight(.semibold)
                Text(message)
                    .foregroundStyle(.secondary)
            }

            Button {
                Task {
                    await retryAction()
                }
            } label: {
                Label("Retry", systemImage: "arrow.clockwise")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .accessibilityLabel("Retry camera preview")

            Button("Back to Train") {
                Task {
                    await exitAction()
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
