import DryFireVisionCore
import XCTest

final class MetricGeometryTests: XCTestCase {
    func testEuclideanDistance() throws {
        let distance = try XCTUnwrap(MetricMath.euclideanDistance(x1: 0, y1: 0, x2: 3, y2: 4))

        XCTAssertEqual(distance, 5, accuracy: 0.0001)
    }

    func testCumulativePathLength() throws {
        let path = try XCTUnwrap(MetricMath.pathLength([
            NormalizedJointPosition(timestampSeconds: 0, x: 0, y: 0, confidence: 0.9),
            NormalizedJointPosition(timestampSeconds: 0.1, x: 3, y: 4, confidence: 0.9),
            NormalizedJointPosition(timestampSeconds: 0.2, x: 6, y: 8, confidence: 0.9)
        ]))

        XCTAssertEqual(path, 10, accuracy: 0.0001)
    }

    func testNonFiniteDistanceIsUnavailable() {
        XCTAssertNil(MetricMath.euclideanDistance(x1: .infinity, y1: 0, x2: 1, y2: 1))
    }
}
