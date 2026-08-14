import Combine
import Foundation

public enum GhostModeViewState: Equatable, Sendable {
    case loading
    case selectingRep(GhostRepSelectionState)
    case preparingComparison(GhostRepSelectionState)
    case ready(GhostModeReadyState)
    case incompatible(GhostUnavailableState)
    case insufficientData(GhostUnavailableState)
    case failed(String)
}

public struct GhostRepSelectionState: Equatable, Sendable {
    public let sessionID: UUID
    public let reference: GhostRepCandidateState
    public let candidates: [GhostRepCandidateState]
    public let noCompatibleMessage: String?
}

public struct GhostRepCandidateState: Equatable, Identifiable, Sendable {
    public let id: UUID
    public let repNumberText: String
    public let durationText: String
    public let classificationLabels: [String]
    public let compatibilityText: String
    public let isCompatible: Bool
    public let isRepresentativeSuggestion: Bool
}

public struct GhostUnavailableState: Equatable, Sendable {
    public let title: String
    public let message: String
    public let selection: GhostRepSelectionState?
}

public struct GhostModeReadyState: Equatable, Sendable {
    public let playback: GhostPlaybackModel
    public let currentPoseA: GhostPlaybackPose?
    public let currentPoseB: GhostPlaybackPose?
    public let metrics: GhostComparisonMetricsState
    public let primaryWristJointID: PoseJointID?
    public let videoUnavailableMessage: String
}

public struct GhostComparisonMetricsState: Equatable, Sendable {
    public let repALabel: String
    public let repBLabel: String
    public let repAClassifications: [String]
    public let repBClassifications: [String]
    public let repADurationText: String
    public let repBDurationText: String
    public let durationDifferenceText: String
    public let headDifferenceText: String
    public let shoulderDifferenceText: String
    public let wristPathDifferenceText: String
    public let wristDirectnessDifferenceText: String
    public let similarityText: String
    public let confidenceText: String?
}

@MainActor
public final class GhostModeViewModel: ObservableObject {
    @Published public private(set) var state: GhostModeViewState = .loading

    private let sessionID: UUID
    private let referenceRepID: UUID
    private let sessionRepository: any SessionRepository
    private let poseAssetStore: any PoseAssetStoring
    private let builder: GhostComparisonBuilder
    private let lookup = GhostPoseLookup()
    private var analysis: SessionAnalysis?
    private var selectionState: GhostRepSelectionState?
    private var loadTask: Task<Void, Never>?

    public init(
        sessionID: UUID,
        referenceRepID: UUID,
        sessionRepository: any SessionRepository,
        poseAssetStore: any PoseAssetStoring,
        builder: GhostComparisonBuilder = GhostComparisonBuilder()
    ) {
        self.sessionID = sessionID
        self.referenceRepID = referenceRepID
        self.sessionRepository = sessionRepository
        self.poseAssetStore = poseAssetStore
        self.builder = builder
    }

    deinit {
        loadTask?.cancel()
    }

    public func loadSelection() {
        loadTask?.cancel()
        state = .loading
        loadTask = Task { [weak self] in
            guard let self else {
                return
            }
            await self.loadSelectionState()
        }
    }

    public func chooseCandidate(repID: UUID) {
        guard let selectionState,
              let candidate = selectionState.candidates.first(where: { $0.id == repID }),
              candidate.isCompatible else {
            return
        }
        state = .preparingComparison(selectionState)
        loadTask?.cancel()
        loadTask = Task { [weak self] in
            guard let self else {
                return
            }
            await self.prepareComparison(repBID: repID)
        }
    }

    public func chooseAnotherRep() {
        if let selectionState {
            state = .selectingRep(selectionState)
        } else {
            loadSelection()
        }
    }

    public func play() {
        updatePlayback { $0.play() }
    }

    public func pause() {
        updatePlayback { $0.pause() }
    }

    public func scrub(to phase: Double) {
        updatePlayback { $0.scrub(to: phase) }
    }

    public func advancePlayback(by elapsedSeconds: Double) {
        updatePlayback { $0.advance(by: elapsedSeconds) }
    }

    public func setPlaybackSpeed(_ speed: RepPlaybackSpeed) {
        updatePlayback { $0.speed = speed }
    }

    public func setTrajectoryVisible(_ isVisible: Bool) {
        updatePlayback { $0.trajectoryVisible = isVisible }
    }

    private func loadSelectionState() async {
        do {
            let snapshot = try await sessionRepository.session(id: sessionID)
            guard let analysis = snapshot.analysis else {
                state = .failed("Saved analysis is unavailable.")
                return
            }
            self.analysis = analysis
            guard let reference = analysis.analyzedReps.first(where: { $0.id == referenceRepID }) else {
                state = .failed("Reference repetition is not part of this saved session.")
                return
            }
            let referenceState = candidateState(
                rep: reference,
                analysis: analysis,
                compatibilityText: "Reference Rep",
                isCompatible: true,
                isRepresentativeSuggestion: false
            )
            var candidates: [GhostRepCandidateState] = []
            for rep in analysis.analyzedReps.sorted(by: { $0.sequenceIndex < $1.sequenceIndex }) where rep.id != referenceRepID {
                let compatibility = await compatibilityText(for: rep, analysis: analysis)
                candidates.append(candidateState(
                    rep: rep,
                    analysis: analysis,
                    compatibilityText: compatibility.text,
                    isCompatible: compatibility.isCompatible,
                    isRepresentativeSuggestion: rep.id == analysis.representativeRepID && reference.id != analysis.representativeRepID
                ))
            }
            let hasCompatible = candidates.contains(where: \.isCompatible)
            let selection = GhostRepSelectionState(
                sessionID: sessionID,
                reference: referenceState,
                candidates: candidates,
                noCompatibleMessage: hasCompatible ? nil : "Another compatible repetition with saved pose data is required for Ghost Mode."
            )
            self.selectionState = selection
            state = .selectingRep(selection)
        } catch PersistenceError.sessionNotFound(_) {
            state = .failed("Saved session was not found.")
        } catch {
            state = .failed("Ghost Mode could not load this session.")
        }
    }

    private func prepareComparison(repBID: UUID) async {
        guard let analysis,
              let selectionState,
              let repA = analysis.analyzedReps.first(where: { $0.id == referenceRepID }),
              let repB = analysis.analyzedReps.first(where: { $0.id == repBID }) else {
            state = .failed("Ghost Mode could not resolve both repetitions.")
            return
        }

        do {
            let payloadA = try await loadPosePayload(repID: repA.id)
            let payloadB = try await loadPosePayload(repID: repB.id)
            switch builder.compare(repA: repA, payloadA: payloadA, repB: repB, payloadB: payloadB) {
            case .success(let result):
                let playback = GhostPlaybackModel(
                    repAID: repA.id,
                    repBID: repB.id,
                    repADurationSeconds: repA.segment.durationSeconds,
                    repBDurationSeconds: repB.segment.durationSeconds,
                    alignedRepA: result.alignedRepA,
                    alignedRepB: result.alignedRepB
                )
                state = .ready(readyState(playback: playback, result: result, analysis: analysis))
            case .failure(let reason):
                state = unavailableState(for: reason, selection: selectionState)
            }
        } catch let reason as GhostPoseLoadError {
            state = unavailableState(for: reason.unavailableReason, selection: selectionState)
        } catch {
            state = .failed("Ghost Mode could not prepare this comparison.")
        }
    }

    private func loadPosePayload(repID: UUID) async throws -> PoseAssetPayload {
        guard let reference = try await sessionRepository.poseAssetReference(sessionID: sessionID, repID: repID) else {
            throw GhostPoseLoadError(.missingPoseAsset)
        }
        guard reference.sessionID == sessionID, reference.repID == repID else {
            throw GhostPoseLoadError(.missingPoseAsset)
        }
        guard reference.encodingVersion == VersionCatalog.current.poseEncodingVersion else {
            throw GhostPoseLoadError(.unsupportedPoseEncoding)
        }
        guard reference.coordinateConventionVersion == VersionCatalog.current.coordinateConventionVersion else {
            throw GhostPoseLoadError(.incompatibleCoordinateConvention)
        }
        guard reference.jointSetVersion == VersionCatalog.current.jointSetVersion else {
            throw GhostPoseLoadError(.incompatibleJointSet)
        }
        guard await poseAssetStore.exists(storageLocation: reference.storageLocation) else {
            throw GhostPoseLoadError(.missingPoseAsset)
        }
        do {
            return try await poseAssetStore.load(storageLocation: reference.storageLocation)
        } catch PersistenceError.unsupportedPayloadVersion(_) {
            throw GhostPoseLoadError(.unsupportedPoseEncoding)
        } catch {
            throw GhostPoseLoadError(.corruptPoseAsset)
        }
    }

    private func updatePlayback(_ update: (inout GhostPlaybackModel) -> Void) {
        guard case .ready(let ready) = state else {
            return
        }
        var playback = ready.playback
        update(&playback)
        state = .ready(readyState(playback: playback, metrics: ready.metrics, primaryWristJointID: ready.primaryWristJointID))
    }

    private func readyState(
        playback: GhostPlaybackModel,
        result: GhostComparisonResult,
        analysis: SessionAnalysis
    ) -> GhostModeReadyState {
        readyState(
            playback: playback,
            metrics: metricsState(result: result, analysis: analysis),
            primaryWristJointID: result.primaryWristJointID
        )
    }

    private func readyState(
        playback: GhostPlaybackModel,
        metrics: GhostComparisonMetricsState,
        primaryWristJointID: PoseJointID?
    ) -> GhostModeReadyState {
        GhostModeReadyState(
            playback: playback,
            currentPoseA: lookup.pose(at: playback.currentPhase, in: playback.alignedRepA),
            currentPoseB: lookup.pose(at: playback.currentPhase, in: playback.alignedRepB),
            metrics: metrics,
            primaryWristJointID: primaryWristJointID,
            videoUnavailableMessage: "Ghost Mode is using saved pose data. Original video playback is not available in this build."
        )
    }

    private func compatibilityText(for rep: AnalyzedRep, analysis: SessionAnalysis) async -> (text: String, isCompatible: Bool) {
        guard rep.segment.validity != .invalid else {
            return ("Invalid rep", false)
        }
        guard analysis.analysisVersion == VersionCatalog.current.analysisVersion else {
            return ("Incompatible analysis version", false)
        }
        do {
            guard let reference = try await sessionRepository.poseAssetReference(sessionID: sessionID, repID: rep.id) else {
                return ("Missing pose data", false)
            }
            guard reference.encodingVersion == VersionCatalog.current.poseEncodingVersion else {
                return ("Unsupported pose format", false)
            }
            guard reference.coordinateConventionVersion == VersionCatalog.current.coordinateConventionVersion else {
                return ("Incompatible coordinates", false)
            }
            guard reference.jointSetVersion == VersionCatalog.current.jointSetVersion else {
                return ("Incompatible joint set", false)
            }
            guard await poseAssetStore.exists(storageLocation: reference.storageLocation) else {
                return ("Missing pose data", false)
            }
            return ("Compatible", true)
        } catch {
            return ("Unavailable", false)
        }
    }

    private func candidateState(
        rep: AnalyzedRep,
        analysis: SessionAnalysis,
        compatibilityText: String,
        isCompatible: Bool,
        isRepresentativeSuggestion: Bool
    ) -> GhostRepCandidateState {
        GhostRepCandidateState(
            id: rep.id,
            repNumberText: "Rep \(rep.sequenceIndex + 1)",
            durationText: metricText(rep.metrics.duration, formatter: formatSeconds),
            classificationLabels: classifications(rep: rep, analysis: analysis),
            compatibilityText: compatibilityText,
            isCompatible: isCompatible,
            isRepresentativeSuggestion: isRepresentativeSuggestion
        )
    }

    private func metricsState(result: GhostComparisonResult, analysis: SessionAnalysis) -> GhostComparisonMetricsState {
        GhostComparisonMetricsState(
            repALabel: "Rep A: Rep \(result.repA.sequenceIndex + 1)",
            repBLabel: "Rep B: Rep \(result.repB.sequenceIndex + 1)",
            repAClassifications: classifications(rep: result.repA, analysis: analysis),
            repBClassifications: classifications(rep: result.repB, analysis: analysis),
            repADurationText: metricText(result.repA.metrics.duration, formatter: formatSeconds),
            repBDurationText: metricText(result.repB.metrics.duration, formatter: formatSeconds),
            durationDifferenceText: formatSeconds(result.durationDifferenceSeconds),
            headDifferenceText: differenceText(result.repA.metrics.headDisplacement, result.repB.metrics.headDisplacement, label: "Head displacement"),
            shoulderDifferenceText: differenceText(result.repA.metrics.shoulderDisplacement, result.repB.metrics.shoulderDisplacement, label: "Shoulder displacement"),
            wristPathDifferenceText: differenceText(result.repA.metrics.primaryWristPathLength, result.repB.metrics.primaryWristPathLength, label: "Wrist path length"),
            wristDirectnessDifferenceText: differenceText(result.repA.metrics.wristPathDirectness, result.repB.metrics.wristPathDirectness, label: "Wrist directness"),
            similarityText: result.comparison.availability == .available ? "Movement Comparison Available" : "Insufficient comparison data",
            confidenceText: confidenceText(result.comparison.confidence)
        )
    }

    private func unavailableState(for reason: GhostComparisonUnavailableReason, selection: GhostRepSelectionState?) -> GhostModeViewState {
        let state = GhostUnavailableState(
            title: title(for: reason),
            message: message(for: reason),
            selection: selection
        )
        switch reason {
        case .invalidRep, .unsupportedPoseEncoding, .incompatibleAnalysisVersion, .incompatibleCoordinateConvention, .incompatibleJointSet, .invalidNormalizationScale:
            return .incompatible(state)
        case .sameRepExcluded, .missingPoseAsset, .corruptPoseAsset, .insufficientJointCoverage, .insufficientUsableJoints, .primaryWristUnavailable, .nonFiniteInput:
            return .insufficientData(state)
        }
    }

    private func title(for reason: GhostComparisonUnavailableReason) -> String {
        switch reason {
        case .invalidRep, .unsupportedPoseEncoding, .incompatibleAnalysisVersion, .incompatibleCoordinateConvention, .incompatibleJointSet, .invalidNormalizationScale:
            return "Comparison Incompatible"
        case .sameRepExcluded, .missingPoseAsset, .corruptPoseAsset, .insufficientJointCoverage, .insufficientUsableJoints, .primaryWristUnavailable, .nonFiniteInput:
            return "Insufficient Comparison Data"
        }
    }

    private func message(for reason: GhostComparisonUnavailableReason) -> String {
        switch reason {
        case .sameRepExcluded:
            return "Choose a different repetition for production Ghost Mode."
        case .invalidRep:
            return "One repetition is invalid and cannot be compared."
        case .missingPoseAsset:
            return "One repetition is missing saved pose data."
        case .corruptPoseAsset:
            return "One saved pose asset could not be decoded."
        case .unsupportedPoseEncoding:
            return "One saved pose asset uses an unsupported format."
        case .incompatibleAnalysisVersion:
            return "These repetitions use incompatible analysis versions."
        case .incompatibleCoordinateConvention:
            return "These repetitions use incompatible coordinate conventions."
        case .incompatibleJointSet:
            return "These repetitions use incompatible joint sets."
        case .invalidNormalizationScale:
            return "One repetition has invalid normalization metadata."
        case .insufficientJointCoverage:
            return "The repetitions do not have enough overlapping tracked joints."
        case .insufficientUsableJoints:
            return "The comparison engine could not find enough usable joints."
        case .primaryWristUnavailable:
            return "Primary wrist tracking is unavailable."
        case .nonFiniteInput:
            return "The comparison contains invalid numeric data."
        }
    }

    private func classifications(rep: AnalyzedRep, analysis: SessionAnalysis) -> [String] {
        var labels: [String] = []
        if analysis.representativeRepID == rep.id {
            labels.append("Representative Rep")
        }
        if analysis.fastestRepID == rep.id {
            labels.append("Fastest Rep")
        }
        if analysis.movementOutlierRepIDs.contains(rep.id) {
            labels.append("Movement Outlier")
        }
        return labels
    }

    private func differenceText(_ lhs: MovementMetricResult, _ rhs: MovementMetricResult, label: String) -> String {
        guard lhs.availability == .available,
              rhs.availability == .available,
              let left = lhs.value,
              let right = rhs.value else {
            if lhs.reason == .lowJointConfidence || rhs.reason == .lowJointConfidence {
                return "\(label): Insufficient confidence"
            }
            return "\(label): Unavailable"
        }
        let difference = right - left
        if abs(difference) <= 0.000_001 {
            return "\(label): no measured difference"
        }
        let direction = difference > 0 ? "higher in Rep B" : "lower in Rep B"
        return "\(label): \(formatNormalized(abs(difference))) \(direction)"
    }

    private func metricText(_ result: MovementMetricResult, formatter: (Double) -> String) -> String {
        guard result.availability == .available, let value = result.value else {
            return result.reason == .lowJointConfidence ? "Insufficient confidence" : "Unavailable"
        }
        return formatter(value)
    }

    private func confidenceText(_ confidence: ConfidenceStatus) -> String? {
        switch confidence {
        case .high:
            return nil
        case .medium:
            return "Comparison confidence: partial"
        case .low:
            return "Insufficient confidence"
        }
    }

    private func formatSeconds(_ value: Double) -> String {
        String(format: "%.2f s", value)
    }

    private func formatNormalized(_ value: Double) -> String {
        String(format: "%.3f normalized", value)
    }
}

private struct GhostPoseLoadError: Error {
    let unavailableReason: GhostComparisonUnavailableReason

    init(_ unavailableReason: GhostComparisonUnavailableReason) {
        self.unavailableReason = unavailableReason
    }
}
