import SwiftUI

struct CameraFlowView: View {
    @StateObject private var viewModel: CameraFlowViewModel
    private let sessionAnalyzer: any SessionAnalyzing
    private let sessionRepository: any SessionRepository
    private let poseAssetStore: any PoseAssetStoring
    private let videoRetentionPreference: VideoRetentionPreference
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    init(
        viewModel: CameraFlowViewModel,
        sessionAnalyzer: any SessionAnalyzing,
        sessionRepository: any SessionRepository,
        poseAssetStore: any PoseAssetStoring,
        videoRetentionPreference: VideoRetentionPreference
    ) {
        self._viewModel = StateObject(wrappedValue: viewModel)
        self.sessionAnalyzer = sessionAnalyzer
        self.sessionRepository = sessionRepository
        self.poseAssetStore = poseAssetStore
        self.videoRetentionPreference = videoRetentionPreference
    }

    var body: some View {
        content
            .navigationTitle("Calibration")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        Task {
                            await viewModel.leave()
                            dismiss()
                        }
                    }
                    .accessibilityLabel("Cancel camera flow")
                }
            }
            .task {
                await viewModel.enter()
            }
            .onDisappear {
                Task {
                    await viewModel.leave()
                }
            }
            .onChange(of: scenePhase) { _, newPhase in
                Task {
                    switch newPhase {
                    case .active:
                        await viewModel.refreshAfterForeground()
                    case .background:
                        await viewModel.leave()
                    case .inactive:
                        break
                    @unknown default:
                        break
                    }
                }
            }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .permissionRequired:
            CameraPermissionInterstitialView(
                continueAction: {
                    await viewModel.continueFromPermissionInterstitial()
                },
                cancelAction: {
                    await viewModel.leave()
                    dismiss()
                }
            )
        case .startingCamera:
            CameraStartingView()
        case .active:
            if case .completed(let recording) = viewModel.recordingState {
                ProcessingView(
                    viewModel: ProcessingViewModel(
                        sessionAnalyzer: sessionAnalyzer,
                        sessionRepository: sessionRepository,
                        videoRetentionPreference: videoRetentionPreference,
                        input: AnalysisInput(recording: recording, targetRepCount: 10)
                    ),
                    sessionRepository: sessionRepository,
                    poseAssetStore: poseAssetStore
                )
            } else {
                CalibrationPreviewView(
                    previewSession: viewModel.previewSession,
                    poseFrame: viewModel.latestPoseFrame,
                    calibrationState: viewModel.calibrationState,
                    recordingState: viewModel.recordingState,
                    selectedCameraPosition: viewModel.selectedCameraPosition,
                    canSwitchCamera: viewModel.canSwitchCamera,
                    switchCameraAction: {
                        await viewModel.switchCamera()
                    },
                    startRecordingAction: {
                        viewModel.startRecordingCountdown()
                    },
                    stopRecordingAction: {
                        await viewModel.stopRecording()
                    },
                    cancelRecordingAction: {
                        await viewModel.cancelRecording()
                    }
                )
            }
        case .interrupted:
            CameraFailureView(
                title: "Camera Interrupted",
                message: "Camera access was interrupted. Try again when the camera is available.",
                retryAction: {
                    await viewModel.retryCameraStart()
                },
                exitAction: {
                    await viewModel.leave()
                    dismiss()
                }
            )
        case .failed(let reason):
            CameraFailureView(
                title: failureTitle(for: reason),
                message: failureMessage(for: reason),
                retryAction: {
                    await viewModel.retryCameraStart()
                },
                exitAction: {
                    await viewModel.leave()
                    dismiss()
                }
            )
        case .permissionRecovery(let reason):
            CameraPermissionRecoveryView(
                reason: reason,
                openSettingsAction: {
                    await viewModel.openSettings()
                },
                backToTrainAction: {
                    await viewModel.leave()
                    dismiss()
                }
            )
        }
    }

    private func failureTitle(for reason: CameraFailureReason) -> String {
        switch reason {
        case .deviceUnavailable:
            return "Camera Unavailable"
        case .cannotAddInput:
            return "Camera Could Not Start"
        case .runtimeFailure:
            return "Camera Error"
        }
    }

    private func failureMessage(for reason: CameraFailureReason) -> String {
        switch reason {
        case .deviceUnavailable:
            return "This device does not expose a supported camera for Dry Fire setup."
        case .cannotAddInput:
            return "Dry Fire Vision could not configure the selected camera."
        case .runtimeFailure:
            return "Dry Fire Vision could not start the camera preview."
        }
    }
}
