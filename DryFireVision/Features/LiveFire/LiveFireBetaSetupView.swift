import SwiftUI

public struct LiveFireBetaSetupView: View {
    @StateObject private var viewModel: LiveFireBetaViewModel
    private let applicationSettingsOpener: any ApplicationSettingsOpening

    public init(
        viewModel: LiveFireBetaViewModel,
        applicationSettingsOpener: any ApplicationSettingsOpening
    ) {
        self._viewModel = StateObject(wrappedValue: viewModel)
        self.applicationSettingsOpener = applicationSettingsOpener
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Live Fire Beta")
                .font(.title)
                .fontWeight(.semibold)
            Text("Visible Movement & Recovery")
                .font(.headline)
                .foregroundStyle(.secondary)

            switch viewModel.state {
            case .introduction:
                introduction
            case .microphonePermissionRequired:
                permissionRequest
            case .ready:
                ready
            case .permissionDenied:
                permissionRecovery("Microphone access is required for acoustic event detection. Dry Fire remains fully available.")
            case .restricted:
                permissionRecovery("Microphone access is restricted on this device. Dry Fire remains fully available.")
            }
            Spacer()
        }
        .padding()
        .navigationTitle("Live Fire Beta")
    }

    private var introduction: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("This beta analyzes visible body movement and recovery around candidate acoustic events.")
            Text("Surrounding range noise can reduce confidence. Ambiguous events will not produce strong recovery claims.")
            Text("Dry Fire Vision does not determine shot placement, target impact, ballistic performance, or physical recoil force.")
            Text("Place the phone only where permitted and where it does not interfere with range operations.")
            Button {
                viewModel.acknowledgeAndContinue()
            } label: {
                Label("Continue", systemImage: "checkmark.circle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .accessibilityLabel("Continue to Live Fire Beta permission check")
        }
    }

    private var permissionRequest: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Microphone access is requested only for Live Fire Beta acoustic event detection.")
            Button {
                viewModel.requestMicrophonePermission()
            } label: {
                Label("Allow Microphone", systemImage: "mic")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .accessibilityLabel("Allow microphone for Live Fire Beta")
        }
    }

    private var ready: some View {
        PlaceholderStateView(
            title: "Live Fire Beta Foundation Ready",
            message: "Microphone access is available. Synchronized real-device capture still requires native/TestFlight validation before external beta use.",
            systemImage: "waveform"
        )
    }

    private func permissionRecovery(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(message)
            Button {
                Task {
                    await applicationSettingsOpener.openApplicationSettings()
                }
            } label: {
                Label("Open Settings", systemImage: "gearshape")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .accessibilityLabel("Open Settings for microphone permission")
        }
    }
}
