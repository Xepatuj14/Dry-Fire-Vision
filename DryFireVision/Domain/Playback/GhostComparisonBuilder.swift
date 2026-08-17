import Foundation

public enum GhostComparisonUnavailableReason: String, Error, Equatable, Sendable {
    case sameRepExcluded
    case invalidRep
    case missingPoseAsset
    case corruptPoseAsset
    case unsupportedPoseEncoding
    case incompatibleAnalysisVersion
    case incompatibleCoordinateConvention
    case incompatibleJointSet
    case invalidNormalizationScale
    case insufficientJointCoverage
    case insufficientUsableJoints
    case primaryWristUnavailable
    case nonFiniteInput
}

public struct GhostComparisonResult: Equatable, Sendable {
    public let repA: AnalyzedRep
    public let repB: AnalyzedRep
    public let alignedRepA: PhaseAlignedRep
    public let alignedRepB: PhaseAlignedRep
    public let comparison: RepComparisonResult
    public let durationDifferenceSeconds: Double
    public let primaryWristJointID: PoseJointID?

    public init(
        repA: AnalyzedRep,
        repB: AnalyzedRep,
        alignedRepA: PhaseAlignedRep,
        alignedRepB: PhaseAlignedRep,
        comparison: RepComparisonResult,
        durationDifferenceSeconds: Double,
        primaryWristJointID: PoseJointID?
    ) {
        self.repA = repA
        self.repB = repB
        self.alignedRepA = alignedRepA
        self.alignedRepB = alignedRepB
        self.comparison = comparison
        self.durationDifferenceSeconds = durationDifferenceSeconds
        self.primaryWristJointID = primaryWristJointID
    }
}

public struct GhostComparisonBuilder: Sendable {
    public let configuration: AnalysisConfiguration
    private let normalizer: PhaseNormalizer
    private let similarityEngine: SimilarityEngine

    public init(configuration: AnalysisConfiguration = .ghostModeV1) {
        self.configuration = configuration
        self.normalizer = PhaseNormalizer(configuration: configuration)
        self.similarityEngine = SimilarityEngine(configuration: configuration)
    }

    public func compare(
        repA: AnalyzedRep,
        payloadA: PoseAssetPayload,
        repB: AnalyzedRep,
        payloadB: PoseAssetPayload
    ) -> Result<GhostComparisonResult, GhostComparisonUnavailableReason> {
        guard repA.segment.validity != .invalid, repB.segment.validity != .invalid else {
            return .failure(.invalidRep)
        }
        guard payloadA.encodingVersion == VersionCatalog.current.poseEncodingVersion,
              payloadB.encodingVersion == VersionCatalog.current.poseEncodingVersion else {
            return .failure(.unsupportedPoseEncoding)
        }
        guard payloadA.coordinateConventionVersion == payloadB.coordinateConventionVersion,
              payloadA.coordinateConventionVersion == VersionCatalog.current.coordinateConventionVersion else {
            return .failure(.incompatibleCoordinateConvention)
        }
        guard payloadA.jointSetVersion == payloadB.jointSetVersion,
              payloadA.jointSetVersion == VersionCatalog.current.jointSetVersion else {
            return .failure(.incompatibleJointSet)
        }
        guard payloadA.normalizationScale.isFinite,
              payloadB.normalizationScale.isFinite,
              payloadA.normalizationScale > 0,
              payloadB.normalizationScale > 0 else {
            return .failure(.invalidNormalizationScale)
        }
        guard let alignedA = normalizer.align(analyzedRep: repA, payload: payloadA),
              let alignedB = normalizer.align(analyzedRep: repB, payload: payloadB) else {
            return .failure(.insufficientJointCoverage)
        }

        let comparison = similarityEngine.compare(alignedA, alignedB)
        guard comparison.availability == .available else {
            return .failure(Self.reason(from: comparison.reason))
        }

        return .success(GhostComparisonResult(
            repA: repA,
            repB: repB,
            alignedRepA: alignedA,
            alignedRepB: alignedB,
            comparison: comparison,
            durationDifferenceSeconds: abs(repA.segment.durationSeconds - repB.segment.durationSeconds),
            primaryWristJointID: configuration.primaryWristJointID
        ))
    }

    private static func reason(from reason: ComparisonUnavailableReason) -> GhostComparisonUnavailableReason {
        switch reason {
        case .none:
            return .insufficientJointCoverage
        case .incompatibleAnalysisVersion:
            return .incompatibleAnalysisVersion
        case .incompatibleCoordinateConvention:
            return .incompatibleCoordinateConvention
        case .incompatibleJointSet:
            return .incompatibleJointSet
        case .invalidRep:
            return .invalidRep
        case .invalidNormalizationScale:
            return .invalidNormalizationScale
        case .missingPrimaryWristConfiguration, .primaryWristUnavailable:
            return .primaryWristUnavailable
        case .insufficientJointCoverage:
            return .insufficientJointCoverage
        case .insufficientUsableJoints:
            return .insufficientUsableJoints
        case .insufficientEligibleReps:
            return .insufficientUsableJoints
        case .zeroDispersion:
            return .insufficientUsableJoints
        case .nonFiniteInput:
            return .nonFiniteInput
        }
    }
}

public extension AnalysisConfiguration {
    static let ghostModeV1 = AnalysisConfiguration(primaryWristJointID: .rightWrist)
}
