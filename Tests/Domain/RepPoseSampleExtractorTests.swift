import DryFireVisionCore
import DryFireVisionTestFixtures
import XCTest

final class RepPoseSampleExtractorTests: XCTestCase {
    func testExtractsSamplesByTimestampInChronologicalOrder() {
        let recording = SyntheticPoseFixtures.segmentationRecording(fixtureID: .good10)
        let segment = RepSegment(
            id: UUID(uuid: (4, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1)),
            sequenceIndex: 0,
            startTimestampSeconds: 0.40,
            activeMovementEndTimestampSeconds: nil,
            completeTimestampSeconds: 0.75,
            validity: .valid,
            confidenceStatus: .high,
            diagnosticReason: .none
        )

        let samples = RepPoseSampleExtractor().samples(for: segment, in: recording)

        XCTAssertFalse(samples.isEmpty)
        XCTAssertTrue(samples.allSatisfy { $0.timestampSeconds >= 0.40 && $0.timestampSeconds <= 0.75 })
        XCTAssertEqual(samples.map(\.timestampSeconds), samples.map(\.timestampSeconds).sorted())
    }
}
