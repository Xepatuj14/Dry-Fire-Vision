import SwiftUI

struct CameraStartingView: View {
    var body: some View {
        VStack(spacing: 16) {
            ProgressView()
            Text("Camera Starting")
                .font(.headline)
            Text("Preparing the live preview.")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Camera starting. Preparing the live preview.")
    }
}
