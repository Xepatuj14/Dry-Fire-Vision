import CoreGraphics
import XCTest
@testable import DryFireVisionCore

final class AspectFillPoseOverlayMapperTests: XCTestCase {
    func testAspectFillMappingCentersCroppedImageVertically() {
        let mapper = AspectFillPoseOverlayMapper(sourceAspectRatio: 1)
        let sample = JointSample(jointID: .nose, x: 0.5, y: 0.5, confidence: 1)

        let point = mapper.displayPoint(for: sample, in: CGSize(width: 200, height: 100))

        XCTAssertEqual(point.x, 100, accuracy: 0.0001)
        XCTAssertEqual(point.y, 50, accuracy: 0.0001)
    }

    func testRearCameraMappingKeepsHorizontalCoordinateUnmirrored() {
        let mapper = AspectFillPoseOverlayMapper(sourceAspectRatio: 1, isMirrored: false)
        let sample = JointSample(jointID: .leftWrist, x: 0.25, y: 0.5, confidence: 1)

        let point = mapper.displayPoint(for: sample, in: CGSize(width: 100, height: 100))

        XCTAssertEqual(point.x, 25, accuracy: 0.0001)
        XCTAssertEqual(point.y, 50, accuracy: 0.0001)
    }

    func testFrontCameraMappingMirrorsHorizontalCoordinateForDisplay() {
        let mapper = AspectFillPoseOverlayMapper(sourceAspectRatio: 1, isMirrored: true)
        let sample = JointSample(jointID: .leftWrist, x: 0.25, y: 0.5, confidence: 1)

        let point = mapper.displayPoint(for: sample, in: CGSize(width: 100, height: 100))

        XCTAssertEqual(point.x, 75, accuracy: 0.0001)
        XCTAssertEqual(point.y, 50, accuracy: 0.0001)
    }

    func testMirroredCenterPointRemainsCentered() {
        let rearMapper = AspectFillPoseOverlayMapper(sourceAspectRatio: 1, isMirrored: false)
        let frontMapper = AspectFillPoseOverlayMapper(sourceAspectRatio: 1, isMirrored: true)
        let sample = JointSample(jointID: .nose, x: 0.5, y: 0.5, confidence: 1)

        let rearPoint = rearMapper.displayPoint(for: sample, in: CGSize(width: 100, height: 100))
        let frontPoint = frontMapper.displayPoint(for: sample, in: CGSize(width: 100, height: 100))

        XCTAssertEqual(rearPoint.x, 50, accuracy: 0.0001)
        XCTAssertEqual(frontPoint.x, 50, accuracy: 0.0001)
    }

    func testFrontCameraMappingAppliesOnlyOneDisplayMirrorAfterAspectFill() {
        let mapper = AspectFillPoseOverlayMapper(sourceAspectRatio: 1, isMirrored: true)
        let sample = JointSample(jointID: .rightWrist, x: 0.25, y: 0.5, confidence: 1)

        let point = mapper.displayPoint(for: sample, in: CGSize(width: 200, height: 100))

        XCTAssertEqual(point.x, 150, accuracy: 0.0001)
        XCTAssertEqual(point.y, 50, accuracy: 0.0001)
    }
}
