import Foundation

public protocol ProgressRepository: Sendable {
    func overview() async throws -> ProgressOverviewSnapshot
    func metricSeries(_ key: HistoricalMetricKey) async throws -> [HistoricalMetricPoint]
    func personalRecords() async throws -> [PersonalRecordSnapshot]
    func personalBaselines() async throws -> [PersonalBaselineSnapshot]
    func invalidateDerivedCachesAfterSessionChange() async
}

public struct SessionProgressRepository: ProgressRepository {
    public static let baselineMinimumSampleCount = 3

    private let sessionRepository: any SessionRepository
    private let compatibleAnalysisVersion: String
    private let now: @Sendable () -> Date

    public init(
        sessionRepository: any SessionRepository,
        compatibleAnalysisVersion: String = VersionCatalog.current.analysisVersion,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.sessionRepository = sessionRepository
        self.compatibleAnalysisVersion = compatibleAnalysisVersion
        self.now = now
    }

    public func overview() async throws -> ProgressOverviewSnapshot {
        let sessions = try await eligibleSessions()
        let duration = durationTrend(from: sessions)
        let consistency = consistencyTrend(from: sessions)
        let records = fastestRepRecords(from: sessions)
        let baselines = [
            baseline(for: .averageMovementDuration, points: duration),
            baseline(for: .movementConsistency, points: consistency)
        ]
        return ProgressOverviewSnapshot(
            durationTrend: duration,
            consistencyTrend: consistency,
            personalRecords: records,
            baselines: baselines,
            compatibleAnalysisVersion: compatibleAnalysisVersion,
            generatedAt: now()
        )
    }

    public func metricSeries(_ key: HistoricalMetricKey) async throws -> [HistoricalMetricPoint] {
        let sessions = try await eligibleSessions()
        switch key {
        case .averageMovementDuration:
            return durationTrend(from: sessions)
        case .movementConsistency:
            return consistencyTrend(from: sessions)
        case .fastestRepDuration:
            return fastestRepPoints(from: sessions)
        }
    }

    public func personalRecords() async throws -> [PersonalRecordSnapshot] {
        fastestRepRecords(from: try await eligibleSessions())
    }

    public func personalBaselines() async throws -> [PersonalBaselineSnapshot] {
        let sessions = try await eligibleSessions()
        return [
            baseline(for: .averageMovementDuration, points: durationTrend(from: sessions)),
            baseline(for: .movementConsistency, points: consistencyTrend(from: sessions))
        ]
    }

    public func invalidateDerivedCachesAfterSessionChange() async {
        // Slice 13 derives records and baselines on demand, so invalidation is intentionally a no-op.
    }

    private func eligibleSessions() async throws -> [TrainingSessionSnapshot] {
        let snapshots = try await sessionRepository.recentCompletedSessions(limit: Int.max)
        return snapshots
            .filter { snapshot in
                snapshot.mode == .dryFire &&
                    snapshot.analysisVersion == compatibleAnalysisVersion &&
                    (snapshot.status == .completed || snapshot.status == .degraded) &&
                    snapshot.analysis != nil
            }
            .sorted { $0.createdAt < $1.createdAt }
    }

    private func durationTrend(from sessions: [TrainingSessionSnapshot]) -> [HistoricalMetricPoint] {
        sessions.compactMap { snapshot in
            guard let analysis = snapshot.analysis,
                  let value = analysis.averageValidRepDurationSeconds,
                  value.isFinite,
                  analysis.overallConfidence != .low else {
                return nil
            }
            return HistoricalMetricPoint(
                id: deterministicID(snapshot.id, .averageMovementDuration, nil),
                sourceSessionID: snapshot.id,
                date: snapshot.createdAt,
                metricKey: .averageMovementDuration,
                value: value,
                analysisVersion: snapshot.analysisVersion,
                confidence: analysis.overallConfidence
            )
        }
    }

    private func consistencyTrend(from sessions: [TrainingSessionSnapshot]) -> [HistoricalMetricPoint] {
        sessions.compactMap { snapshot in
            guard let analysis = snapshot.analysis,
                  analysis.movementConsistency.availability == .available,
                  let value = analysis.movementConsistency.internalValue,
                  value.isFinite,
                  analysis.movementConsistency.confidence != .low else {
                return nil
            }
            return HistoricalMetricPoint(
                id: deterministicID(snapshot.id, .movementConsistency, nil),
                sourceSessionID: snapshot.id,
                date: snapshot.createdAt,
                metricKey: .movementConsistency,
                value: value,
                analysisVersion: snapshot.analysisVersion,
                confidence: analysis.movementConsistency.confidence
            )
        }
    }

    private func fastestRepPoints(from sessions: [TrainingSessionSnapshot]) -> [HistoricalMetricPoint] {
        sessions.flatMap { snapshot -> [HistoricalMetricPoint] in
            guard let analysis = snapshot.analysis else {
                return []
            }
            return analysis.analyzedReps.compactMap { rep in
                guard rep.segment.validity == .valid,
                      rep.metrics.duration.availability == .available,
                      rep.metrics.duration.confidence == .high,
                      let value = rep.metrics.duration.value,
                      value.isFinite,
                      rep.metrics.analysisVersion == compatibleAnalysisVersion else {
                    return nil
                }
                return HistoricalMetricPoint(
                    id: deterministicID(snapshot.id, .fastestRepDuration, rep.id),
                    sourceSessionID: snapshot.id,
                    sourceRepID: rep.id,
                    date: snapshot.createdAt,
                    metricKey: .fastestRepDuration,
                    value: value,
                    analysisVersion: rep.metrics.analysisVersion,
                    confidence: rep.metrics.duration.confidence
                )
            }
        }
        .sorted { lhs, rhs in
            if lhs.date == rhs.date {
                return lhs.value < rhs.value
            }
            return lhs.date < rhs.date
        }
    }

    private func fastestRepRecords(from sessions: [TrainingSessionSnapshot]) -> [PersonalRecordSnapshot] {
        let candidates = fastestRepPoints(from: sessions).sorted { lhs, rhs in
            if lhs.value == rhs.value {
                return lhs.date < rhs.date
            }
            return lhs.value < rhs.value
        }
        guard let record = candidates.first else {
            return []
        }
        let previous = candidates.dropFirst().first?.value
        return [
            PersonalRecordSnapshot(
                id: deterministicID(record.sourceSessionID, .fastestRepDuration, record.sourceRepID),
                metricKey: .fastestRepDuration,
                mode: .dryFire,
                value: record.value,
                achievedDate: record.date,
                sourceSessionID: record.sourceSessionID,
                sourceRepID: record.sourceRepID,
                analysisVersion: record.analysisVersion,
                confidence: record.confidence,
                previousValue: previous
            )
        ]
    }

    private func baseline(for key: HistoricalMetricKey, points: [HistoricalMetricPoint]) -> PersonalBaselineSnapshot {
        let values = points.map(\.value).filter(\.isFinite)
        let medianValue = median(values)
        let actualDispersion: Double?
        if let medianValue {
            actualDispersion = median(values.map { abs($0 - medianValue) })
        } else {
            actualDispersion = nil
        }
        return PersonalBaselineSnapshot(
            id: deterministicID(UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 13, 1)), key, nil),
            metricKey: key,
            mode: .dryFire,
            analysisVersion: compatibleAnalysisVersion,
            sampleCount: values.count,
            medianValue: values.count >= Self.baselineMinimumSampleCount ? medianValue : nil,
            robustDispersion: values.count >= Self.baselineMinimumSampleCount ? actualDispersion : nil,
            lastRebuiltAt: now(),
            availability: values.count >= Self.baselineMinimumSampleCount ? .available : .insufficientHistory
        )
    }

    private func median(_ values: [Double]) -> Double? {
        let sorted = values.filter(\.isFinite).sorted()
        guard !sorted.isEmpty else {
            return nil
        }
        let middle = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return (sorted[middle - 1] + sorted[middle]) / 2
        }
        return sorted[middle]
    }

    private func deterministicID(_ sessionID: UUID, _ key: HistoricalMetricKey, _ repID: UUID?) -> UUID {
        let seedText = [sessionID.uuidString, key.rawValue, repID?.uuidString ?? "session"].joined(separator: "|")
        let seed = seedText.unicodeScalars.reduce(UInt64(14_695_981_039_346_656_037)) { partial, scalar in
            (partial ^ UInt64(scalar.value)) &* 1_099_511_628_211
        }
        return UUID(uuid: (
            UInt8((seed >> 56) & 0xff),
            UInt8((seed >> 48) & 0xff),
            UInt8((seed >> 40) & 0xff),
            UInt8((seed >> 32) & 0xff),
            UInt8((seed >> 24) & 0xff),
            UInt8((seed >> 16) & 0xff),
            UInt8((seed >> 8) & 0xff),
            UInt8(seed & 0xff),
            0, 0, 0, 0, 0, 0, 0, 13
        ))
    }
}

public struct UnimplementedProgressRepository: ProgressRepository {
    public init() {}

    public func overview() async throws -> ProgressOverviewSnapshot {
        throw ServiceBoundaryError.notImplemented
    }

    public func metricSeries(_ key: HistoricalMetricKey) async throws -> [HistoricalMetricPoint] {
        throw ServiceBoundaryError.notImplemented
    }

    public func personalRecords() async throws -> [PersonalRecordSnapshot] {
        throw ServiceBoundaryError.notImplemented
    }

    public func personalBaselines() async throws -> [PersonalBaselineSnapshot] {
        throw ServiceBoundaryError.notImplemented
    }

    public func invalidateDerivedCachesAfterSessionChange() async {}
}
