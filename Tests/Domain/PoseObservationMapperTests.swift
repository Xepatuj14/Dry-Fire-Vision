import XCTest
@testable import DryFireVisionCore

final class PoseObservationMapperTests: XCTestCase {
    func testCoordinateConversionUsesTopLeftOrigin() {
        let converter = PoseCoordinateConverter()

        let point = converter.domainPointFromVisionNormalizedPoint(x: 0.25, y: 0.75)

        XCTAssertEqual(point?.x, 0.25)
        XCTAssertEqual(point?.y, 0.25)
    }

    func testMapperPreservesJointIdentityConfidenceAndTimestamp() {
        let mapper = PoseObservationMapper()

        let frame = mapper.map(
            joints: [
                VisionJointObservation(jointID: .leftWrist, x: 0.2, y: 0.3, confidence: 0.82)
            ],
            timestampSeconds: 12.34
        )

        XCTAssertEqual(frame.timestampSeconds, 12.34)
        XCTAssertEqual(frame.sample(for: .leftWrist)?.jointID, .leftWrist)
        XCTAssertEqual(frame.sample(for: .leftWrist)?.confidence, 0.82)
        XCTAssertEqual(frame.sample(for: .leftWrist)?.x, 0.2)
        XCTAssertEqual(frame.sample(for: .leftWrist)?.y, 0.7)
    }

    func testMissingJointsRemainMissing() {
        let mapper = PoseObservationMapper()

        let frame = mapper.map(joints: [], timestampSeconds: 1)

        XCTAssertNil(frame.sample(for: .rightWrist))
        XCTAssertTrue(frame.joints.isEmpty)
    }
}
