import SwiftUI

struct PoseSkeletonOverlayView: View {
    let poseFrame: PoseFrame
    let cameraPosition: CameraPosition

    var body: some View {
        GeometryReader { geometry in
            Canvas { context, size in
                for connection in Self.connections {
                    guard
                        let start = poseFrame.sample(for: connection.0),
                        let end = poseFrame.sample(for: connection.1)
                    else {
                        continue
                    }

                    var path = Path()
                    let startPoint = displayPoint(for: start, size: size)
                    let endPoint = displayPoint(for: end, size: size)
                    path.move(to: startPoint)
                    path.addLine(to: endPoint)
                    context.stroke(path, with: .color(.green), lineWidth: 3)
                }

                for sample in poseFrame.joints.values {
                    let point = displayPoint(for: sample, size: size)
                    let rect = CGRect(x: point.x - 4, y: point.y - 4, width: 8, height: 8)
                    context.fill(Path(ellipseIn: rect), with: .color(.white))
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
    }

    private func displayPoint(for sample: JointSample, size: CGSize) -> CGPoint {
        let mapper = AspectFillPoseOverlayMapper(isMirrored: cameraPosition == .front)
        return mapper.displayPoint(for: sample, in: size)
    }

    private static let connections: [(PoseJointID, PoseJointID)] = [
        (.nose, .leftShoulder),
        (.nose, .rightShoulder),
        (.leftShoulder, .rightShoulder),
        (.leftShoulder, .leftElbow),
        (.leftElbow, .leftWrist),
        (.rightShoulder, .rightElbow),
        (.rightElbow, .rightWrist),
        (.leftShoulder, .leftHip),
        (.rightShoulder, .rightHip),
        (.leftHip, .rightHip),
        (.leftHip, .leftKnee),
        (.leftKnee, .leftAnkle),
        (.rightHip, .rightKnee),
        (.rightKnee, .rightAnkle)
    ]
}
