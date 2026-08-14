import DryFireVisionCore
import XCTest

final class ProgressRepositoryTests: XCTestCase {
    func testOverviewBuildsChronologicalTrendsRecordsAndAvailableBaselines() async throws {
        let snapshots = [
            makeSnapshot(day: 3, averageDuration: 1.4, fastestDuration: 0.9, consistency: 0.8),
            makeSnapshot(day: 1, averageDuration: 1.2, fastestDuration: 0.8, consistency: 0.7),
            makeSnapshot(day: 2, averageDuration: 1.0, fastestDuration: 0.7, consistency: 0.9)
        ]
        let repository = SessionProgressRepository(
            sessionRepository: FakeProgressSessionRepository(snapshots),
            now: { Date(timeIntervalSince1970: 13) }
        )

        let overview = try await repository.overview()

        XCTAssertEqual(overview.durationTrend.map(\.value), [1.2, 1.0, 1.4])
        XCTAssertEqual(overview.consistencyTrend.map(\.value), [0.7, 0.9, 0.8])
        XCTAssertEqual(overview.personalRecords.first?.value, 0.7)
        XCTAssertEqual(overview.personalRecords.first?.previousValue, 0.8)
        let durationBaseline = try XCTUnwrap(overview.baselines.first { $0.metricKey == .averageMovementDuration })
        let consistencyBaseline = try XCTUnwrap(overview.baselines.first { $0.metricKey == .movementConsistency })
        XCTAssertEqual(durationBaseline.availability, .available)
        XCTAssertEqual(try XCTUnwrap(durationBaseline.medianValue), 1.2)
        XCTAssertEqual(try XCTUnwrap(durationBaseline.robustDispersion), 0.2, accuracy: 0.000_001)
        XCTAssertEqual(try XCTUnwrap(consistencyBaseline.medianValue), 0.8)
        XCTAssertEqual(try XCTUnwrap(consistencyBaseline.robustDispersion), 0.1, accuracy: 0.000_001)
    }

    func testInsufficientHistoryProducesNoBaselineValues() async throws {
        let repository = SessionProgressRepository(
            sessionRepository: FakeProgressSessionRepository([
                makeSnapshot(day: 1, averageDuration: 1.0, fastestDuration: 0.7, consistency: 0.7),
                makeSnapshot(day: 2, averageDuration: 1.2, fastestDuration: 0.8, consistency: 0.8)
            ])
        )

        let baselines = try await repository.personalBaselines()

        XCTAssertTrue(baselines.allSatisfy { $0.availability == .insufficientHistory })
        XCTAssertTrue(baselines.allSatisfy { $0.medianValue == nil })
        XCTAssertTrue(baselines.allSatisfy { $0.robustDispersion == nil })
    }

    func testEligibilityExcludesIncompatibleLiveFireLowConfidenceInvalidAndNonFiniteInputs() async throws {
        let good = makeSnapshot(day: 1, averageDuration: 1.0, fastestDuration: 0.70, consistency: 0.70)
        let liveFire = makeSnapshot(day: 2, averageDuration: 0.5, fastestDuration: 0.30, consistency: 0.60, mode: .liveFireBeta)
        let incompatible = makeSnapshot(day: 3, averageDuration: 0.4, fastestDuration: 0.20, consistency: 0.50, analysisVersion: "legacy")
        let lowDurationConfidence = makeSnapshot(day: 4, averageDuration: 0.3, fastestDuration: 0.10, consistency: 0.40, durationConfidence: .low, overallConfidence: .low)
        let invalidRep = makeSnapshot(day: 5, averageDuration: 0.2, fastestDuration: 0.05, consistency: 0.30, repValidity: .invalid)
        let lowOverallConfidence = makeSnapshot(day: 6, averageDuration: 0.1, fastestDuration: 0.04, consistency: 0.20, durationConfidence: .low, overallConfidence: .low)
        let unavailableConsistency = makeSnapshot(day: 7, averageDuration: Double.nan, fastestDuration: 0.90, consistency: nil)
        let repository = SessionProgressRepository(
            sessionRepository: FakeProgressSessionRepository([
                good,
                liveFire,
                incompatible,
                lowDurationConfidence,
                invalidRep,
                lowOverallConfidence,
                unavailableConsistency
            ])
        )

        let overview = try await repository.overview()

        XCTAssertEqual(overview.durationTrend.map(\.sourceSessionID), [good.id])
        XCTAssertEqual(overview.consistencyTrend.map(\.sourceSessionID), [good.id])
        XCTAssertEqual(overview.personalRecords.map(\.sourceSessionID), [good.id])
        XCTAssertFalse(overview.durationTrend.contains { !$0.value.isFinite })
    }

    func testDeletingRecordHolderPromotesNextEligibleRecordAndRefreshesTrends() async throws {
        let old = makeSnapshot(day: 1, averageDuration: 1.2, fastestDuration: 0.8, consistency: 0.7)
        let holder = makeSnapshot(day: 2, averageDuration: 1.0, fastestDuration: 0.6, consistency: 0.8)
        let backing = FakeProgressSessionRepository([old, holder])
        let repository = SessionProgressRepository(sessionRepository: backing)

        XCTAssertEqual(try await repository.personalRecords().first?.sourceSessionID, holder.id)

        try await backing.deleteSession(id: holder.id)
        await repository.invalidateDerivedCachesAfterSessionChange()

        let overview = try await repository.overview()
        XCTAssertEqual(overview.durationTrend.map(\.sourceSessionID), [old.id])
        XCTAssertEqual(overview.personalRecords.first?.sourceSessionID, old.id)
        XCTAssertNil(overview.personalRecords.first?.previousValue)
    }

    func testDerivedIDsAreDeterministicAcrossRebuilds() async throws {
        let backing = FakeProgressSessionRepository([
            makeSnapshot(day: 1, averageDuration: 1.2, fastestDuration: 0.8, consistency: 0.7),
            makeSnapshot(day: 2, averageDuration: 1.0, fastestDuration: 0.6, consistency: 0.8),
            makeSnapshot(day: 3, averageDuration: 1.4, fastestDuration: 0.9, consistency: 0.9)
        ])
        let repository = SessionProgressRepository(sessionRepository: backing)

        let first = try await repository.overview()
        let second = try await repository.overview()

        XCTAssertEqual(first.durationTrend.map(\.id), second.durationTrend.map(\.id))
        XCTAssertEqual(first.consistencyTrend.map(\.id), second.consistencyTrend.map(\.id))
        XCTAssertEqual(first.personalRecords.map(\.id), second.personalRecords.map(\.id))
        XCTAssertEqual(first.baselines.map(\.id), second.baselines.map(\.id))
    }

    func testLargeHistoryPerformanceHarnessCovers100500And1000Sessions() async throws {
        for size in [100, 500, 1_000] {
            let snapshots = (0..<size).map { index in
                makeSnapshot(
                    day: index,
                    averageDuration: 1.0 + Double(index % 7) * 0.01,
                    fastestDuration: 0.7 + Double(index % 11) * 0.01,
                    consistency: 0.6 + Double(index % 5) * 0.02
                )
            }
            let repository = SessionProgressRepository(sessionRepository: FakeProgressSessionRepository(snapshots))

            let start = Date()
            let overview = try await repository.overview()
            let elapsed = Date().timeIntervalSince(start)

            XCTAssertEqual(overview.durationTrend.count, size)
            XCTAssertEqual(overview.consistencyTrend.count, size)
            XCTAssertEqual(try await repository.metricSeries(.fastestRepDuration).count, size)
            XCTAssertLessThan(elapsed, 5.0)
        }
    }

    private func makeSnapshot(
        day: Int,
        averageDuration: Double,
        fastestDuration: Double,
        consistency: Double?,
        mode: SessionMode = .dryFire,
        analysisVersion: String = VersionCatalog.current.analysisVersion,
        durationConfidence: ConfidenceStatus = .high,
        overallConfidence: ConfidenceStatus = .high,
        repValidity: RepValidity = .valid
    ) -> TrainingSessionSnapshot {
        let id = UUID(uuid: (
            UInt8((day >> 24) & 0xff),
            UInt8((day >> 16) & 0xff),
            UInt8((day >> 8) & 0xff),
            UInt8(day & 0xff),
            0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 13, 13
        ))
        let date = Date(timeIntervalSince1970: Double(day) * 86_400)
        let rep = makeRep(sessionID: id, duration: fastestDuration, confidence: durationConfidence, validity: repValidity)
        let analysis = SessionAnalysis(
            sessionID: id,
            recordingID: id,
            mode: mode,
            recordingStartTimestampSeconds: date.timeIntervalSince1970,
            recordingEndTimestampSeconds: date.timeIntervalSince1970 + averageDuration,
            analysisVersion: analysisVersion,
            analysisConfigurationVersion: VersionCatalog.current.analysisConfigurationVersion,
            targetRepCount: 1,
            actualSegmentedRepCount: 1,
            validRepCount: repValidity == .valid ? 1 : 0,
            degradedRepCount: repValidity == .degraded ? 1 : 0,
            invalidRepCount: repValidity == .invalid ? 1 : 0,
            averageValidRepDurationSeconds: averageDuration,
            analyzedReps: [rep],
            fastestRepID: rep.id,
            movementConsistency: consistency.map {
                SessionConsistencyResult(
                    availability: .available,
                    internalValue: $0,
                    confidence: overallConfidence,
                    reason: .none
                )
            } ?? .unavailable(reason: .insufficientEligibleReps),
            overallConfidence: overallConfidence,
            status: .completed
        )
        return TrainingSessionSnapshot(
            id: id,
            mode: mode,
            status: analysis.status,
            createdAt: date,
            analysisVersion: analysisVersion,
            analysisConfigurationVersion: analysis.analysisConfigurationVersion,
            analysis: analysis,
            poseAssetAvailability: .available
        )
    }

    private func makeRep(
        sessionID: UUID,
        duration: Double,
        confidence: ConfidenceStatus,
        validity: RepValidity
    ) -> AnalyzedRep {
        let repID = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 13, 99))
        let metricSet = MovementMetricSet(
            duration: .available(
                key: .totalRepDuration,
                value: duration,
                confidence: confidence,
                configurationVersion: VersionCatalog.current.analysisConfigurationVersion
            ),
            headDisplacement: .available(
                key: .headDisplacement,
                value: 0.1,
                confidence: .high,
                configurationVersion: VersionCatalog.current.analysisConfigurationVersion
            ),
            shoulderDisplacement: .available(
                key: .shoulderDisplacement,
                value: 0.1,
                confidence: .high,
                configurationVersion: VersionCatalog.current.analysisConfigurationVersion
            ),
            primaryWristPathLength: .available(
                key: .primaryWristPathLength,
                value: 0.1,
                confidence: .high,
                configurationVersion: VersionCatalog.current.analysisConfigurationVersion
            ),
            wristPathDirectness: .available(
                key: .wristPathDirectness,
                value: 0.1,
                confidence: .high,
                configurationVersion: VersionCatalog.current.analysisConfigurationVersion
            ),
            configurationVersion: VersionCatalog.current.analysisConfigurationVersion
        )
        return AnalyzedRep(
            id: repID,
            sequenceIndex: 0,
            segment: RepSegment(
                id: repID,
                sequenceIndex: 0,
                startTimestampSeconds: 0,
                activeMovementEndTimestampSeconds: duration / 2,
                completeTimestampSeconds: duration,
                validity: validity,
                confidenceStatus: confidence,
                diagnosticReason: .none
            ),
            metrics: metricSet,
            metricDiagnostics: [],
            sourceRecordingID: sessionID
        )
    }
}

private actor FakeProgressSessionRepository: SessionRepository {
    private var snapshotsByID: [UUID: TrainingSessionSnapshot]

    init(_ snapshots: [TrainingSessionSnapshot]) {
        self.snapshotsByID = Dictionary(uniqueKeysWithValues: snapshots.map { ($0.id, $0) })
    }

    func save(_ analysis: SessionAnalysis) async throws -> UUID {
        let snapshot = TrainingSessionSnapshot(
            id: analysis.sessionID,
            mode: analysis.mode,
            status: analysis.status,
            createdAt: Date(timeIntervalSince1970: analysis.recordingStartTimestampSeconds ?? 0),
            analysisVersion: analysis.analysisVersion,
            analysisConfigurationVersion: analysis.analysisConfigurationVersion,
            analysis: analysis,
            poseAssetAvailability: .available
        )
        snapshotsByID[analysis.sessionID] = snapshot
        return analysis.sessionID
    }

    func session(id: UUID) async throws -> TrainingSessionSnapshot {
        guard let snapshot = snapshotsByID[id] else {
            throw PersistenceError.sessionNotFound(id)
        }
        return snapshot
    }

    func poseAssetReference(sessionID: UUID, repID: UUID) async throws -> RepPoseAssetReference? {
        nil
    }

    func recentCompletedSessions(limit: Int) async throws -> [TrainingSessionSnapshot] {
        Array(
            snapshotsByID.values
                .sorted { $0.createdAt > $1.createdAt }
                .prefix(limit)
        )
    }

    func deleteSession(id: UUID) async throws {
        snapshotsByID[id] = nil
    }
}
