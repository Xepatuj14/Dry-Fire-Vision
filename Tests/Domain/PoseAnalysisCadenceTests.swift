import XCTest
@testable import DryFireVisionCore

final class PoseAnalysisCadenceTests: XCTestCase {
    func testCadenceSkipsFramesWithoutChangingTimestamps() {
        var cadence = PoseAnalysisCadence(minimumIntervalSeconds: 0.1)

        XCTAssertTrue(cadence.shouldAnalyze(timestampSeconds: 10.0))
        XCTAssertFalse(cadence.shouldAnalyze(timestampSeconds: 10.05))
        XCTAssertTrue(cadence.shouldAnalyze(timestampSeconds: 10.11))
    }
}
