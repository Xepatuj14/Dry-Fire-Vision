import Foundation

#if canImport(Vision) && canImport(CoreMedia)
import CoreMedia
import Vision
#endif

public struct VisionPoseDetector: PoseDetecting {
    private let mapper: PoseObservationMapper

    public init(mapper: PoseObservationMapper = PoseObservationMapper()) {
        self.mapper = mapper
    }

    public func detectPoses(in frame: CameraFrame) async throws -> PoseDetectionResult {
        #if canImport(Vision) && canImport(CoreMedia)
        guard let sampleBuffer = frame.sampleBuffer else {
            throw PoseDetectionError.invalidObservation
        }

        // Vision work is isolated from MainActor-bound feature state so preview rendering stays responsive.
        return try await Task.detached(priority: .userInitiated) {
            let request = VNDetectHumanBodyPoseRequest()
            let handler = VNImageRequestHandler(cmSampleBuffer: sampleBuffer, orientation: .right, options: [:])

            do {
                try handler.perform([request])
            } catch {
                throw PoseDetectionError.visionRequestFailed
            }

            let observations = request.results ?? []
            let poseFrames = observations.map { observation in
                mapper.map(
                    joints: Self.domainJointObservations(from: observation),
                    timestampSeconds: frame.timestampSeconds
                )
            }

            return PoseDetectionResult(poseFrames: poseFrames)
        }.value
        #else
        throw PoseDetectionError.unsupportedPoseRequest
        #endif
    }

    #if canImport(Vision)
    private static func domainJointObservations(from observation: VNHumanBodyPoseObservation) -> [VisionJointObservation] {
        let recognizedPoints = (try? observation.recognizedPoints(.all)) ?? [:]
        let mapping: [(VNHumanBodyPoseObservation.JointName, PoseJointID)] = [
            (.nose, .nose),
            (.leftShoulder, .leftShoulder),
            (.rightShoulder, .rightShoulder),
            (.leftElbow, .leftElbow),
            (.rightElbow, .rightElbow),
            (.leftWrist, .leftWrist),
            (.rightWrist, .rightWrist),
            (.leftHip, .leftHip),
            (.rightHip, .rightHip),
            (.leftKnee, .leftKnee),
            (.rightKnee, .rightKnee),
            (.leftAnkle, .leftAnkle),
            (.rightAnkle, .rightAnkle)
        ]

        return mapping.compactMap { visionJoint, domainJoint in
            guard let point = recognizedPoints[visionJoint], point.confidence > 0 else {
                return nil
            }

            return VisionJointObservation(
                jointID: domainJoint,
                x: Double(point.location.x),
                y: Double(point.location.y),
                confidence: Double(point.confidence)
            )
        }
    }
    #endif
}
