import Charts
import SwiftUI

public struct ProgressRootView: View {
    @StateObject private var viewModel: ProgressViewModel

    private let sessionRepository: any SessionRepository
    private let poseAssetStore: any PoseAssetStoring

    public init(
        sessionRepository: any SessionRepository,
        progressRepository: any ProgressRepository,
        poseAssetStore: any PoseAssetStoring
    ) {
        self.sessionRepository = sessionRepository
        self.poseAssetStore = poseAssetStore
        _viewModel = StateObject(
            wrappedValue: ProgressViewModel(
                sessionRepository: sessionRepository,
                progressRepository: progressRepository
            )
        )
    }

    public var body: some View {
        NavigationStack {
            content
                .navigationTitle("Progress")
                .task {
                    viewModel.load()
                }
                .refreshable {
                    viewModel.refreshAfterReturningFromDetail()
                }
                .confirmationDialog(
                    "Delete this session?",
                    isPresented: deleteConfirmationBinding,
                    titleVisibility: .visible,
                    presenting: viewModel.pendingDeletion
                ) { row in
                    Button("Delete Session", role: .destructive) {
                        viewModel.confirmDeletePendingSession()
                    }
                    Button("Cancel", role: .cancel) {
                        viewModel.cancelDelete()
                    }
                } message: { row in
                    Text("\(row.dateText) will be removed from History, trends, records, baselines, and local pose playback.")
                }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .loading:
            ProgressView("Loading progress...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .empty(let snapshot):
            progressBody(snapshot: snapshot)
        case .populated(let snapshot):
            progressBody(snapshot: snapshot)
        case .deleting(let snapshot, _):
            progressBody(snapshot: snapshot)
                .disabled(true)
                .overlay {
                    ProgressView("Deleting session...")
                        .padding()
                        .background(.regularMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
        case .failed(let message):
            VStack(spacing: 16) {
                PlaceholderStateView(
                    title: "Progress Unavailable",
                    message: message,
                    systemImage: "chart.xyaxis.line"
                )
                Button {
                    viewModel.load()
                } label: {
                    Label("Retry", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    private func progressBody(snapshot: ProgressViewSnapshot) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                TrendSectionView(state: snapshot.durationTrend, valueUnit: "seconds")
                TrendSectionView(state: snapshot.consistencyTrend, valueUnit: "internal consistency")

                PersonalRecordsSection(
                    records: snapshot.personalRecords,
                    historyRows: snapshot.historyRows,
                    sessionRepository: sessionRepository,
                    poseAssetStore: poseAssetStore,
                    refreshAfterDetail: viewModel.refreshAfterReturningFromDetail
                )
                PersonalBaselinesSection(baselines: snapshot.baselines)

                HistorySection(
                    rows: snapshot.historyRows,
                    sessionRepository: sessionRepository,
                    poseAssetStore: poseAssetStore,
                    requestDelete: viewModel.requestDelete(_:),
                    refreshAfterDetail: viewModel.refreshAfterReturningFromDetail
                )

                Text(snapshot.generatedSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding()
        }
        .accessibilityElement(children: .contain)
    }

    private var deleteConfirmationBinding: Binding<Bool> {
        Binding(
            get: { viewModel.pendingDeletion != nil },
            set: { isPresented in
                if !isPresented {
                    viewModel.cancelDelete()
                }
            }
        )
    }
}

private struct TrendSectionView: View {
    let state: TrendSectionState
    let valueUnit: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(state.title)
                    .font(.headline)
                Spacer()
                Text("\(state.points.count) points")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if state.points.count >= 2 {
                Chart(state.points) { point in
                    LineMark(
                        x: .value("Date", point.date),
                        y: .value(state.title, point.value)
                    )
                    PointMark(
                        x: .value("Date", point.date),
                        y: .value(state.title, point.value)
                    )
                }
                .frame(height: 180)
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 4))
                }
                .chartYAxis {
                    AxisMarks(position: .leading)
                }
                .accessibilityLabel(state.accessibilitySummary)
            } else {
                PlaceholderStateView(
                    title: state.points.isEmpty ? "No Trend Yet" : "One Eligible Session",
                    message: state.summaryText,
                    systemImage: "chart.line.uptrend.xyaxis"
                )
                .frame(minHeight: 160)
            }

            Text(state.summaryText)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(valueUnit)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct PersonalRecordsSection: View {
    let records: [PersonalRecordCardState]
    let historyRows: [HistorySessionRowState]
    let sessionRepository: any SessionRepository
    let poseAssetStore: any PoseAssetStoring
    let refreshAfterDetail: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Personal Records")
                .font(.headline)

            if records.isEmpty {
                Text("Eligible records will appear as you build training history.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(.thinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                ForEach(records) { record in
                    if let sourceRow = historyRows.first(where: { $0.id == record.sourceSessionID }) {
                        NavigationLink {
                            ProgressSessionResultsDestination(
                                analysis: sourceRow.analysis,
                                sessionRepository: sessionRepository,
                                poseAssetStore: poseAssetStore,
                                refreshAfterDetail: refreshAfterDetail
                            )
                        } label: {
                            PersonalRecordCard(record: record)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Open source session for \(record.title)")
                    } else {
                        PersonalRecordCard(record: record)
                    }
                }
            }
        }
    }
}

private struct PersonalRecordCard: View {
    let record: PersonalRecordCardState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(record.title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Spacer()
                Text(record.valueText)
                    .font(.headline)
            }
            Text(record.achievedText)
                .foregroundStyle(.secondary)
            Text(record.sourceText)
                .foregroundStyle(.secondary)
            if let deltaText = record.deltaText {
                Text(deltaText)
                    .foregroundStyle(.secondary)
            }
        }
        .font(.subheadline)
        .padding(12)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .combine)
    }
}

private struct PersonalBaselinesSection: View {
    let baselines: [PersonalBaselineCardState]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Personal Baseline")
                .font(.headline)

            ForEach(baselines) { baseline in
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(baseline.title)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        Spacer()
                        Text(baseline.valueText)
                            .font(.headline)
                    }
                    Text(baseline.dispersionText)
                        .foregroundStyle(.secondary)
                    Text(baseline.sampleCountText)
                        .foregroundStyle(.secondary)
                    Text(baseline.availabilityText)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)
                }
                .font(.subheadline)
                .padding(12)
                .background(.thinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .accessibilityElement(children: .combine)
            }
        }
    }
}

private struct HistorySection: View {
    let rows: [HistorySessionRowState]
    let sessionRepository: any SessionRepository
    let poseAssetStore: any PoseAssetStoring
    let requestDelete: (HistorySessionRowState) -> Void
    let refreshAfterDetail: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("History")
                .font(.headline)

            if rows.isEmpty {
                PlaceholderStateView(
                    title: "No Saved Sessions",
                    message: "Complete a dry fire session to begin building History, trends, records, and baselines.",
                    systemImage: "clock.arrow.circlepath"
                )
                .frame(minHeight: 180)
            } else {
                ForEach(rows) { row in
                    HStack(spacing: 10) {
                        NavigationLink {
                            ProgressSessionResultsDestination(
                                analysis: row.analysis,
                                sessionRepository: sessionRepository,
                                poseAssetStore: poseAssetStore,
                                refreshAfterDetail: refreshAfterDetail
                            )
                        } label: {
                            HistorySessionRow(state: row)
                        }
                        .buttonStyle(.plain)

                        Button(role: .destructive) {
                            requestDelete(row)
                        } label: {
                            Image(systemName: "trash")
                                .frame(width: 36, height: 36)
                        }
                        .buttonStyle(.bordered)
                        .accessibilityLabel("Delete \(row.dateText) session")
                    }
                }
            }
        }
    }
}

private struct ProgressSessionResultsDestination: View {
    @Environment(\.dismiss) private var dismiss

    let analysis: SessionAnalysis
    let sessionRepository: any SessionRepository
    let poseAssetStore: any PoseAssetStoring
    let refreshAfterDetail: () -> Void

    var body: some View {
        SessionResultsView(
            analysis: analysis,
            sessionRepository: sessionRepository,
            poseAssetStore: poseAssetStore
        ) {
            refreshAfterDetail()
            dismiss()
        }
    }
}

private struct HistorySessionRow: View {
    let state: HistorySessionRowState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(state.dateText)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .lineLimit(2)
                Spacer()
                Text(state.modeText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Text(state.repCountText)
                Text(state.averageDurationText)
                Text(state.consistencyText)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(2)

            if let videoText = state.videoText {
                Text(videoText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .combine)
    }
}
