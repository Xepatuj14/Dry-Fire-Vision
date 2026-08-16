import SwiftUI

struct DryFireSetupView: View {
    private let cameraCaptureProvider: any CameraCaptureProviding
    private let applicationSettingsOpener: any ApplicationSettingsOpening
    private let poseDetector: any PoseDetecting
    private let poseRecordingService: PoseRecordingService
    private let countdownProvider: any CountdownProviding
    private let sessionAnalyzer: any SessionAnalyzing
    private let sessionRepository: any SessionRepository
    private let poseAssetStore: any PoseAssetStoring
    private let settingsStore: any SettingsStoring
    @State private var retentionPreference: VideoRetentionPreference = .keep
    @State private var sessionLength: DryFireSessionLength = .ten
    @State private var maximumRepWindow: DryFireMaximumRepWindow = .five

    init(
        cameraCaptureProvider: any CameraCaptureProviding,
        applicationSettingsOpener: any ApplicationSettingsOpening,
        poseDetector: any PoseDetecting,
        poseRecordingService: PoseRecordingService,
        countdownProvider: any CountdownProviding,
        sessionAnalyzer: any SessionAnalyzing,
        sessionRepository: any SessionRepository,
        poseAssetStore: any PoseAssetStoring,
        settingsStore: any SettingsStoring
    ) {
        self.cameraCaptureProvider = cameraCaptureProvider
        self.applicationSettingsOpener = applicationSettingsOpener
        self.poseDetector = poseDetector
        self.poseRecordingService = poseRecordingService
        self.countdownProvider = countdownProvider
        self.sessionAnalyzer = sessionAnalyzer
        self.sessionRepository = sessionRepository
        self.poseAssetStore = poseAssetStore
        self.settingsStore = settingsStore
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Dry Fire Analysis")
                    .font(.title)
                    .fontWeight(.semibold)
                Text("Place your iPhone in a stable position with your body visible. Camera access is requested only when you continue.")
                    .foregroundStyle(.secondary)
            }

            Picker("Session Length", selection: $sessionLength) {
                ForEach(DryFireSessionLength.allCases, id: \.self) { length in
                    Text(length.title).tag(length)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityLabel("Session length")

            VStack(alignment: .leading, spacing: 8) {
                Picker("Rep Window", selection: $maximumRepWindow) {
                    ForEach(DryFireMaximumRepWindow.allCases, id: \.self) { window in
                        Text(window.title).tag(window)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityLabel("Rep window")

                Text("Maximum time allowed for each rep")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Picker("Video Retention", selection: $retentionPreference) {
                ForEach(VideoRetentionPreference.allCases, id: \.self) { preference in
                    Text(preference.title).tag(preference)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityLabel("Video retention preference")

            Text(retentionPreference.setupSummary)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .accessibilityLabel(retentionPreference.setupSummary)

            NavigationLink {
                CameraFlowView(
                    viewModel: CameraFlowViewModel(
                        cameraCaptureProvider: cameraCaptureProvider,
                        applicationSettingsOpener: applicationSettingsOpener,
                        poseDetector: poseDetector,
                        poseRecordingService: poseRecordingService,
                        countdownProvider: countdownProvider,
                        sessionConfiguration: sessionConfiguration
                    ),
                    sessionAnalyzer: sessionAnalyzer,
                    sessionRepository: sessionRepository,
                    poseAssetStore: poseAssetStore,
                    videoRetentionPreference: retentionPreference,
                    sessionConfiguration: sessionConfiguration
                )
            } label: {
                Label("Continue to Camera", systemImage: "camera.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .accessibilityLabel("Continue to camera")

            Spacer()
        }
        .padding()
        .navigationTitle("Dry Fire Setup")
        .task {
            retentionPreference = await settingsStore.videoRetentionPreference
        }
        .onChange(of: retentionPreference) { _, newValue in
            Task {
                await settingsStore.setVideoRetentionPreference(newValue)
            }
        }
    }

    private var sessionConfiguration: DryFireSessionConfiguration {
        DryFireSessionConfiguration(
            sessionLength: sessionLength,
            maximumRepWindow: maximumRepWindow
        )
    }
}
