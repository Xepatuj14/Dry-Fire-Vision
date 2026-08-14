import Foundation

public enum SessionResultsDisplayState: Equatable, Sendable {
    case full
    case degraded
    case noValidReps
}

public struct SessionResultsViewState: Equatable, Sendable {
    public let displayState: SessionResultsDisplayState
    public let title: String
    public let sessionContextText: String
    public let repCountText: String
    public let targetRepText: String?
    public let averageDurationText: String
    public let movementConsistencyText: String
    public let confidenceText: String
    public let representativeRep: HighlightRepState?
    public let fastestRep: HighlightRepState?
    public let outlierRows: [SessionResultsRepRowState]
    public let repRows: [SessionResultsRepRowState]
    public let message: String?
}

public struct HighlightRepState: Equatable, Sendable {
    public let id: UUID
    public let title: String
    public let repNumberText: String
    public let durationText: String
    public let detailText: String
}

public struct SessionResultsRepRowState: Equatable, Identifiable, Sendable {
    public let id: UUID
    public let repNumberText: String
    public let durationText: String
    public let validityText: String
    public let headMetricText: String
    public let wristMetricText: String
    public let badges: [String]
}

public struct SessionResultsViewModel: Equatable, Sendable {
    public let analysis: SessionAnalysis
    public let state: SessionResultsViewState

    public init(analysis: SessionAnalysis) {
        self.analysis = analysis
        self.state = Self.makeState(from: analysis)
    }

    private static func makeState(from analysis: SessionAnalysis) -> SessionResultsViewState {
        let rows = analysis.analyzedReps.map { rep in
            rowState(for: rep, analysis: analysis)
        }
        let rowByID = Dictionary(uniqueKeysWithValues: rows.map { ($0.id, $0) })
        let representative = analysis.representativeRepID.flatMap { id in
            analysis.analyzedReps.first { $0.id == id }.map {
                highlight(title: "Representative Rep", rep: $0)
            }
        }
        let fastest = analysis.fastestRepID.flatMap { id in
            analysis.analyzedReps.first { $0.id == id }.map {
                highlight(title: "Fastest Rep", rep: $0)
            }
        }
        let displayState: SessionResultsDisplayState = analysis.status == .noValidReps ? .noValidReps : (analysis.status == .completed ? .full : .degraded)
        let targetText = analysis.validRepCount == analysis.targetRepCount ? nil : "Target: \(analysis.targetRepCount) reps"

        return SessionResultsViewState(
            displayState: displayState,
            title: "Dry Fire Session Results",
            sessionContextText: sessionContextText(analysis),
            repCountText: "\(analysis.validRepCount) valid reps analyzed",
            targetRepText: targetText,
            averageDurationText: analysis.averageValidRepDurationSeconds.map(formatSeconds) ?? "Unavailable",
            movementConsistencyText: movementConsistencyText(analysis.movementConsistency),
            confidenceText: confidenceText(analysis.overallConfidence),
            representativeRep: representative,
            fastestRep: fastest,
            outlierRows: analysis.movementOutlierRepIDs.compactMap { rowByID[$0] },
            repRows: rows,
            message: message(for: analysis)
        )
    }

    private static func rowState(for rep: AnalyzedRep, analysis: SessionAnalysis) -> SessionResultsRepRowState {
        var badges: [String] = []
        if analysis.representativeRepID == rep.id {
            badges.append("Representative")
        }
        if analysis.fastestRepID == rep.id {
            badges.append("Fastest")
        }
        if analysis.movementOutlierRepIDs.contains(rep.id) {
            badges.append("Outlier")
        }
        return SessionResultsRepRowState(
            id: rep.id,
            repNumberText: "Rep \(rep.sequenceIndex + 1)",
            durationText: metricText(rep.metrics.duration, formatter: formatSeconds),
            validityText: validityText(rep.segment.validity),
            headMetricText: metricText(rep.metrics.headDisplacement, formatter: formatNormalized),
            wristMetricText: metricText(rep.metrics.primaryWristPathLength, formatter: formatNormalized),
            badges: badges
        )
    }

    private static func highlight(title: String, rep: AnalyzedRep) -> HighlightRepState {
        HighlightRepState(
            id: rep.id,
            title: title,
            repNumberText: "Rep \(rep.sequenceIndex + 1)",
            durationText: metricText(rep.metrics.duration, formatter: formatSeconds),
            detailText: "Head \(metricText(rep.metrics.headDisplacement, formatter: formatNormalized)) | Wrist \(metricText(rep.metrics.primaryWristPathLength, formatter: formatNormalized))"
        )
    }

    private static func metricText(
        _ result: MovementMetricResult,
        formatter: (Double) -> String
    ) -> String {
        guard result.availability == .available, let value = result.value else {
            return result.reason == .lowJointConfidence ? "Insufficient confidence" : "Unavailable"
        }
        return formatter(value)
    }

    private static func movementConsistencyText(_ consistency: SessionConsistencyResult) -> String {
        consistency.availability == .available ? "Available" : "Insufficient Data"
    }

    private static func validityText(_ validity: RepValidity) -> String {
        switch validity {
        case .valid:
            return "Valid"
        case .degraded:
            return "Degraded"
        case .invalid:
            return "Invalid"
        }
    }

    private static func confidenceText(_ confidence: ConfidenceStatus) -> String {
        switch confidence {
        case .high:
            return "High confidence"
        case .medium:
            return "Partial confidence"
        case .low:
            return "Low confidence"
        }
    }

    private static func sessionContextText(_ analysis: SessionAnalysis) -> String {
        guard let start = analysis.recordingStartTimestampSeconds,
              let end = analysis.recordingEndTimestampSeconds else {
            return "Unsaved analysis"
        }
        return "Captured \(formatSeconds(max(0, end - start)))"
    }

    private static func message(for analysis: SessionAnalysis) -> String? {
        switch analysis.status {
        case .completed:
            return nil
        case .degraded:
            return "Some repetitions or comparisons were unavailable, but the usable results are preserved."
        case .noValidReps:
            return "No valid repetitions were analyzed. Future review/retry controls will use this state without fabricating summary metrics."
        case .failed:
            return "Analysis failed."
        }
    }

    private static func formatSeconds(_ value: Double) -> String {
        String(format: "%.2f s", value)
    }

    private static func formatNormalized(_ value: Double) -> String {
        String(format: "%.3f normalized", value)
    }
}
