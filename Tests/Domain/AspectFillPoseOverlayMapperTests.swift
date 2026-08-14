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
}
