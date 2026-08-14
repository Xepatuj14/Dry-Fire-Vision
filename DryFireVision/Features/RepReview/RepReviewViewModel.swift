import Combine
import Foundation

public enum RepReviewMode: Equatable, Sendable {
    case videoAndPose
    case poseOnly
    case metricsOnly
}

public enum RepReviewDegradedReason: Equatable, Sendable {
    case videoNotRecorded
    case missingPoseAsset
    case corruptPoseAsset
    case unsupportedPoseEncoding
    case poseAssetOwnershipFailed
    case emptyPosePayload
}

public enum RepReviewViewState: Equatable, Sendable {
    case loading
    case readyWithVideoAndPose(RepReviewReadyState)
    case readyPoseOnly(RepReviewReadyState)
    case readyMetricsOnly(RepReviewMetricsState, RepReviewDegradedReason)
    case poseUnavailable(RepReviewMetricsState, RepReviewDegradedReason)
    case playbackError(RepReviewMetricsState, String)
    case failed(String)
}

public struct RepReviewReadyState: Equatable, Sendable {
    public let metrics: RepReviewMetricsState
    public let playback: RepPlaybackModel
    public let currentPose: RepPlaybackPoseSample?
    public let primaryWristJointID: PoseJointID?
    public let videoUnavailableMessage: String?
}

public struct RepReviewMetricsState: Equatable, Sendable {
    public let sessionID: UUID
    public let repID: UUID
    public let repNumberText: String
    public let durationText: String
    public let headDisplacementText: String
    public let shoulderDisplacementText: String
    public let wristPathLengthText: String
    public let wristDirectnessText: String
    public let classificationLabels: [String]
    public let confidenceNote: String?
    public let canOpenPreviousRep: Bool
    public let canOpenNextRep: Bool
    public let previousRepLabel: String?
    public let nextRepLabel: String?
}

@MainActor
public final class RepReviewViewModel: ObservableObject {
    @Published public private(set) var state: RepReviewViewState = .loading

    private let sessionID: UUID
    private let sessionRepository: any SessionRepository
    private let poseAssetStore: any PoseAssetStoring
    private let lookup: RepPoseSampleLookup
    private var analysis: SessionAnalysis?
    private var selectedRepID: UUID
    private var loadTask: Task<Void, Never>?

    public init(
        sessionID: UUID,
        repID: UUID,
        sessionRepository: any SessionRepository,
        poseAssetStore: any PoseAssetStoring,
        lookup: RepPoseSampleLookup = RepPoseSampleLookup()
    ) {
        self.sessionID = sessionID
        self.selectedRepID = repID
        self.sessionRepository = sessionRepository
        self.poseAssetStore = poseAssetStore
        self.lookup = lookup
    }

    deinit {
        loadTask?.cancel()
    }

    public func load() {
        load(repID: selectedRepID)
    }

    public func load(repID: UUID) {
        loadTask?.cancel()
        selectedRepID = repID
        state = .loading
        loadTask = Task { [weak self] in
            guard let self else {
                return
            }
            await self.loadSelectedRep(repID: repID)
        }
    }

    public func play() {
        updatePlayback { playback in
            playback.play()
        }
    }

    public func pause() {
        updatePlayback { playback in
            playback.pause()
        }
    }

    public func scrub(to timeSeconds: Double) {
        updatePlayback { playback in
            playback.scrub(to: timeSeconds)
        }
    }

    public func advancePlayback(by elapsedSeconds: Double) {
        updatePlayback { playback in
            playback.advance(by: elapsedSeconds)
        }
    }

    public func setPlaybackSpeed(_ speed: RepPlaybackSpeed) {
        updatePlayback { playback in
            playback.speed = speed
        }
    }

    public func setTrajectoryVisible(_ isVisible: Bool) {
        updatePlayback { playback in
            playback.trajectoryVisible = isVisible
        }
    }

    public func stepToPreviousPoseSample() {
        guard let playback = currentPlayback,
              let sample = lookup.previousStoredSample(before: playback.currentTimeSeconds, in: playback.orderedPoseSamples) else {
            return
        }
        scrub(to: sample.repTimeSeconds)
    }

    public func stepToNextPoseSample() {
        guard let playback = currentPlayback,
              let sample = lookup.nextStoredSample(after: playback.currentTimeSeconds, in: playback.orderedPoseSamples) else {
            return
        }
        scrub(to: sample.repTimeSeconds)
    }

    public func openPreviousRep() {
        guard let target = adjacentRep(offset: -1) else {
            return
        }
        load(repID: target.id)
    }

    public func openNextRep() {
        guard let target = adjacentRep(offset: 1) else {
            return
        }
        load(repID: target.id)
    }

    private var currentPlayback: RepPlaybackModel? {
        switch state {
        case .readyWithVideoAndPose(let ready), .readyPoseOnly(let ready):
            return ready.playback
        case .loading, .readyMetricsOnly, .poseUnavailable, .playbackError, .failed:
            return nil
        }
    }

    private func loadSelectedRep(repID: UUID) async {
        do {
            let snapshot = try await sessionRepository.session(id: sessionID)
            guard let analysis = snapshot.analysis else {
                state = .failed("Saved analysis is unavailable.")
                return
            }
            self.analysis = analysis
            guard let rep = analysis.analyzedReps.first(where: { $0.id == repID }) else {
                state = .failed("This repetition is not part of the saved session.")
                return
            }

            let metrics = metricsState(for: rep, analysis: analysis)
            guard let reference = try await sessionRepository.poseAssetReference(sessionID: sessionID, repID: repID) else {
                state = .readyMetricsOnly(metrics, .missingPoseAsset)
                return
            }
            guard reference.sessionID == sessionID, reference.repID == repID else {
                state = .poseUnavailable(metrics, .poseAssetOwnershipFailed)
                return
            }
            guard reference.encodingVersion == VersionCatalog.current.poseEncodingVersion,
                  reference.jointSetVersion == VersionCatalog.current.jointSetVersion,
                  reference.coordinateConventionVersion == VersionCatalog.current.coordinateConventionVersion else {
                state = .poseUnavailable(metrics, .unsupportedPoseEncoding)
                return
            }
            guard await poseAssetStore.exists(storageLocation: reference.storageLocation) else {
                state = .poseUnavailable(metrics, .missingPoseAsset)
                return
            }

            let payload: PoseAssetPayload
            do {
                payload = try await poseAssetStore.load(storageLocation: reference.storageLocation)
            } catch PersistenceError.unsupportedPayloadVersion(_) {
                state = .poseUnavailable(metrics, .unsupportedPoseEncoding)
                return
            } catch {
                state = .poseUnavailable(metrics, .corruptPoseAsset)
                return
            }
            guard payload.encodingVersion == reference.encodingVersion,
                  payload.jointSetVersion == reference.jointSetVersion,
                  payload.coordinateConventionVersion == reference.coordinateConventionVersion else {
                state = .poseUnavailable(metrics, .unsupportedPoseEncoding)
                return
            }

            let playback = RepPlaybackModelBuilder.make(repID: repID, rep: rep, payload: payload)
            guard !playback.orderedPoseSamples.isEmpty else {
                state = .poseUnavailable(metrics, .emptyPosePayload)
                return
            }
            let ready = readyState(
                metrics: metrics,
                playback: playback,
                videoUnavailableMessage: videoMessage(for: snapshot.videoRetentionState)
            )
            state = .readyPoseOnly(ready)
        } catch PersistenceError.sessionNotFound(_) {
            state = .failed("Saved session was not found.")
        } catch PersistenceError.integrityViolation(_) {
            state = .failed("Saved session integrity could not be verified.")
        } catch {
            state = .failed("Rep Review could not load this repetition.")
        }
    }

    private func updatePlayback(_ update: (inout RepPlaybackModel) -> Void) {
        switch state {
        case .readyWithVideoAndPose(let ready):
            var playback = ready.playback
            update(&playback)
            state = .readyWithVideoAndPose(readyState(metrics: ready.metrics, playback: playback, videoUnavailableMessage: ready.videoUnavailableMessage))
        case .readyPoseOnly(let ready):
            var playback = ready.playback
            update(&playback)
            state = .readyPoseOnly(readyState(metrics: ready.metrics, playback: playback, videoUnavailableMessage: ready.videoUnavailableMessage))
        case .loading, .readyMetricsOnly, .poseUnavailable, .playbackError, .failed:
            break
        }
    }

    private func readyState(
        metrics: RepReviewMetricsState,
        playback: RepPlaybackModel,
        videoUnavailableMessage: String?
    ) -> RepReviewReadyState {
        RepReviewReadyState(
            metrics: metrics,
            playback: playback,
            currentPose: lookup.sample(at: playback.currentTimeSeconds, in: playback.orderedPoseSamples),
            primaryWristJointID: primaryWristJointID(in: playback.orderedPoseSamples),
            videoUnavailableMessage: videoUnavailableMessage
        )
    }

    private func metricsState(for rep: AnalyzedRep, analysis: SessionAnalysis) -> RepReviewMetricsState {
        let ordered = analysis.analyzedReps.sorted { $0.sequenceIndex < $1.sequenceIndex }
        let index = ordered.firstIndex { $0.id == rep.id }
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
        return RepReviewMetricsState(
            sessionID: analysis.sessionID,
            repID: rep.id,
            repNumberText: "Rep \(rep.sequenceIndex + 1)",
            durationText: Self.metricText(rep.metrics.duration, formatter: Self.formatSeconds),
            headDisplacementText: Self.metricText(rep.metrics.headDisplacement, formatter: Self.formatNormalized),
            shoulderDisplacementText: Self.metricText(rep.metrics.shoulderDisplacement, formatter: Self.formatNormalized),
            wristPathLengthText: Self.metricText(rep.metrics.primaryWristPathLength, formatter: Self.formatNormalized),
            wristDirectnessText: Self.metricText(rep.metrics.wristPathDirectness, formatter: Self.formatRatio),
            classificationLabels: labels,
            confidenceNote: confidenceNote(for: rep.metrics),
            canOpenPreviousRep: (index ?? 0) > 0,
            canOpenNextRep: index.map { $0 < ordered.count - 1 } ?? false,
            previousRepLabel: previousNextLabel(index: index.map { $0 - 1 }, ordered: ordered),
            nextRepLabel: previousNextLabel(index: index.map { $0 + 1 }, ordered: ordered)
        )
    }

    private func previousNextLabel(index: Int?, ordered: [AnalyzedRep]) -> String? {
        guard let index, ordered.indices.contains(index) else {
            return nil
        }
        return "Rep \(ordered[index].sequenceIndex + 1)"
    }

    private func adjacentRep(offset: Int) -> AnalyzedRep? {
        guard let analysis,
              let currentIndex = analysis.analyzedReps.sorted(by: { $0.sequenceIndex < $1.sequenceIndex }).firstIndex(where: { $0.id == selectedRepID }) else {
            return nil
        }
        let ordered = analysis.analyzedReps.sorted { $0.sequenceIndex < $1.sequenceIndex }
        let targetIndex = currentIndex + offset
        guard ordered.indices.contains(targetIndex) else {
            return nil
        }
        return ordered[targetIndex]
    }

    private func primaryWristJointID(in samples: [RepPlaybackPoseSample]) -> PoseJointID? {
        if samples.contains(where: { $0.joints[.rightWrist] != nil }) {
            return .rightWrist
        }
        if samples.contains(where: { $0.joints[.leftWrist] != nil }) {
            return .leftWrist
        }
        return nil
    }

    private func confidenceNote(for metrics: MovementMetricSet) -> String? {
        let values = [
            metrics.duration,
            metrics.headDisplacement,
            metrics.shoulderDisplacement,
            metrics.primaryWristPathLength,
            metrics.wristPathDirectness
        ]
        if values.contains(where: { $0.reason == .lowJointConfidence }) {
            return "Tracking was limited during part of this repetition."
        }
        if values.contains(where: { $0.availability == .unavailable }) {
            return "Some movement data unavailable."
        }
        return nil
    }

    private func videoMessage(for state: VideoRetentionState) -> String {
        switch state {
        case .notRecorded:
            return "Original video was not recorded for this session."
        case .deleted:
            return "Original video is unavailable; pose playback is preserved."
        case .keep, .pendingDelete, .deletionFailed:
            return "Video playback is not available in this build; pose playback is preserved."
        }
    }

    private static func metricText(_ result: MovementMetricResult, formatter: (Double) -> String) -> String {
        guard result.availability == .available, let value = result.value else {
            return result.reason == .lowJointConfidence ? "Insufficient confidence" : "Unavailable"
        }
        return formatter(value)
    }

    private static func formatSeconds(_ value: Double) -> String {
        String(format: "%.2f s", value)
    }

    private static func formatNormalized(_ value: Double) -> String {
        String(format: "%.3f normalized", value)
    }

    private static func formatRatio(_ value: Double) -> String {
        String(format: "%.2f ratio", value)
    }
}
