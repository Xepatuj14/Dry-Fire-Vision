import Foundation
import SwiftData

public struct DependencyContainer: Sendable {
    public let appRouter: AppRouter
    public let featureFlags: FeatureFlags
    public let versions: VersionCatalog
    public let sessionAnalyzer: any SessionAnalyzing
    public let sessionRepository: any SessionRepository
    public let progressRepository: any ProgressRepository
    public let poseAssetStore: any PoseAssetStoring
    public let maintenanceService: any MaintenanceServicing
    public let settingsStore: any SettingsStoring
    public let cameraCaptureProvider: any CameraCaptureProviding
    public let applicationSettingsOpener: any ApplicationSettingsOpening
    public let poseDetector: any PoseDetecting
    public let poseRecordingService: PoseRecordingService
    public let countdownProvider: any CountdownProviding
    public let microphonePermissionProvider: any MicrophonePermissionProviding

    public init(
        appRouter: AppRouter,
        featureFlags: FeatureFlags,
        versions: VersionCatalog,
        sessionAnalyzer: any SessionAnalyzing,
        sessionRepository: any SessionRepository,
        progressRepository: any ProgressRepository,
        poseAssetStore: any PoseAssetStoring,
        maintenanceService: any MaintenanceServicing,
        settingsStore: any SettingsStoring,
        cameraCaptureProvider: any CameraCaptureProviding,
        applicationSettingsOpener: any ApplicationSettingsOpening,
        poseDetector: any PoseDetecting,
        poseRecordingService: PoseRecordingService,
        countdownProvider: any CountdownProviding,
        microphonePermissionProvider: any MicrophonePermissionProviding
    ) {
        self.appRouter = appRouter
        self.featureFlags = featureFlags
        self.versions = versions
        self.sessionAnalyzer = sessionAnalyzer
        self.sessionRepository = sessionRepository
        self.progressRepository = progressRepository
        self.poseAssetStore = poseAssetStore
        self.maintenanceService = maintenanceService
        self.settingsStore = settingsStore
        self.cameraCaptureProvider = cameraCaptureProvider
        self.applicationSettingsOpener = applicationSettingsOpener
        self.poseDetector = poseDetector
        self.poseRecordingService = poseRecordingService
        self.countdownProvider = countdownProvider
        self.microphonePermissionProvider = microphonePermissionProvider
    }

    public static func production() -> DependencyContainer {
        let sessionRepository: any SessionRepository
        let progressRepository: any ProgressRepository
        let poseAssetStore: any PoseAssetStoring
        let maintenanceService: any MaintenanceServicing
        do {
            let filePoseAssetStore = try FilePoseAssetStore.applicationSupportStore()
            let fileMediaAssetStore = try FileMediaAssetStore.applicationSupportStore()
            poseAssetStore = filePoseAssetStore
            let swiftDataSessionRepository = SwiftDataSessionRepository(
                modelContainer: ModelContainer(for: DryFireVisionPersistenceSchema.schema),
                poseAssetStore: filePoseAssetStore,
                mediaAssetStore: fileMediaAssetStore
            )
            sessionRepository = swiftDataSessionRepository
            progressRepository = SessionProgressRepository(sessionRepository: swiftDataSessionRepository)
            maintenanceService = MaintenanceService(repository: swiftDataSessionRepository)
        } catch {
            poseAssetStore = UnimplementedPoseAssetStore()
            sessionRepository = UnimplementedSessionRepository()
            progressRepository = UnimplementedProgressRepository()
            maintenanceService = NoopMaintenanceService()
        }

        DependencyContainer(
            appRouter: AppRouter(),
            featureFlags: .production,
            versions: .current,
            sessionAnalyzer: SessionAnalysisPipeline(),
            sessionRepository: sessionRepository,
            progressRepository: progressRepository,
            poseAssetStore: poseAssetStore,
            maintenanceService: maintenanceService,
            settingsStore: UserDefaultsSettingsStore(),
            cameraCaptureProvider: AVFoundationCameraCaptureProvider(),
            applicationSettingsOpener: SystemApplicationSettingsOpener(),
            poseDetector: VisionPoseDetector(),
            poseRecordingService: PoseRecordingService(),
            countdownProvider: LiveCountdownProvider(),
            microphonePermissionProvider: SystemMicrophonePermissionProvider()
        )
    }
}
