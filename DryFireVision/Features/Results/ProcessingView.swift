import SwiftUI

public struct ProcessingView: View {
    @StateObject private var viewModel: ProcessingViewModel
    @Environment(\.dismiss) private var dismiss
    private let sessionRepository: any SessionRepository
    private let poseAssetStore: any PoseAssetStoring

    public init(
        viewModel: ProcessingViewModel,
        sessionRepository: any SessionRepository,
        poseAssetStore: any PoseAssetStoring
    ) {
        self._viewModel = StateObject(wrappedValue: viewModel)
        self.sessionRepository = sessionRepository
        self.poseAssetStore = poseAssetStore
    }

    public var body: some View {
        Group {
            switch viewModel.state {
            case .preparing:
                processingContent(title: "Preparing", message: "Getting the recording ready for analysis.")
            case .analyzing:
                processingContent(title: "Analyzing movement", message: "Detecting repetitions, calculating movement metrics, and comparing reps.")
            case .saving:
                processingContent(title: "Saving results", message: "Saving the analyzed session before opening Results.")
            case .complete(let analysis), .degraded(let analysis):
                SessionResultsView(
                    analysis: analysis,
                    sessionRepository: sessionRepository,
                    poseAssetStore: poseAssetStore
                ) {
                    dismiss()
                }
            case .persistenceFailed(let failure):
                VStack(spacing: 16) {
                    PlaceholderStateView(
                        title: failure.title,
                        message: failure.message,
                        systemImage: "externaldrive.badge.exclamationmark"
                    )
                    Button {
                        viewModel.retryPersistence()
                    } label: {
                        Label("Retry Save", systemImage: "arrow.clockwise")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    Button {
                        dismiss()
                    } label: {
                        Label("Return to Train", systemImage: "house")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
                .padding()
            case .failed(let failure):
                PlaceholderStateView(
                    title: failure.title,
                    message: failure.message,
                    systemImage: "exclamationmark.triangle"
                )
            }
        }
        .navigationTitle("Processing")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(isBusy)
        .task {
            viewModel.startAnalysisIfNeeded()
        }
        .onDisappear {
            if isBusy {
                viewModel.cancel()
            }
        }
    }

    private var isBusy: Bool {
        switch viewModel.state {
        case .preparing, .analyzing, .saving:
            return true
        case .complete, .degraded, .persistenceFailed, .failed:
            return false
        }
    }

    private func processingContent(title: String, message: String) -> some View {
        VStack(spacing: 16) {
            ProgressView()
                .accessibilityLabel("Analysis in progress")
            Text(title)
                .font(.title2)
                .fontWeight(.semibold)
            Text(message)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }
}
