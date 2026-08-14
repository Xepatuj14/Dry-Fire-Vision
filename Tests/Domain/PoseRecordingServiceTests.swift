import DryFireVisionTestFixtures
import XCTest
@testable import DryFireVisionCore

final class PoseRecordingServiceTests: XCTestCase {
    func testCannotAcceptPoseBeforeRecordingStarts() async {
        let service = PoseRecordingService()

        do {
            try await service.accept(SyntheticPoseFixtures.centeredFullBodyPerson())
            XCTFail("Expected notRecording error")
        } catch PoseRecordingError.notRecording {
            XCTAssertTrue(true)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testManualStopProducesCompletedRecordingWithRelativeTimestamps() async throws {
        let service = PoseRecordingService()
        let calibration = SyntheticPoseFixtures.calibrationResult()
        let frames = [
            SyntheticPoseFixtures.centeredFullBodyPerson(timestampSeconds: 10.0),
            SyntheticPoseFixtures.centeredFullBodyPerson(timestampSeconds: 10.034),
            SyntheticPoseFixtures.centeredFullBodyPerson(timestampSeconds: 10.118)
        ]
        let recordingID = UUID(uuidString: "00000000-0000-0000-0000-000000000101") ?? UUID()

        try await service.start(
            id: recordingID,
            calibrationResult: calibration,
            startTimestampSeconds: 10.0,
            metadata: PoseRecordingMetadata(nominalCaptureFPS: 60)
        )
        for frame in frames {
            try await service.accept(frame)
        }
        let recording = try await service.finish()

        XCTAssertEqual(recording.poseFrames.map(\.timestampSeconds), [0.0, 0.034, 0.118])
        XCTAssertEqual(recording.calibrationResult, calibration)
        XCTAssertEqual(recording.metadata.nominalCaptureFPS, 60)
        XCTAssertEqual(recording.metadata.acceptedPoseFrameCount, 3)
        XCTAssertEqual(recording.durationSeconds, 0.118, accuracy: 0.0001)
    }

    func testIrregularIntervalsRemainIntact() async throws {
        let recording = try await makeRecording(from: SyntheticPoseFixtures.irregularCadenceRecordingFrames())

        XCTAssertEqual(recording.poseFrames.map(\.timestampSeconds), [0.0, 0.034, 0.067, 0.118, 0.151])
    }

    func testDroppedAnalysisIntervalDoesNotCreateSyntheticFrames() async throws {
        let recording = try await makeRecording(from: SyntheticPoseFixtures.droppedAnalysisIntervalFrames())

        XCTAssertEqual(recording.poseFrames.count, 5)
        XCTAssertEqual(recording.poseFrames.map(\.timestampSeconds), [0.0, 0.033, 0.066, 0.5, 0.533])
    }

    func testMissingJointRemainsMissingAndConfidenceRemainsIntact() async throws {
        let frames = [
            SyntheticPoseFixtures.centeredFullBodyPerson(timestampSeconds: 3.0),
            SyntheticPoseFixtures.missingWrist(timestampSeconds: 3.1),
            SyntheticPoseFixtures.lowConfidenceWrist(timestampSeconds: 3.2)
        ]

        let recording = try await makeRecording(from: frames, startTimestampSeconds: 3.0)

        XCTAssertNil(recording.poseFrames[1].sample(for: .leftWrist))
        XCTAssertEqual(recording.poseFrames[2].sample(for: .leftWrist)?.confidence, 0.1)
    }

    func testOutOfOrderTimestampIsRejectedAndFlagged() async throws {
        let service = PoseRecordingService()
        try await service.start(
            calibrationResult: SyntheticPoseFixtures.calibrationResult(),
            startTimestampSeconds: 5.0
        )
        try await service.accept(SyntheticPoseFixtures.centeredFullBodyPerson(timestampSeconds: 5.2))

        do {
            try await service.accept(SyntheticPoseFixtures.centeredFullBodyPerson(timestampSeconds: 5.1))
            XCTFail("Expected nonMonotonicTimestamp error")
        } catch PoseRecordingError.nonMonotonicTimestamp(let previous, let next) {
            XCTAssertEqual(previous, 0.2, accuracy: 0.0001)
            XCTAssertEqual(next, 0.1, accuracy: 0.0001)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testCancelPreventsFakeCompletedRecording() async throws {
        let service = PoseRecordingService()
        try await service.start(
            calibrationResult: SyntheticPoseFixtures.calibrationResult(),
            startTimestampSeconds: 0
        )
        await service.cancel()

        do {
            _ = try await service.finish()
            XCTFail("Expected notRecording after cancellation")
        } catch PoseRecordingError.notRecording {
            XCTAssertTrue(true)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testInterruptPreventsCompletedRecording() async throws {
        let service = PoseRecordingService()
        try await service.start(
            calibrationResult: SyntheticPoseFixtures.calibrationResult(),
            startTimestampSeconds: 0
        )
        await service.interrupt()

        do {
            _ = try await service.finish()
            XCTFail("Expected notRecording after interruption")
        } catch PoseRecordingError.notRecording {
            XCTAssertTrue(true)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testEffectivePoseCadenceIsDerivedFromTimestamps() async throws {
        let recording = try await makeRecording(from: SyntheticPoseFixtures.irregularCadenceRecordingFrames())

        XCTAssertEqual(recording.metadata.effectivePoseFPS ?? 0, Double(5) / 0.151, accuracy: 0.0001)
    }

    private func makeRecording(
        from frames: [PoseFrame],
        startTimestampSeconds: Double? = nil
    ) async throws -> PoseRecording {
        let service = PoseRecordingService()
        let start = startTimestampSeconds ?? frames[0].timestampSeconds
        try await service.start(
            calibrationResult: SyntheticPoseFixtures.calibrationResult(),
            startTimestampSeconds: start
        )
        for frame in frames {
            try await service.accept(frame)
        }
        return try await service.finish()
    }
}
