import Foundation

public struct SessionComparisonAnalyzer: Sendable {
    public let configuration: AnalysisConfiguration
    public let phaseNormalizer: PhaseNormalizer
    public let similarityEngine: SimilarityEngine

    public init(configuration: AnalysisConfiguration = .provisionalSegmentationV1) {
        self.configuration = configuration
        self.phaseNormalizer = PhaseNormalizer(configuration: configuration)
        self.similarityEngine = SimilarityEngine(configuration: configuration)
    }

    public func analyze(recording: PoseRecording, analyzedReps: [AnalyzedRep]) -> SessionComparisonResult {
        var excluded: [UUID: ComparisonUnavailableReason] = [:]
        let eligible = analyzedReps.filter { rep in
            guard rep.segment.validity == .valid else {
                excluded[rep.id] = .invalidRep
                return false
            }
            guard rep.metrics.analysisVersion == VersionCatalog.current.analysisVersion else {
                excluded[rep.id] = .incompatibleAnalysisVersion
                return false
            }
            guard recording.coordinateVersionsAreCurrent else {
                excluded[rep.id] = .incompatibleCoordinateConvention
                return false
            }
            return true
        }

        let aligned = Dictionary(uniqueKeysWithValues: eligible.compactMap { rep -> (UUID, PhaseAlignedRep)? in
            guard let aligned = phaseNormalizer.align(analyzedRep: rep, recording: recording) else {
                excluded[rep.id] = configuration.primaryWristJointID == nil ? .missingPrimaryWristConfiguration : .invalidNormalizationScale
                return nil
            }
            return (rep.id, aligned)
        })

        let eligibleIDs = eligible.map(\.id).filter { aligned[$0] != nil }
        let pairwise = pairwiseComparisons(eligibleIDs: eligibleIDs, aligned: aligned)
        let sequenceByID = Dictionary(uniqueKeysWithValues: analyzedReps.map { ($0.id, $0.sequenceIndex) })
        let representative = representativeRepID(eligibleIDs: eligibleIDs, pairwise: pairwise, sequenceByID: sequenceByID)
        let fastest = fastestRepID(eligible)
        let toRepresentative = comparisonsToRepresentative(representative, eligibleIDs: eligibleIDs, pairwise: pairwise)
        let consistency = consistencyResult(eligibleIDs: eligibleIDs, representative: representative, comparisons: toRepresentative)
        let outliers = outlierIDs(eligibleIDs: eligibleIDs, representative: representative, comparisons: toRepresentative)
        let medoidDistances = aggregateDistances(eligibleIDs: eligibleIDs, pairwise: pairwise)
        let distances = representativeDistances(eligibleIDs: eligibleIDs, representative: representative, comparisons: toRepresentative)
        let medianDistance = median(distances.map(\.1))
        let dispersion = median(distances.map { abs($0.1 - (medianDistance ?? 0)) })
        let threshold = dispersion.map {
            (medianDistance ?? 0) + configuration.outlierMedianAbsoluteDeviationMultiplier * $0
        }

        let diagnostic = SessionComparisonDiagnostic(
            eligibleRepCount: eligibleIDs.count,
            medoidAggregateDistances: medoidDistances,
            consistencyInputSimilarities: toRepresentative.values.compactMap(\.internalSimilarity).sorted(),
            outlierCenterDistance: medianDistance,
            outlierDispersion: dispersion,
            outlierThresholdDistance: threshold,
            excludedRepReasons: excluded,
            configurationVersion: configuration.version
        )

        return SessionComparisonResult(
            recordingID: recording.id,
            analyzedReps: analyzedReps,
            eligibleRepIDs: eligibleIDs,
            representativeRepID: representative,
            fastestRepID: fastest,
            consistency: consistency,
            outlierRepIDs: outliers.sortedBySequence(in: analyzedReps),
            similarityToRepresentative: toRepresentative,
            pairwiseComparisons: pairwise,
            confidence: consistency.confidence,
            diagnostics: diagnostic,
            configurationVersion: configuration.version
        )
    }

    private func pairwiseComparisons(
        eligibleIDs: [UUID],
        aligned: [UUID: PhaseAlignedRep]
    ) -> [RepComparisonResult] {
        var comparisons: [RepComparisonResult] = []
        for leftIndex in eligibleIDs.indices {
            for rightIndex in eligibleIDs.indices where rightIndex > leftIndex {
                guard let left = aligned[eligibleIDs[leftIndex]],
                      let right = aligned[eligibleIDs[rightIndex]] else {
                    continue
                }
                comparisons.append(similarityEngine.compare(left, right))
            }
        }
        return comparisons
    }

    private func representativeRepID(
        eligibleIDs: [UUID],
        pairwise: [RepComparisonResult],
        sequenceByID: [UUID: Int]
    ) -> UUID? {
        guard eligibleIDs.count >= 2 else {
            return nil
        }
        let distances = aggregateDistances(eligibleIDs: eligibleIDs, pairwise: pairwise)
        return eligibleIDs.min { lhs, rhs in
            let left = distances[lhs] ?? Double.greatestFiniteMagnitude
            let right = distances[rhs] ?? Double.greatestFiniteMagnitude
            if abs(left - right) > 0.000_000_001 {
                return left < right
            }
            return (sequenceByID[lhs] ?? Int.max) < (sequenceByID[rhs] ?? Int.max)
        }
    }

    private func aggregateDistances(eligibleIDs: [UUID], pairwise: [RepComparisonResult]) -> [UUID: Double] {
        Dictionary(uniqueKeysWithValues: eligibleIDs.map { id in
            let sum = pairwise.filter {
                ($0.repAID == id || $0.repBID == id) && $0.availability == .available
            }.compactMap(\.aggregateError).reduce(0, +)
            return (id, sum)
        })
    }

    private func fastestRepID(_ reps: [AnalyzedRep]) -> UUID? {
        reps.filter { $0.segment.validity == .valid && $0.metrics.duration.availability == .available }
            .min { lhs, rhs in
                let left = lhs.metrics.duration.value ?? Double.greatestFiniteMagnitude
                let right = rhs.metrics.duration.value ?? Double.greatestFiniteMagnitude
                if abs(left - right) > 0.000_000_001 {
                    return left < right
                }
                return lhs.sequenceIndex < rhs.sequenceIndex
            }?.id
    }

    private func comparisonsToRepresentative(
        _ representative: UUID?,
        eligibleIDs: [UUID],
        pairwise: [RepComparisonResult]
    ) -> [UUID: RepComparisonResult] {
        guard let representative else {
            return [:]
        }
        return Dictionary(uniqueKeysWithValues: eligibleIDs.compactMap { id in
            guard id != representative,
                  let comparison = pairwise.first(where: {
                      ($0.repAID == id && $0.repBID == representative) ||
                          ($0.repAID == representative && $0.repBID == id)
                  }) else {
                return nil
            }
            return (id, comparison)
        })
    }

    private func consistencyResult(
        eligibleIDs: [UUID],
        representative: UUID?,
        comparisons: [UUID: RepComparisonResult]
    ) -> SessionConsistencyResult {
        guard configuration.primaryWristJointID != nil else {
            return SessionConsistencyResult(
                availability: .unavailable,
                internalValue: nil,
                confidence: .low,
                reason: .missingPrimaryWristConfiguration
            )
        }

        guard representative != nil,
              eligibleIDs.count >= configuration.minimumRepsForSessionConsistency else {
            return SessionConsistencyResult(
                availability: .unavailable,
                internalValue: nil,
                confidence: .low,
                reason: .insufficientEligibleReps
            )
        }
        let similarities = comparisons.values.compactMap(\.internalSimilarity)
        guard let value = median(similarities), value.isFinite else {
            return SessionConsistencyResult(
                availability: .unavailable,
                internalValue: nil,
                confidence: .low,
                reason: .insufficientJointCoverage
            )
        }
        let confidence: ConfidenceStatus = comparisons.values.allSatisfy { $0.confidence == .high } ? .high : .medium
        return SessionConsistencyResult(
            availability: .available,
            internalValue: value,
            confidence: confidence,
            reason: .none
        )
    }

    private func outlierIDs(
        eligibleIDs: [UUID],
        representative: UUID?,
        comparisons: [UUID: RepComparisonResult]
    ) -> [UUID] {
        guard representative != nil,
              eligibleIDs.count >= configuration.minimumRepsForOutlierDetection else {
            return []
        }
        let distances = representativeDistances(eligibleIDs: eligibleIDs, representative: representative, comparisons: comparisons)
        guard let center = median(distances.map(\.1)),
              let dispersion = median(distances.map { abs($0.1 - center) }) else {
            return []
        }
        if dispersion <= configuration.zeroDispersionThreshold {
            return distances.filter { $0.1 > configuration.zeroDispersionThreshold }.map(\.0)
        }
        let threshold = center + configuration.outlierMedianAbsoluteDeviationMultiplier * dispersion
        return distances.filter { $0.1 > threshold }.map(\.0)
    }

    private func representativeDistances(
        eligibleIDs: [UUID],
        representative: UUID?,
        comparisons: [UUID: RepComparisonResult]
    ) -> [(UUID, Double)] {
        guard let representative else {
            return []
        }
        return eligibleIDs.compactMap { id in
            if id == representative {
                return (id, 0)
            }
            guard let error = comparisons[id]?.aggregateError else {
                return nil
            }
            return (id, error)
        }
    }

    private func median(_ values: [Double]) -> Double? {
        let sorted = values.filter(\.isFinite).sorted()
        guard !sorted.isEmpty else {
            return nil
        }
        let midpoint = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return (sorted[midpoint - 1] + sorted[midpoint]) / 2
        }
        return sorted[midpoint]
    }
}

private extension PoseRecording {
    var coordinateVersionsAreCurrent: Bool {
        metadata.coordinateConventionVersion == VersionCatalog.current.coordinateConventionVersion &&
            metadata.jointSetVersion == VersionCatalog.current.jointSetVersion
    }
}

private extension Array where Element == UUID {
    func sortedBySequence(in reps: [AnalyzedRep]) -> [UUID] {
        sorted { lhs, rhs in
            let left = reps.first(where: { $0.id == lhs })?.sequenceIndex ?? Int.max
            let right = reps.first(where: { $0.id == rhs })?.sequenceIndex ?? Int.max
            return left < right
        }
    }
}
