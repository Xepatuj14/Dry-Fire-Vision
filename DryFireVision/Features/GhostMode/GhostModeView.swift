import Combine
import SwiftUI

public struct GhostModeView: View {
    @StateObject private var viewModel: GhostModeViewModel
    private let playbackTimer = Timer.publish(every: 1.0 / 30.0, on: .main, in: .common).autoconnect()

    public init(viewModel: GhostModeViewModel) {
        self._viewModel = StateObject(wrappedValue: viewModel)
    }

    public var body: some View {
        Group {
            switch viewModel.state {
            case .loading:
                ProgressView("Loading Ghost Mode")
            case .selectingRep(let selection):
                selectionView(selection)
            case .preparingComparison(let selection):
                VStack(spacing: 16) {
                    ProgressView()
                    Text("Preparing Movement Comparison")
                        .font(.headline)
                    Text("Loading saved pose data for \(selection.reference.repNumberText) and the selected repetition.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding()
            case .ready(let ready):
                viewer(ready)
            case .incompatible(let unavailable), .insufficientData(let unavailable):
                unavailableView(unavailable)
            case .failed(let message):
                PlaceholderStateView(title: "Ghost Mode Unavailable", message: message, systemImage: "exclamationmark.triangle")
                    .padding()
            }
        }
        .navigationTitle("Ghost Mode")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            viewModel.loadSelection()
        }
        .onReceive(playbackTimer) { _ in
            viewModel.advancePlayback(by: 1.0 / 30.0)
        }
    }

    private func selectionView(_ selection: GhostRepSelectionState) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Compare Repetitions")
                    .font(.title2)
                    .fontWeight(.semibold)

                GhostSelectionCard(title: "Reference Rep", candidate: selection.reference)

                Text("Choose Rep B")
                    .font(.headline)
                if let message = selection.noCompatibleMessage {
                    PlaceholderStateView(title: "No Compatible Reps", message: message, systemImage: "figure.arms.open")
                }

                ForEach(selection.candidates) { candidate in
                    Button {
                        viewModel.chooseCandidate(repID: candidate.id)
                    } label: {
                        GhostSelectionCard(title: candidate.isRepresentativeSuggestion ? "Suggested Comparison" : "Candidate", candidate: candidate)
                    }
                    .buttonStyle(.plain)
                    .disabled(!candidate.isCompatible)
                    .accessibilityLabel("\(candidate.repNumberText), \(candidate.compatibilityText)")
                }
            }
            .padding()
        }
    }

    private func viewer(_ ready: GhostModeReadyState) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                repLabels(ready.metrics)
                GhostComparisonCanvas(ready: ready)
                    .frame(maxWidth: .infinity)
                    .aspectRatio(9.0 / 16.0, contentMode: .fit)
                    .accessibilityLabel("Ghost Mode comparison canvas for Rep A and Rep B")
                Text(ready.videoUnavailableMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                playbackControls(ready)
                overlayControls(ready)
                comparisonPanel(ready.metrics)
                Button {
                    viewModel.chooseAnotherRep()
                } label: {
                    Label("Choose Another Rep", systemImage: "list.bullet")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("Choose another comparison repetition")
            }
            .padding()
        }
    }

    private func unavailableView(_ unavailable: GhostUnavailableState) -> some View {
        ScrollView {
            VStack(spacing: 16) {
                PlaceholderStateView(title: unavailable.title, message: unavailable.message, systemImage: "figure.arms.open")
                if unavailable.selection != nil {
                    Button {
                        viewModel.chooseAnotherRep()
                    } label: {
                        Label("Choose Another Rep", systemImage: "list.bullet")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding()
        }
    }

    private func repLabels(_ metrics: GhostComparisonMetricsState) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Compare Repetitions")
                .font(.title2)
                .fontWeight(.semibold)
            HStack(alignment: .top, spacing: 12) {
                GhostRepLegend(title: metrics.repALabel, symbol: "A", labels: metrics.repAClassifications, color: .green)
                GhostRepLegend(title: metrics.repBLabel, symbol: "B", labels: metrics.repBClassifications, color: .orange)
            }
        }
    }

    private func playbackControls(_ ready: GhostModeReadyState) -> some View {
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
                .accessibilityLabel(ready.playback.phase == .playing ? "Pause Ghost Mode playback" : "Play Ghost Mode playback")

                Picker("Playback speed", selection: Binding(
                    get: { ready.playback.speed },
                    set: { viewModel.setPlaybackSpeed($0) }
                )) {
                    ForEach(RepPlaybackSpeed.allCases, id: \.self) { speed in
                        Text(speed.label).tag(speed)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityLabel("Ghost Mode playback speed")
            }

            Slider(
                value: Binding(
                    get: { ready.playback.currentPhase },
                    set: { viewModel.scrub(to: $0) }
                ),
                in: 0...1
            )
            .accessibilityLabel("Normalized phase position")
            .accessibilityValue("\(Int((ready.playback.currentPhase * 100).rounded())) percent")

            HStack {
                Text("0%")
                Spacer()
                Text("\(Int((ready.playback.currentPhase * 100).rounded()))%")
                    .fontWeight(.semibold)
                Spacer()
                Text("100%")
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            Text("Timing mode: \(ready.playback.timingMode.label)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .accessibilityLabel("Timing mode \(ready.playback.timingMode.label). Rep starts align at zero percent and completions align at one hundred percent.")
        }
    }

    private func overlayControls(_ ready: GhostModeReadyState) -> some View {
        Toggle("Trajectories", isOn: Binding(
            get: { ready.playback.trajectoryVisible },
            set: { viewModel.setTrajectoryVisible($0) }
        ))
        .accessibilityLabel("Trajectory overlays")
    }

    private func comparisonPanel(_ metrics: GhostComparisonMetricsState) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Movement Comparison")
                .font(.headline)
            GhostMetricRow(title: metrics.repALabel, value: metrics.repADurationText)
            GhostMetricRow(title: metrics.repBLabel, value: metrics.repBDurationText)
            GhostMetricRow(title: "Duration Difference", value: metrics.durationDifferenceText)
            Text(metrics.headDifferenceText)
            Text(metrics.shoulderDifferenceText)
            Text(metrics.wristPathDifferenceText)
            Text(metrics.wristDirectnessDifferenceText)
            GhostMetricRow(title: "Movement Similarity", value: metrics.similarityText)
            if let confidence = metrics.confidenceText {
                Text(confidence)
                    .foregroundStyle(.secondary)
            }
        }
        .font(.subheadline)
        .accessibilityElement(children: .contain)
    }
}

private struct GhostComparisonCanvas: View {
    let ready: GhostModeReadyState
    private let lookup = GhostPoseLookup()

    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(red: 0.08, green: 0.09, blue: 0.10)))
            let mapper = GhostDisplayMapper(alignedRepA: ready.playback.alignedRepA, alignedRepB: ready.playback.alignedRepB)

            if ready.playback.trajectoryVisible,
               let wrist = ready.primaryWristJointID {
                drawTrajectory(
                    lookup.trajectory(jointID: wrist, in: ready.playback.alignedRepA, through: ready.playback.currentPhase),
                    color: .green,
                    context: &context,
                    size: size,
                    mapper: mapper
                )
                drawTrajectory(
                    lookup.trajectory(jointID: wrist, in: ready.playback.alignedRepB, through: ready.playback.currentPhase),
                    color: .orange,
                    context: &context,
                    size: size,
                    mapper: mapper
                )
            }

            if let poseA = ready.currentPoseA {
                drawPose(poseA, color: .green, context: &context, size: size, mapper: mapper)
            }
            if let poseB = ready.currentPoseB {
                drawPose(poseB, color: .orange, context: &context, size: size, mapper: mapper)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func drawTrajectory(
        _ joints: [RepPlaybackJoint],
        color: Color,
        context: inout GraphicsContext,
        size: CGSize,
        mapper: GhostDisplayMapper
    ) {
        let points = GhostPlaybackRenderer.trajectory(joints: joints, in: size, mapper: mapper)
        guard points.count > 1 else {
            return
        }
        var path = Path()
        path.move(to: points[0])
        for point in points.dropFirst() {
            path.addLine(to: point)
        }
        context.stroke(path, with: .color(color.opacity(0.75)), lineWidth: 3)
    }

    private func drawPose(
        _ pose: GhostPlaybackPose,
        color: Color,
        context: inout GraphicsContext,
        size: CGSize,
        mapper: GhostDisplayMapper
    ) {
        for segment in GhostPlaybackRenderer.skeletonSegments(for: pose, in: size, mapper: mapper) {
            var path = Path()
            path.move(to: segment.start)
            path.addLine(to: segment.end)
            context.stroke(path, with: .color(color), lineWidth: 3)
        }
        for point in GhostPlaybackRenderer.jointPoints(for: pose, in: size, mapper: mapper).values {
            context.fill(Path(ellipseIn: CGRect(x: point.x - 4, y: point.y - 4, width: 8, height: 8)), with: .color(.white))
        }
    }
}

private struct GhostSelectionCard: View {
    let title: String
    let candidate: GhostRepCandidateState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Text(candidate.repNumberText)
                    .font(.headline)
                Spacer()
                Text(candidate.durationText)
                    .foregroundStyle(.secondary)
            }
            if !candidate.classificationLabels.isEmpty {
                GhostBadgeRow(labels: candidate.classificationLabels)
            }
            Text(candidate.compatibilityText)
                .font(.caption)
                .foregroundStyle(candidate.isCompatible ? Color.secondary : Color.red)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct GhostRepLegend: View {
    let title: String
    let symbol: String
    let labels: [String]
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(symbol)
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundStyle(.white)
                    .frame(width: 22, height: 22)
                    .background(color)
                    .clipShape(Circle())
                Text(title)
                    .font(.headline)
            }
            if !labels.isEmpty {
                GhostBadgeRow(labels: labels)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

private struct GhostMetricRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct GhostBadgeRow: View {
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
