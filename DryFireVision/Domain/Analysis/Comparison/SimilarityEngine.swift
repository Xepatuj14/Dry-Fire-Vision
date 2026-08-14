import Foundation

public struct SimilarityEngine: Sendable {
    public let configuration: AnalysisConfiguration

    public init(configuration: AnalysisConfiguration) {
        self.configuration = configuration
    }

    public func compare(_ lhs: PhaseAlignedRep?, _ rhs: PhaseAlignedRep?) -> RepComparisonResult {
        guard let lhs, let rhs else {
            return unavailable(
                repAID: lhs?.repID ?? zeroUUID(),
                repBID: rhs?.repID ?? zeroUUID(),
                reason: .invalidNormalizationScale
            )
        }

        guard lhs.analysisVersion == rhs.analysisVersion else {
            return unavailable(repAID: lhs.repID, repBID: rhs.repID, reason: .incompatibleAnalysisVersion)
        }
        guard lhs.phaseGrid == rhs.phaseGrid else {
            return unavailable(repAID: lhs.repID, repBID: rhs.repID, reason: .insufficientJointCoverage)
        }

        let jointResults = comparableJointIDs().map { jointID in
            compare(jointID: jointID, lhs: lhs.trajectories[jointID] ?? [], rhs: rhs.trajectories[jointID] ?? [])
        }
        let available = jointResults.filter { $0.availability == .available && $0.averageError != nil }
        guard available.count >= configuration.minimumUsableComparisonJoints else {
            return RepComparisonResult(
                id: deterministicID(lhs.repID, rhs.repID),
                repAID: lhs.repID,
                repBID: rhs.repID,
                availability: .unavailable,
                reason: .insufficientUsableJoints,
                jointResults: jointResults,
                aggregateError: nil,
                internalSimilarity: nil,
                confidence: .low,
                usableJointCoverage: usableCoverage(available),
                configurationVersion: configuration.version
            )
        }

        let weighted = available.compactMap { result -> (Double, Double)? in
            guard let error = result.averageError else {
                return nil
            }
            let weight = configuration.comparisonJointWeights[result.jointID] ?? 0
            return weight > 0 ? (error, weight) : nil
        }
        let totalWeight = weighted.map(\.1).reduce(0, +)
        guard totalWeight > 0 else {
            return unavailable(repAID: lhs.repID, repBID: rhs.repID, reason: .insufficientUsableJoints, jointResults: jointResults)
        }
        let aggregateError = weighted.reduce(0.0) { partial, item in
            partial + item.0 * (item.1 / totalWeight)
        }
        guard aggregateError.isFinite, configuration.similarityErrorScale > 0 else {
            return unavailable(repAID: lhs.repID, repBID: rhs.repID, reason: .nonFiniteInput, jointResults: jointResults)
        }
        let similarity = 1 / (1 + aggregateError / configuration.similarityErrorScale)
        let boundedSimilarity = min(1, max(0, similarity))
        let coverage = usableCoverage(available)

        return RepComparisonResult(
            id: deterministicID(lhs.repID, rhs.repID),
            repAID: lhs.repID,
            repBID: rhs.repID,
            availability: .available,
            reason: .none,
            jointResults: jointResults,
            aggregateError: aggregateError,
            internalSimilarity: boundedSimilarity,
            confidence: confidence(jointResults: available, coverage: coverage),
            usableJointCoverage: coverage,
            configurationVersion: configuration.version
        )
    }

    private func compare(jointID: PoseJointID, lhs: [PhaseSample?], rhs: [PhaseSample?]) -> JointComparisonResult {
        let pairs = zip(lhs, rhs).compactMap { left, right -> (PhaseSample, PhaseSample)? in
            guard let left, let right else {
                return nil
            }
            return (left, right)
        }
        let expectedCount = min(lhs.count, rhs.count)
        let coverage = expectedCount > 0 ? Double(pairs.count) / Double(expectedCount) : 0
        guard coverage >= configuration.minimumComparisonJointCoverage else {
            return JointComparisonResult(
                jointID: jointID,
                availability: .unavailable,
                averageError: nil,
                coverage: coverage,
                confidence: .low,
                reason: .insufficientJointCoverage
            )
        }

        let errors = pairs.compactMap { pair in
            MetricMath.euclideanDistance(x1: pair.0.x, y1: pair.0.y, x2: pair.1.x, y2: pair.1.y)
        }
        guard errors.count == pairs.count, !errors.isEmpty else {
            return JointComparisonResult(
                jointID: jointID,
                availability: .unavailable,
                averageError: nil,
                coverage: coverage,
                confidence: .low,
                reason: .nonFiniteInput
            )
        }
        let averageError = errors.reduce(0, +) / Double(errors.count)
        return JointComparisonResult(
            jointID: jointID,
            availability: .available,
            averageError: averageError,
            coverage: coverage,
            confidence: coverage >= 0.95 ? .high : .medium,
            reason: .none
        )
    }

    private func comparableJointIDs() -> [PoseJointID] {
        guard let wrist = configuration.primaryWristJointID else {
            return [.nose, .leftShoulder, .rightShoulder]
        }
        return [.nose, .leftShoulder, .rightShoulder, wrist]
    }

    private func usableCoverage(_ results: [JointComparisonResult]) -> Double {
        guard !results.isEmpty else {
            return 0
        }
        return results.map(\.coverage).reduce(0, +) / Double(results.count)
    }

    private func confidence(jointResults: [JointComparisonResult], coverage: Double) -> ConfidenceStatus {
        if jointResults.allSatisfy({ $0.confidence == .high }) && coverage >= 0.95 {
            return .high
        }
        if coverage >= configuration.minimumComparisonJointCoverage {
            return .medium
        }
        return .low
    }

    private func unavailable(
        repAID: UUID,
        repBID: UUID,
        reason: ComparisonUnavailableReason,
        jointResults: [JointComparisonResult] = []
    ) -> RepComparisonResult {
        RepComparisonResult(
            id: deterministicID(repAID, repBID),
            repAID: repAID,
            repBID: repBID,
            availability: .unavailable,
            reason: reason,
            jointResults: jointResults,
            aggregateError: nil,
            internalSimilarity: nil,
            confidence: .low,
            usableJointCoverage: 0,
            configurationVersion: configuration.version
        )
    }

    private func deterministicID(_ lhs: UUID, _ rhs: UUID) -> UUID {
        let ordered = [lhs.uuidString, rhs.uuidString].sorted().joined()
        let seed = ordered.unicodeScalars.reduce(UInt64(14_695_981_039_346_656_037)) { partial, scalar in
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
            0, 0, 0, 0, 0, 0, 0, 7
        ))
    }

    private func zeroUUID() -> UUID {
        UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))
    }
}
