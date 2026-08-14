import Foundation
import SwiftUI

public struct SessionResultsView: View {
    private let viewModel: SessionResultsViewModel
    private let returnToTrain: () -> Void
    private let sessionRepository: any SessionRepository
    private let poseAssetStore: any PoseAssetStoring

    @State private var isDeletingSession = false
    @State private var showDeleteConfirmation = false
    @State private var deleteErrorMessage: String?
    @State private var privacyStatusText: String?

    public init(
        analysis: SessionAnalysis,
        sessionRepository: any SessionRepository,
        poseAssetStore: any PoseAssetStoring,
        returnToTrain: @escaping () -> Void
    ) {
        self.viewModel = SessionResultsViewModel(analysis: analysis)
        self.sessionRepository = sessionRepository
        self.poseAssetStore = poseAssetStore
        self.returnToTrain = returnToTrain
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header

                if viewModel.state.displayState == .noValidReps {
                    noValidReps
                } else {
                    headlineMetrics
                    highlightGrid
                    outliersSection
                    repList
                }

                if let deleteErrorMessage {
                    Text(deleteErrorMessage)
                        .font(.subheadline)
                        .foregroundStyle(.red)
                        .accessibilityLabel(deleteErrorMessage)
                }

                Button(role: .destructive) {
                    showDeleteConfirmation = true
                } label: {
                    Label(isDeletingSession ? "Deleting Session" : "Delete Session", systemImage: "trash")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(isDeletingSession)
                .accessibilityLabel("Delete Session")

                Button {
                    returnToTrain()
                } label: {
                    Label("Return to Train", systemImage: "house")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityLabel("Return to Train")
            }
            .padding()
        }
        .navigationTitle("Results")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(
            "Delete this session?",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete Session", role: .destructive) {
                deleteCurrentSession()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the saved session from History and deletes any local pose playback assets for its reps.")
        }
    }

    private func deleteCurrentSession() {
        isDeletingSession = true
        deleteErrorMessage = nil
        Task {
            do {
                try await sessionRepository.deleteSession(id: viewModel.analysis.sessionID)
                await MainActor.run {
                    isDeletingSession = false
                    returnToTrain()
                }
            } catch {
                await MainActor.run {
                    isDeletingSession = false
                    deleteErrorMessage = "Dry Fire Vision could not delete this saved session."
                }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(viewModel.state.title)
                .font(.title2)
                .fontWeight(.semibold)
            Text(viewModel.state.sessionContextText)
                .foregroundStyle(.secondary)
            Text(viewModel.state.repCountText)
                .font(.headline)
            if let target = viewModel.state.targetRepText {
                Text(target)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if let message = viewModel.state.message {
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if let privacyStatusText {
                Text(privacyStatusText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(privacyStatusText)
            }
        }
        .accessibilityElement(children: .combine)
        .task {
            privacyStatusText = await loadPrivacyStatusText()
        }
    }

    private func loadPrivacyStatusText() async -> String? {
        guard let snapshot = try? await sessionRepository.session(id: viewModel.analysis.sessionID) else {
            return nil
        }
        switch snapshot.videoMediaAvailability {
        case .videoAvailable:
            return "Raw video retained for this session."
        case .videoDeletedByPreference:
            return "Raw video removed after analysis. Pose playback and metrics are preserved."
        case .videoDeletionPending:
            return "Analysis was saved. Raw video removal will continue at the next maintenance opportunity."
        case .videoDeletionFailed:
            return "Analysis was saved, but the raw video could not be removed yet. Dry Fire Vision will retry."
        case .videoMissing:
            return "Saved metrics remain, but retained video is currently unavailable."
        case .notRecorded:
            return "Raw video was not recorded for this session. Pose playback and metrics are preserved."
        case .unavailable:
            return nil
        }
    }

    private var headlineMetrics: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Session Summary")
                .font(.headline)
            HStack(spacing: 12) {
                SessionSummaryCard(title: "Average Duration", value: viewModel.state.averageDurationText)
                SessionSummaryCard(title: "Movement Consistency", value: viewModel.state.movementConsistencyText)
            }
            SessionSummaryCard(title: "Analysis Confidence", value: viewModel.state.confidenceText)
        }
    }

    @ViewBuilder
    private var highlightGrid: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Standout Reps")
                .font(.headline)
            if let representative = viewModel.state.representativeRep {
                NavigationLink {
                    repReviewDestination(repID: representative.id)
                } label: {
                    HighlightRepCard(state: representative)
                }
                .accessibilityLabel("Open Representative Rep Review")
            }
            if let fastest = viewModel.state.fastestRep {
                NavigationLink {
                    repReviewDestination(repID: fastest.id)
                } label: {
                    HighlightRepCard(state: fastest)
                }
                .accessibilityLabel("Open Fastest Rep Review")
            }
            if let representative = viewModel.state.representativeRep {
                NavigationLink {
                    ghostModeDestination(referenceRepID: representative.id)
                } label: {
                    Label("Compare Repetitions", systemImage: "square.stack.3d.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("Open Ghost Mode with Representative Rep as reference")
            }
        }
    }

    @ViewBuilder
    private var outliersSection: some View {
        if !viewModel.state.outlierRows.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("Movement Outliers")
                    .font(.headline)
                ForEach(viewModel.state.outlierRows) { row in
                    NavigationLink {
                        repReviewDestination(repID: row.id)
                    } label: {
                        RepRow(state: row)
                    }
                    .accessibilityLabel("Open Movement Outlier Rep Review")
                }
            }
        }
    }

    private var repList: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Repetitions")
                .font(.headline)
            ForEach(viewModel.state.repRows) { row in
                NavigationLink {
                    repReviewDestination(repID: row.id)
                } label: {
                    RepRow(state: row)
                }
                .accessibilityLabel("Open \(row.repNumberText) Review")
            }
        }
    }

    private func repReviewDestination(repID: UUID) -> some View {
        RepReviewView(
            viewModel: RepReviewViewModel(
                sessionID: viewModel.analysis.sessionID,
                repID: repID,
                sessionRepository: sessionRepository,
                poseAssetStore: poseAssetStore
            ),
            sessionRepository: sessionRepository,
            poseAssetStore: poseAssetStore
        )
    }

    private func ghostModeDestination(referenceRepID: UUID) -> some View {
        GhostModeView(
            viewModel: GhostModeViewModel(
                sessionID: viewModel.analysis.sessionID,
                referenceRepID: referenceRepID,
                sessionRepository: sessionRepository,
                poseAssetStore: poseAssetStore
            )
        )
    }

    private var noValidReps: some View {
        PlaceholderStateView(
            title: "No Valid Repetitions Detected",
            message: "Dry Fire Vision kept the analysis result empty instead of inventing reps. Return to Train to run another capture.",
            systemImage: "figure.strengthtraining.traditional"
        )
    }
}

private struct SessionSummaryCard: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.headline)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .combine)
    }
}

private struct HighlightRepCard: View {
    let state: HighlightRepState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(state.title)
                .font(.headline)
            HStack {
                Text(state.repNumberText)
                    .fontWeight(.semibold)
                Spacer()
                Text(state.durationText)
                    .foregroundStyle(.secondary)
            }
            Text(state.detailText)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .combine)
    }
}

private struct RepRow: View {
    let state: SessionResultsRepRowState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(state.repNumberText)
                    .font(.headline)
                Spacer()
                Text(state.durationText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            HStack {
                Text(state.validityText)
                Text("Head \(state.headMetricText)")
                Text("Wrist \(state.wristMetricText)")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(2)
            if !state.badges.isEmpty {
                FlowBadgeRow(labels: state.badges)
            }
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
    }
}

private struct FlowBadgeRow: View {
    let labels: [String]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(labels, id: \.self) { label in
                Text(label)
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.quaternary)
                    .clipShape(Capsule())
            }
        }
    }
}
