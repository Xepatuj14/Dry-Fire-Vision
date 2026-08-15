import Foundation
import SwiftUI

struct CalibrationPreviewView: View {
    let previewSession: CameraPreviewSession?
    let poseFrame: PoseFrame?
    let calibrationState: CalibrationReadinessState
    let recordingState: PoseRecordingState
    let selectedCameraPosition: CameraPosition
    let canSwitchCamera: Bool
    let switchCameraAction: () async -> Void
    let startRecordingAction: () async -> Void
    let stopRecordingAction: () async -> Void
    let cancelRecordingAction: () async -> Void

    var body: some View {
        ZStack(alignment: .topLeading) {
            if let previewSession {
                CameraPreviewView(previewSession: previewSession)
                    .ignoresSafeArea(edges: .bottom)
                    .accessibilityLabel("Live camera preview")
            } else {
                Color.black
                    .overlay {
                        Text("Preview unavailable")
                            .foregroundStyle(.white)
                    }
            }

            if let poseFrame {
                PoseSkeletonOverlayView(poseFrame: poseFrame)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(statusTitle)
                    .font(.headline)
                Text(statusMessage)
                    .font(.subheadline)
                recordingControls
            }
            .padding(12)
            .background(.thinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .padding()
            .accessibilityElement(children: .combine)

            if canSwitchCamera {
                VStack {
                    HStack {
                        Spacer()
                        Button {
                            Task {
                                await switchCameraAction()
                            }
                        } label: {
                            Image(systemName: "arrow.triangle.2.circlepath.camera")
                                .font(.title3)
                                .frame(width: 44, height: 44)
                        }
                        .buttonStyle(.bordered)
                        .tint(.primary)
                        .background(.thinMaterial)
                        .clipShape(Circle())
                        .accessibilityLabel("Switch camera")
                        .accessibilityValue(selectedCameraPosition.label)
                    }
                    Spacer()
                }
                .padding()
            }
        }
    }

    @ViewBuilder
    private var recordingControls: some View {
        switch recordingState {
        case .idle:
            Button {
                Task {
                    await startRecordingAction()
                }
            } label: {
                Label("Start", systemImage: "record.circle")
            }
            .buttonStyle(.borderedProminent)
            .accessibilityLabel("Start countdown")
        case .awaitingCalibration:
            EmptyView()
        case .countdown(let remainingSeconds):
            Text("\(remainingSeconds)")
                .font(.system(size: 56, weight: .bold))
                .accessibilityLabel("Countdown \(remainingSeconds)")
            Button("Cancel") {
                Task {
                    await cancelRecordingAction()
                }
            }
            .buttonStyle(.bordered)
        case .waitingForStartPosition:
            Text("Return to your starting position.")
        case .recording(let elapsedSeconds):
            HStack {
                Label("Recording", systemImage: "record.circle.fill")
                Text(String(format: "%.1f s", elapsedSeconds))
            }
            Button("Stop") {
                Task {
                    await stopRecordingAction()
                }
            }
            .buttonStyle(.borderedProminent)
            Button("Cancel") {
                Task {
                    await cancelRecordingAction()
                }
            }
            .buttonStyle(.bordered)
        case .completing:
            Text("Completing recording.")
        case .completed(let recording):
            Text("Pose recording complete: \(recording.poseFrames.count) samples.")
            Text("Ready for timestamped pose analysis in the next slice.")
                .font(.caption)
        case .cancelled:
            Text("Recording cancelled.")
        case .interrupted:
            Text("Recording interrupted.")
        case .failed(let error):
            Text("Recording failed: \(message(for: error))")
        }
    }

    private var statusTitle: String {
        switch calibrationState {
        case .startingCamera:
            return "Camera Starting"
        case .searchingForPerson:
            return "Step Into Frame"
        case .personDetected:
            return "Person Detected"
        case .adjust:
            return "Adjust Framing"
        case .multiplePeople:
            return "Clear the Frame"
        case .lowConfidence:
            return "Tracking Quality Low"
        case .holdStill:
            return "Hold Still"
        case .capturingBaseline:
            return "Capturing Baseline"
        case .ready:
            return "Ready"
        case .failed:
            return "Pose Detection Issue"
        }
    }

    private var statusMessage: String {
        switch calibrationState {
        case .startingCamera:
            return "Preparing pose detection."
        case .searchingForPerson:
            return "Stand where your whole body is visible."
        case .personDetected:
            return "Hold your starting position."
        case .adjust(let reason):
            return message(for: reason)
        case .multiplePeople:
            return "Only one person should be in frame."
        case .lowConfidence:
            return "Improve lighting or adjust clothing contrast."
        case .holdStill(let progress):
            return "Hold still: \(Int(progress * 100))%"
        case .capturingBaseline:
            return "Keep holding your starting position."
        case .ready:
            return "Calibration baseline captured."
        case .failed:
            return "Pose detection could not evaluate this frame."
        }
    }

    private func message(for error: PoseRecordingError) -> String {
        switch error {
        case .missingCalibration:
            return "calibration is required"
        case .notRecording:
            return "recording was not active"
        case .alreadyRecording:
            return "recording already active"
        case .noAcceptedFrames:
            return "no pose samples were captured"
        case .nonMonotonicTimestamp:
            return "pose timestamps were not ordered"
        case .unsupportedFixtureEncoding:
            return "unsupported fixture version"
        }
    }

    private func message(for reason: CalibrationAdjustmentReason) -> String {
        switch reason {
        case .stepBack:
            return "Step back so your body is not cropped."
        case .moveCloser:
            return "Move closer so your body is large enough to analyze."
        case .moveLeft:
            return "Move left."
        case .moveRight:
            return "Move right."
        case .keepHeadVisible:
            return "Keep your head visible."
        case .keepShouldersVisible:
            return "Keep both shoulders visible."
        case .keepWristsVisible:
            return "Keep both wrists visible."
        case .keepHipsVisible:
            return "Keep both hips visible."
        case .keepLegsAndFeetVisible:
            return "Keep your legs and feet visible."
        case .onlyOnePersonInFrame:
            return "Only one person should be in frame."
        case .holdStill:
            return "Hold still."
        }
    }
}
