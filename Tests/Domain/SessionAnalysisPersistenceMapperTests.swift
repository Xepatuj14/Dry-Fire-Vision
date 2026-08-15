import DryFireVisionCore
import DryFireVisionTestFixtures
import XCTest

final class SessionAnalysisPersistenceMapperTests: XCTestCase {
    func testSessionRecordPersistsCameraPositionFromRecordingMetadata() async throws {
        let source = SessionAnalysisFixtureFactory.recording(.good10)
        let recording = PoseRecording(
            id: source.id,
            startTimestampSeconds: source.startTimestampSeconds,
            endTimestampSeconds: source.endTimestampSeconds,
            poseFrames: source.poseFrames,
            calibrationResult: source.calibrationResult,
            metadata: PoseRecordingMetadata(
                cameraPerspective: source.metadata.cameraPerspective,
                cameraPosition: CameraPosition.rear.rawValue,
                captureOrientation: source.metadata.captureOrientation,
                nominalCaptureFPS: source.metadata.nominalCaptureFPS,
                effectivePoseFPS: source.metadata.effectivePoseFPS,
                acceptedPoseFrameCount: source.metadata.acceptedPoseFrameCount,
                rejectedPoseFrameCount: source.metadata.rejectedPoseFrameCount
            )
        )

        let analysis = try await SessionAnalysisPipeline().analyze(AnalysisInput(
            recording: recording,
            targetRepCount: 10,
            configuration: .resultsFixtureConfiguration
        ))
        let record = try SessionAnalysisPersistenceMapper.makeSessionRecord(from: analysis)

        XCTAssertEqual(record.cameraPosition, CameraPosition.rear.rawValue)
    }
}
