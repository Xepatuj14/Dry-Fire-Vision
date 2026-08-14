import SwiftUI

struct RecentSessionCard: View {
    let sessionRepository: any SessionRepository
    let poseAssetStore: any PoseAssetStoring
    @State private var state: RecentSessionState = .loading

    var body: some View {
        Group {
            switch state {
            case .loading:
                ProgressView("Checking saved sessions")
                    .frame(maxWidth: .infinity, alignment: .leading)
            case .empty:
                EmptyView()
            case .loaded(let snapshot):
                if let analysis = snapshot.analysis {
                    NavigationLink {
                        RecentSessionResultsDestination(
                            analysis: analysis,
                            sessionRepository: sessionRepository,
                            poseAssetStore: poseAssetStore
                        )
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            Label("Recent Session", systemImage: "clock")
                                .font(.headline)
                            Text("\(analysis.validRepCount) valid reps analyzed")
                                .font(.subheadline)
                            Text("Saved locally")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.thinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .accessibilityLabel("Open recent saved session")
                }
            case .failed:
                EmptyView()
            }
        }
        .task {
            await load()
        }
    }

    private func load() async {
        do {
            let sessions = try await sessionRepository.recentCompletedSessions(limit: 1)
            state = sessions.first.map(RecentSessionState.loaded) ?? .empty
        } catch {
            state = .failed
        }
    }
}

private enum RecentSessionState: Equatable {
    case loading
    case empty
    case loaded(TrainingSessionSnapshot)
    case failed
}

private struct RecentSessionResultsDestination: View {
    @Environment(\.dismiss) private var dismiss
    let analysis: SessionAnalysis
    let sessionRepository: any SessionRepository
    let poseAssetStore: any PoseAssetStoring

    var body: some View {
        SessionResultsView(
            analysis: analysis,
            sessionRepository: sessionRepository,
            poseAssetStore: poseAssetStore
        ) {
            dismiss()
        }
    }
}
