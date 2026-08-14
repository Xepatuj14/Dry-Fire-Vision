import SwiftUI

public struct AppShellView: View {
    private let dependencyContainer: DependencyContainer
    @State private var selectedTab: AppTab
    @Environment(\.scenePhase) private var scenePhase

    public init(dependencyContainer: DependencyContainer) {
        self.dependencyContainer = dependencyContainer
        self._selectedTab = State(initialValue: dependencyContainer.appRouter.selectedTab)
    }

    public var body: some View {
        TabView(selection: $selectedTab) {
            TrainRootView(
                featureFlags: dependencyContainer.featureFlags,
                cameraCaptureProvider: dependencyContainer.cameraCaptureProvider,
                applicationSettingsOpener: dependencyContainer.applicationSettingsOpener,
                poseDetector: dependencyContainer.poseDetector,
                poseRecordingService: dependencyContainer.poseRecordingService,
                countdownProvider: dependencyContainer.countdownProvider,
                sessionAnalyzer: dependencyContainer.sessionAnalyzer,
                sessionRepository: dependencyContainer.sessionRepository,
                poseAssetStore: dependencyContainer.poseAssetStore,
                settingsStore: dependencyContainer.settingsStore,
                microphonePermissionProvider: dependencyContainer.microphonePermissionProvider
            )
                .tabItem {
                    Label("Train", systemImage: "figure.strengthtraining.traditional")
                }
                .tag(AppTab.train)

            ProgressRootView(
                sessionRepository: dependencyContainer.sessionRepository,
                progressRepository: dependencyContainer.progressRepository,
                poseAssetStore: dependencyContainer.poseAssetStore
            )
                .tabItem {
                    Label("Progress", systemImage: "chart.line.uptrend.xyaxis")
                }
                .tag(AppTab.progress)

            SettingsRootView(
                featureFlags: dependencyContainer.featureFlags,
                versions: dependencyContainer.versions,
                settingsStore: dependencyContainer.settingsStore
            )
            .tabItem {
                Label("Settings", systemImage: "gearshape")
            }
            .tag(AppTab.settings)
        }
        .task {
            try? await dependencyContainer.maintenanceService.performMaintenance()
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else {
                return
            }
            Task {
                try? await dependencyContainer.maintenanceService.performMaintenance()
            }
        }
    }
}
