import Combine
import SwiftUI

public struct RepReviewView: View {
    @StateObject private var viewModel: RepReviewViewModel
    private let sessionRepository: any SessionRepository
    private let poseAssetStore: any PoseAssetStoring
    private let playbackTimer = Timer.publish(every: 1.0 / 30.0, on: .main, in: .common).autoconnect()

    public init(
        viewModel: RepReviewViewModel,
        sessionRepository: any SessionRepository,
        poseAssetStore: any PoseAssetStoring
    ) {
        self._viewModel = StateObject(wrappedValue: viewModel)
        self.sessionRepository = sessionRepository
        self.poseAssetStore = poseAssetStore
    }

    public var body: some View {
        Group {
            switch viewModel.state {
            case .loading:
                ProgressView("Loading Rep Review")
            case .readyWithVideoAndPose(let ready), .readyPoseOnly(let ready):
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        header(metrics: ready.metrics)
                        PosePlaybackCanvas(ready: ready)
                            .frame(maxWidth: .infinity)
                            .aspectRatio(9.0 / 16.0, contentMode: .fit)
                            .accessibilityLabel("Pose playback canvas")
                        if let message = ready.videoUnavailableMessage {
                            Text(message)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        playbackControls(ready: ready)
                        overlayControls(ready: ready)
                        metricsPanel(ready.metrics)
                        compareLink(metrics: ready.metrics)
                        availabilityNote(ready.metrics.confidenceNote)
                    }
                    .padding()
                }
            case .readyMetricsOnly(let metrics, let reason), .poseUnavailable(let metrics, let reason):
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        header(metrics: metrics)
                        PlaceholderStateView(
                            title: "Pose Unavailable",
                            message: degradedMessage(for: reason),
                            systemImage: "figure.arms.open"
                        )
                        metricsPanel(metrics)
                        compareLink(metrics: metrics)
                        availabilityNote(metrics.confidenceNote)
                    }
                    .padding()
                }
            case .playbackError(let metrics, let message):
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        header(metrics: metrics)
                        PlaceholderStateView(title: "Playback Error", message: message, systemImage: "exclamationmark.triangle")
                        metricsPanel(metrics)
                    }
                    .padding()
                }
            case .failed(let message):
                PlaceholderStateView(title: "Rep Review Unavailable", message: message, systemImage: "exclamationmark.triangle")
                    .padding()
            }
        }
        .navigationTitle("Rep Review")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            viewModel.load()
        }
        .onReceive(playbackTimer) { _ in
            viewModel.advancePlayback(by: 1.0 / 30.0)
        }
    }

    private func header(metrics: RepReviewMetricsState) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(metrics.repNumberText)
                .font(.title2)
                .fontWeight(.semibold)
            if !metrics.classificationLabels.isEmpty {
                RepReviewBadgeRow(labels: metrics.classificationLabels)
            }
            HStack {
                Button {
                    viewModel.openPreviousRep()
                } label: {
                    Label(metrics.previousRepLabel ?? "Previous Rep", systemImage: "chevron.left")
                }
                .buttonStyle(.bordered)
                .disabled(!metrics.canOpenPreviousRep)
                .accessibilityLabel(metrics.previousRepLabel.map { "Open previous repetition, \($0)" } ?? "Previous repetition unavailable")

                Spacer()

                Button {
                    viewModel.openNextRep()
                } label: {
                    Label(metrics.nextRepLabel ?? "Next Rep", systemImage: "chevron.right")
                }
                .buttonStyle(.bordered)
                .disabled(!metrics.canOpenNextRep)
                .accessibilityLabel(metrics.nextRepLabel.map { "Open next repetition, \($0)" } ?? "Next repetition unavailable")
            }
        }
    }

    private func playbackControls(ready: RepReviewReadyState) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Button {
                    if ready.playback.phase == .playing {
                        viewModel.pause()
                    } else {
                        viewModel.play()
                    }
                } label: {
                    Label(ready.playback.phase == .playing ? "Pause" : "Play", systemImage: ready.playback.phase == .playing ? "pause.fill" : "play.fill")
                }
                .buttonStyle(.borderedProminent)
                .accessibilityLabel(ready.playback.phase == .playing ? "Pause rep playback" : "Play rep playback")

                Button {
                    viewModel.stepToPreviousPoseSample()
                } label: {
                    Label("Previous Pose", systemImage: "backward.frame")
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("Step to previous stored pose sample")

                Button {
                    viewModel.stepToNextPoseSample()
                } label: {
                    Label("Next Pose", systemImage: "forward.frame")
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("Step to next stored pose sample")
            }

            Slider(
                value: Binding(
                    get: { ready.playback.currentTimeSeconds },
                    set: { viewModel.scrub(to: $0) }
                ),
                in: 0...max(ready.playback.durationSeconds, 0.01)
            )
            .accessibilityLabel("Rep playback position")
            .accessibilityValue("\(String(format: "%.2f", ready.playback.currentTimeSeconds)) seconds of \(String(format: "%.2f", ready.playback.durationSeconds)) seconds")

            HStack {
                Text("\(String(format: "%.2f", ready.playback.currentTimeSeconds)) s")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(String(format: "%.2f", ready.playback.durationSeconds)) s")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Picker("Playback speed", selection: Binding(
                get: { ready.playback.speed },
                set: { viewModel.setPlaybackSpeed($0) }
            )) {
                ForEach(RepPlaybackSpeed.allCases, id: \.self) { speed in
                    Text(speed.label).tag(speed)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityLabel("Playback speed")
        }
    }

    private func overlayControls(ready: RepReviewReadyState) -> some View {
        Toggle("Trajectory", isOn: Binding(
            get: { ready.playback.trajectoryVisible },
            set: { viewModel.setTrajectoryVisible($0) }
        ))
        .accessibilityLabel("Trajectory overlay")
    }

    private func compareLink(metrics: RepReviewMetricsState) -> some View {
        NavigationLink {
            GhostModeView(
                viewModel: GhostModeViewModel(
                    sessionID: metrics.sessionID,
                    referenceRepID: metrics.repID,
                    sessionRepository: sessionRepository,
                    poseAssetStore: poseAssetStore
                )
            )
        } label: {
            Label("Compare this Rep", systemImage: "square.stack.3d.up")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .accessibilityLabel("Compare this repetition in Ghost Mode")
    }

    private func metricsPanel(_ metrics: RepReviewMetricsState) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Metrics")
                .font(.headline)
            MetricRow(title: "Total Rep Duration", value: metrics.durationText)
            MetricRow(title: "Head Displacement", value: metrics.headDisplacementText)
            MetricRow(title: "Shoulder Displacement", value: metrics.shoulderDisplacementText)
            MetricRow(title: "Primary Wrist Path Length", value: metrics.wristPathLengthText)
            MetricRow(title: "Wrist Path Directness", value: metrics.wristDirectnessText)
        }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private func availabilityNote(_ note: String?) -> some View {
        if let note {
            Text(note)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private func degradedMessage(for reason: RepReviewDegradedReason) -> String {
        switch reason {
        case .videoNotRecorded:
            return "Original video was not recorded, but saved metrics remain available."
        case .missingPoseAsset:
            return "Saved pose data is missing. Metrics are still available."
        case .corruptPoseAsset:
            return "Saved pose data could not be decoded. Metrics are still available."
        case .unsupportedPoseEncoding:
            return "Saved pose data uses an unsupported format. Metrics are still available."
        case .poseAssetOwnershipFailed:
            return "Saved pose data did not match this session and repetition."
        case .emptyPosePayload:
            return "Saved pose data has no samples for this repetition."
        }
    }
}

private struct PosePlaybackCanvas: View {
    let ready: RepReviewReadyState
    private let mapper = PosePlaybackDisplayMapper(contentMode: .aspectFit)

    var body: some View {
        Canvas { context, size in
            let rect = CGRect(origin: .zero, size: size)
            context.fill(Path(rect), with: .color(Color(red: 0.09, green: 0.10, blue: 0.11)))

            if ready.playback.trajectoryVisible,
               let wrist = ready.primaryWristJointID {
                let points = PosePlaybackRenderer.trajectory(
                    jointID: wrist,
                    samples: ready.playback.orderedPoseSamples,
                    through: ready.playback.currentTimeSeconds,
                    in: size,
                    mapper: mapper
                )
                if points.count > 1 {
                    var path = Path()
                    path.move(to: points[0])
                    for point in points.dropFirst() {
                        path.addLine(to: point)
                    }
                    context.stroke(path, with: .color(.orange.opacity(0.8)), lineWidth: 3)
                }
            }

            guard ready.playback.skeletonVisible, let pose = ready.currentPose else {
                return
            }
            for segment in PosePlaybackRenderer.skeletonSegments(for: pose, in: size, mapper: mapper) {
                var path = Path()
                path.move(to: segment.start)
                path.addLine(to: segment.end)
                context.stroke(path, with: .color(.green), lineWidth: 3)
            }
            for point in PosePlaybackRenderer.jointPoints(for: pose, in: size, mapper: mapper).values {
                context.fill(Path(ellipseIn: CGRect(x: point.x - 4, y: point.y - 4, width: 8, height: 8)), with: .color(.white))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct MetricRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct RepReviewBadgeRow: View {
    let labels: [String]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(labels, id: \.self) { label in
                Text(label)
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.quaternary)
                    .clipShape(Capsule())
            }
        }
    }
}
