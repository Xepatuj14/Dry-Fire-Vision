import Combine
import Foundation

public enum ProgressRootState: Equatable, Sendable {
    case loading
    case empty(ProgressViewSnapshot)
    case populated(ProgressViewSnapshot)
    case deleting(ProgressViewSnapshot, sessionID: UUID)
    case failed(String)
}

public struct ProgressViewSnapshot: Equatable, Sendable {
    public let historyRows: [HistorySessionRowState]
    public let durationTrend: TrendSectionState
    public let consistencyTrend: TrendSectionState
    public let personalRecords: [PersonalRecordCardState]
    public let baselines: [PersonalBaselineCardState]
    public let generatedSummary: String
}

public struct HistorySessionRowState: Equatable, Identifiable, Sendable {
    public let id: UUID
    public let dateText: String
    public let modeText: String
    public let repCountText: String
    public let averageDurationText: String
    public let consistencyText: String
    public let videoText: String?
    public let analysis: SessionAnalysis
}

public struct TrendSectionState: Equatable, Sendable {
    public let title: String
    public let points: [HistoricalMetricPoint]
    public let summaryText: String
    public let accessibilitySummary: String
}

public struct PersonalRecordCardState: Equatable, Identifiable, Sendable {
    public let id: UUID
    public let title: String
    public let valueText: String
    public let achievedText: String
    public let sourceText: String
    public let deltaText: String?
    public let sourceSessionID: UUID
    public let sourceRepID: UUID?
}

public struct PersonalBaselineCardState: Equatable, Identifiable, Sendable {
    public let id: UUID
    public let title: String
    public let valueText: String
    public let dispersionText: String
    public let sampleCountText: String
    public let availabilityText: String
}

@MainActor
public final class ProgressViewModel: ObservableObject {
    @Published public private(set) var state: ProgressRootState = .loading
    @Published public private(set) var pendingDeletion: HistorySessionRowState?

    private let sessionRepository: any SessionRepository
    private let progressRepository: any ProgressRepository
    private var loadTask: Task<Void, Never>?

    public init(sessionRepository: any SessionRepository, progressRepository: any ProgressRepository) {
        self.sessionRepository = sessionRepository
        self.progressRepository = progressRepository
    }

    deinit {
        loadTask?.cancel()
    }

    public func load() {
        loadTask?.cancel()
        state = .loading
        loadTask = Task { [weak self] in
            guard let self else {
                return
            }
            await self.loadData()
        }
    }

    public func requestDelete(_ row: HistorySessionRowState) {
        pendingDeletion = row
    }

    public func cancelDelete() {
        pendingDeletion = nil
    }

    public func confirmDeletePendingSession() {
        guard let row = pendingDeletion else {
            return
        }
        pendingDeletion = nil
        let snapshot = currentSnapshot
        if let snapshot {
            state = .deleting(snapshot, sessionID: row.id)
        }
        loadTask?.cancel()
        loadTask = Task { [weak self] in
            guard let self else {
                return
            }
            do {
                try await sessionRepository.deleteSession(id: row.id)
                await progressRepository.invalidateDerivedCachesAfterSessionChange()
                await loadData()
            } catch {
                state = .failed("Dry Fire Vision could not delete this saved session.")
            }
        }
    }

    public func refreshAfterReturningFromDetail() {
        load()
    }

    private var currentSnapshot: ProgressViewSnapshot? {
        switch state {
        case .empty(let snapshot), .populated(let snapshot), .deleting(let snapshot, _):
            return snapshot
        case .loading, .failed:
            return nil
        }
    }

    private func loadData() async {
        do {
            let history = try await sessionRepository.recentCompletedSessions(limit: Int.max)
            let overview = try await progressRepository.overview()
            let snapshot = makeSnapshot(history: history, overview: overview)
            state = snapshot.historyRows.isEmpty ? .empty(snapshot) : .populated(snapshot)
        } catch {
            state = .failed("Progress and History could not load right now.")
        }
    }

    private func makeSnapshot(history: [TrainingSessionSnapshot], overview: ProgressOverviewSnapshot) -> ProgressViewSnapshot {
        ProgressViewSnapshot(
            historyRows: history.compactMap(historyRow),
            durationTrend: trendState(title: "Movement Duration", points: overview.durationTrend, formatter: formatSeconds),
            consistencyTrend: trendState(title: "Movement Consistency", points: overview.consistencyTrend, formatter: formatConsistency),
            personalRecords: overview.personalRecords.map(recordState),
            baselines: overview.baselines.map(baselineState),
            generatedSummary: "Compatible analysis version \(overview.compatibleAnalysisVersion)"
        )
    }

    private func historyRow(_ snapshot: TrainingSessionSnapshot) -> HistorySessionRowState? {
        guard let analysis = snapshot.analysis else {
            return nil
        }
        return HistorySessionRowState(
            id: snapshot.id,
            dateText: Self.dateFormatter.string(from: snapshot.createdAt),
            modeText: snapshot.mode == .dryFire ? "Dry Fire" : "Live Fire Beta",
            repCountText: "\(analysis.validRepCount) valid reps",
            averageDurationText: analysis.averageValidRepDurationSeconds.map(formatSeconds) ?? "Unavailable",
            consistencyText: consistencyText(analysis.movementConsistency),
            videoText: videoText(snapshot.videoRetentionState),
            analysis: analysis
        )
    }

    private func trendState(
        title: String,
        points: [HistoricalMetricPoint],
        formatter: (Double) -> String
    ) -> TrendSectionState {
        let summary: String
        if points.isEmpty {
            summary = "No eligible sessions yet."
        } else if points.count == 1 {
            summary = "Complete more sessions to start seeing a trend."
        } else {
            summary = "\(points.count) eligible sessions from \(Self.shortDateFormatter.string(from: points.first?.date ?? Date())) to \(Self.shortDateFormatter.string(from: points.last?.date ?? Date()))."
        }
        let accessibility: String
        if let first = points.first, let last = points.last {
            accessibility = "\(title), \(points.count) eligible sessions, first value \(formatter(first.value)), most recent value \(formatter(last.value))."
        } else {
            accessibility = "\(title), no eligible sessions."
        }
        return TrendSectionState(
            title: title,
            points: points,
            summaryText: summary,
            accessibilitySummary: accessibility
        )
    }

    private func recordState(_ record: PersonalRecordSnapshot) -> PersonalRecordCardState {
        PersonalRecordCardState(
            id: record.id,
            title: record.metricKey.title,
            valueText: formatSeconds(record.value),
            achievedText: "Achieved \(Self.dateFormatter.string(from: record.achievedDate))",
            sourceText: record.sourceRepID == nil ? "Source session saved locally" : "Source \(record.metricKey == .fastestRepDuration ? "rep" : "session") saved locally",
            deltaText: record.previousValue.map { "Previous eligible record: \(formatSeconds($0))" },
            sourceSessionID: record.sourceSessionID,
            sourceRepID: record.sourceRepID
        )
    }

    private func baselineState(_ baseline: PersonalBaselineSnapshot) -> PersonalBaselineCardState {
        PersonalBaselineCardState(
            id: baseline.id,
            title: baseline.metricKey.title,
            valueText: baseline.medianValue.map { baseline.metricKey == .movementConsistency ? formatConsistency($0) : formatSeconds($0) } ?? "Unavailable",
            dispersionText: baseline.robustDispersion.map { "MAD \(baseline.metricKey == .movementConsistency ? formatConsistency($0) : formatSeconds($0))" } ?? "MAD unavailable",
            sampleCountText: "\(baseline.sampleCount) eligible sessions",
            availabilityText: baseline.availability == .available ? "Personal Baseline" : "Insufficient history"
        )
    }

    private func consistencyText(_ consistency: SessionConsistencyResult) -> String {
        guard consistency.availability == .available, consistency.internalValue != nil else {
            return "Consistency unavailable"
        }
        return "Consistency available"
    }

    private func videoText(_ state: VideoRetentionState) -> String? {
        switch state {
        case .notRecorded:
            return "Video not recorded"
        case .deleted:
            return "Video deleted"
        case .keep:
            return "Video retained"
        case .pendingDelete:
            return "Video pending delete"
        case .deletionFailed:
            return "Video cleanup failed"
        }
    }

    private func formatSeconds(_ value: Double) -> String {
        String(format: "%.2f s", value)
    }

    private func formatConsistency(_ value: Double) -> String {
        String(format: "%.3f internal", value)
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    private static let shortDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .none
        return formatter
    }()
}
