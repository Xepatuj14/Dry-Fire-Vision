import SwiftUI

public struct TrainRootView: View {
    private let featureFlags: FeatureFlags
    private let cameraCaptureProvider: any CameraCaptureProviding
    private let applicationSettingsOpener: any ApplicationSettingsOpening
    private let poseDetector: any PoseDetecting
    private let poseRecordingService: PoseRecordingService
    private let countdownProvider: any CountdownProviding
    private let sessionAnalyzer: any SessionAnalyzing
    private let sessionRepository: any SessionRepository
    private let poseAssetStore: any PoseAssetStoring
    private let settingsStore: any SettingsStoring
    private let microphonePermissionProvider: any MicrophonePermissionProviding

    public init(
        featureFlags: FeatureFlags,
        cameraCaptureProvider: any CameraCaptureProviding,
        applicationSettingsOpener: any ApplicationSettingsOpening,
        poseDetector: any PoseDetecting,
        poseRecordingService: PoseRecordingService,
        countdownProvider: any CountdownProviding,
        sessionAnalyzer: any SessionAnalyzing,
        sessionRepository: any SessionRepository,
        poseAssetStore: any PoseAssetStoring,
        settingsStore: any SettingsStoring,
        microphonePermissionProvider: any MicrophonePermissionProviding
    ) {
        self.featureFlags = featureFlags
        self.cameraCaptureProvider = cameraCaptureProvider
        self.applicationSettingsOpener = applicationSettingsOpener
        self.poseDetector = poseDetector
        self.poseRecordingService = poseRecordingService
        self.countdownProvider = countdownProvider
        self.sessionAnalyzer = sessionAnalyzer
        self.sessionRepository = sessionRepository
        self.poseAssetStore = poseAssetStore
        self.settingsStore = settingsStore
        self.microphonePermissionProvider = microphonePermissionProvider
    }

    public var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Dry Fire Vision")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    Text("Run your first 10-rep analysis to establish a baseline.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                }

                NavigationLink {
                    DryFireSetupView(
                        cameraCaptureProvider: cameraCaptureProvider,
                        applicationSettingsOpener: applicationSettingsOpener,
                        poseDetector: poseDetector,
                        poseRecordingService: poseRecordingService,
                        countdownProvider: countdownProvider,
                        sessionAnalyzer: sessionAnalyzer,
                        sessionRepository: sessionRepository,
                        poseAssetStore: poseAssetStore,
                        settingsStore: settingsStore
                    )
                } label: {
                    Label("Start Dry Fire", systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                RecentSessionCard(sessionRepository: sessionRepository, poseAssetStore: poseAssetStore)

                if featureFlags.liveFireBetaEnabled {
                    NavigationLink {
                        LiveFireBetaSetupView(
                            viewModel: LiveFireBetaViewModel(microphonePermissionProvider: microphonePermissionProvider),
                            applicationSettingsOpener: applicationSettingsOpener
                        )
                    } label: {
                        Label("Live Fire Beta", systemImage: "waveform")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }

                Spacer()
            }
            .padding()
            .navigationTitle("Train")
        }
    }
}
